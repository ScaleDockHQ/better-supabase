import type { CliEnv } from "../env.ts";
import type { SharedMemorySegment, SharedMemoryUsage } from "../shm.ts";
import type { Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";
import { readSharedMemory } from "../shm.ts";
import { branchName, listStacks, type ManagedStack } from "../stacks.ts";

/** The segment use and the managed stacks, for BS700 and BS701. */
export type LocalStackCheck =
  | {
      readonly memory: SharedMemoryUsage;
      /** Read only when a finding names stacks. */
      readonly stacks: readonly ManagedStack[];
    }
  | { readonly skipped: string };

/** The share of the segment limit in use from which BS700 warns. */
const SEGMENT_WARNING_SHARE = 0.8;

/**
 * Larger than the interlock segment every postmaster keeps (56 bytes), so
 * the stack keeps its shared buffers in System V memory.
 */
const SYSV_SEGMENT_BYTES = 1024 * 1024;

const nearLimit = (memory: SharedMemoryUsage): boolean =>
  memory.limit !== undefined &&
  memory.segments.length >= memory.limit * SEGMENT_WARNING_SHARE;

function segmentsByStack(
  segments: readonly SharedMemorySegment[],
): ReadonlyMap<string, readonly SharedMemorySegment[]> {
  const byStack = new Map<string, SharedMemorySegment[]>();

  for (const segment of segments) {
    if (segment.stackId !== undefined) {
      byStack.set(segment.stackId, [
        ...(byStack.get(segment.stackId) ?? []),
        segment,
      ]);
    }
  }

  return byStack;
}

/** Stacks that hold more than the interlock segment, so they use `sysv`. */
function sysvStacks(
  memory: SharedMemoryUsage,
): readonly (readonly [string, readonly SharedMemorySegment[]])[] {
  return [...segmentsByStack(memory.segments)].filter(
    ([, segments]) =>
      segments.length > 1 ||
      segments.some((segment) => (segment.bytes ?? 0) > SYSV_SEGMENT_BYTES),
  );
}

export async function loadLocalStackCheck(
  root: string,
  env: CliEnv,
): Promise<LocalStackCheck> {
  try {
    const memory = await readSharedMemory(root, env);

    if (!memory.supported) {
      return { skipped: "ipcs is not available." };
    }

    const named = nearLimit(memory) || sysvStacks(memory).length > 0;

    const stacks = named ? await listStacks(root, env).catch(() => []) : [];

    return { memory, stacks };
  } catch (cause) {
    return { skipped: errorText(cause) };
  }
}

function stackName(id: string, stacks: readonly ManagedStack[]): string {
  const stack = stacks.find((each) => each.id === id);

  return stack === undefined
    ? id.slice(0, 12)
    : `${id.slice(0, 12)} (${branchName(stack.branch)} in ${stack.projectRoot})`;
}

/** Stacks BS700 names before it points at `stack ls`. */
const NAMED_STACKS = 5;

const megabytes = (bytes: number): string =>
  `${(bytes / (1024 * 1024)).toFixed(0)} MB`;

/** Checks on the machine's local stacks (BS700, BS701). */
export const STACK_RULES: readonly Rule[] = [
  {
    code: "BS700",
    severity: "warning",
    title: "Shared memory segments almost used up",
    description:
      "Every running Postgres holds one System V shared memory segment, even with shared_memory_type = mmap. When the segment limit (32 on macOS) is reached, the next stack or shadow database fails with `could not create shared memory segment: No space left on device`. Prune stacks you no longer need with `better-supabase stack prune --stop-idle`, or raise the limit (`kern.sysv.shmmni` on macOS, `kernel.shmmni` on Linux).",
    check: ({ localStacks }) => {
      if (
        localStacks === undefined ||
        "skipped" in localStacks ||
        !nearLimit(localStacks.memory)
      ) {
        return [];
      }

      const { memory, stacks } = localStacks;

      const holders = [...segmentsByStack(memory.segments).keys()].map((id) =>
        stackName(id, stacks),
      );

      const named = holders.slice(0, NAMED_STACKS).join(", ");

      const more =
        holders.length > NAMED_STACKS
          ? ` and ${String(holders.length - NAMED_STACKS)} more (better-supabase stack ls lists them)`
          : "";

      return [
        {
          target: "kern.sysv.shmmni",
          message: `${String(memory.segments.length)} of ${String(memory.limit)} shared memory segments are in use${holders.length === 0 ? "" : `, ${String(holders.length)} of them by managed stacks: ${named}${more}`}. Run better-supabase stack prune --stop-idle to free them.`,
        },
      ];
    },
  },
  {
    code: "BS701",
    severity: "warning",
    title: "Local stack uses System V shared memory",
    description:
      "A stack whose Postgres runs with shared_memory_type or dynamic_shared_memory_type set to sysv holds its shared buffers and parallel query memory in System V segments, which fills the segment limit quickly. The defaults on macOS and Linux are mmap and posix; remove the override from the stack's Postgres settings.",
    check: ({ localStacks }) =>
      localStacks === undefined || "skipped" in localStacks
        ? []
        : sysvStacks(localStacks.memory).map(([id, segments]) => {
            const bytes = segments.reduce(
              (sum, segment) => sum + (segment.bytes ?? 0),
              0,
            );

            return {
              target: id,
              message: `Stack ${stackName(id, localStacks.stacks)} holds ${String(segments.length)} shared memory segment(s)${bytes > 0 ? ` (${megabytes(bytes)})` : ""}, so it sets shared_memory_type or dynamic_shared_memory_type to sysv. Use mmap and posix, the defaults.`,
            };
          }),
  },
];
