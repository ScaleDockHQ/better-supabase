import type { CliEnv } from "./env.ts";

import { type RunProcess, runProcess } from "./exec.ts";

export interface SharedMemorySegment {
  readonly id: string;
  /** The process that created the segment. */
  readonly pid: number;
  /** The managed stack whose postmaster holds it, when one does. */
  readonly stackId?: string;
}

export interface SharedMemoryUsage {
  /** False where `ipcs` is missing (Windows), so nothing was read. */
  readonly supported: boolean;
  /** The system-wide segment limit (`kern.sysv.shmmni`, `kernel.shmmni`). */
  readonly limit?: number;
  readonly segments: readonly SharedMemorySegment[];
}

const DIGITS = /^\d+$/;

/**
 * The segment ids and creator PIDs from `ipcs -m -p`. macOS prints
 * `m <id> <key> <mode> <owner> <group> <cpid> <lpid>`, Linux prints
 * `<shmid> <owner> <cpid> <lpid>` under a header.
 */
export function parseIpcs(
  stdout: string,
): readonly { readonly id: string; readonly pid: number }[] {
  const rows: { id: string; pid: number }[] = [];

  for (const line of stdout.split("\n")) {
    const fields = line.trim().split(/\s+/);

    if (fields[0] === "m" && fields.length >= 8) {
      const [, id, , , , , cpid] = fields;

      if (id !== undefined && cpid !== undefined && DIGITS.test(cpid)) {
        rows.push({ id, pid: Number(cpid) });
      }
    } else if (
      fields.length === 4 &&
      fields.every((f, i) => i === 1 || DIGITS.test(f))
    ) {
      const [id, , cpid] = fields;

      if (id !== undefined && cpid !== undefined) {
        rows.push({ id, pid: Number(cpid) });
      }
    }
  }

  return rows;
}

const STACK_DATA_DIR = /[/\\]\.supabase[/\\]stacks[/\\]([0-9a-f]{12,})[/\\]/;

/** The managed stack id in a postmaster's command line (`-D ~/.supabase/stacks/<id>/...`). */
export function stackIdOf(command: string): string | undefined {
  return STACK_DATA_DIR.exec(command)?.[1];
}

/** `pid command` lines from `ps -o pid=,command=`. */
export function parsePs(stdout: string): ReadonlyMap<number, string> {
  const commands = new Map<number, string>();

  for (const line of stdout.split("\n")) {
    const match = /^\s*(\d+)\s+(.*)$/.exec(line);

    if (match?.[1] !== undefined && match[2] !== undefined) {
      commands.set(Number(match[1]), match[2]);
    }
  }

  return commands;
}

async function segmentLimit(
  root: string,
  env: CliEnv,
  run: RunProcess,
  platform: NodeJS.Platform,
): Promise<number | undefined> {
  const result =
    platform === "linux"
      ? await run("cat", ["/proc/sys/kernel/shmmni"], root, env)
      : await run("sysctl", ["-n", "kern.sysv.shmmni"], root, env);

  const value = Number(result.stdout.trim());

  return result.code === 0 && Number.isInteger(value) && value > 0
    ? value
    : undefined;
}

/**
 * The System V shared memory segments in use, each tied to the managed
 * stack whose postmaster created it. Every running Postgres keeps one small
 * segment as an interlock, even with `shared_memory_type = mmap`, so the
 * segment limit caps how many stacks and shadow databases run at once.
 */
export async function readSharedMemory(
  root: string,
  env: CliEnv,
  run: RunProcess = runProcess,
  platform: NodeJS.Platform = process.platform,
): Promise<SharedMemoryUsage> {
  const ipcs = await run("ipcs", ["-m", "-p"], root, env);

  if (ipcs.code !== 0) {
    return { supported: false, segments: [] };
  }

  const rows = parseIpcs(ipcs.stdout);
  const limit = await segmentLimit(root, env, run, platform);
  const pids = [...new Set(rows.map((row) => row.pid))];

  const ps =
    pids.length === 0
      ? undefined
      : await run(
          "ps",
          ["-o", "pid=,command=", "-p", pids.join(",")],
          root,
          env,
        );

  const commands =
    ps === undefined ? new Map<number, string>() : parsePs(ps.stdout);

  const segments = rows.map((row): SharedMemorySegment => {
    const command = commands.get(row.pid);
    const stackId = command === undefined ? undefined : stackIdOf(command);

    return stackId === undefined ? row : { ...row, stackId };
  });

  return {
    supported: true,
    ...(limit === undefined ? {} : { limit }),
    segments,
  };
}
