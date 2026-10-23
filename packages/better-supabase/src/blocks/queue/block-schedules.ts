import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BlockSchedule } from "../../core/automation.ts";
import type { Result } from "../../core/result.ts";
import type { ScheduleDefinition } from "./types.ts";

/** The queue every block timer enqueues on. */
export const BLOCK_TICKS_QUEUE = "block_ticks";

/** The schedule name prefix of the block timers, for `ensureSchedules`. */
export const BLOCK_SCHEDULE_PREFIX = "block:";

/** The payload of a `block_ticks` job: which block timer fired. */
export interface BlockTick {
  readonly block: string;
  readonly name: string;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The `block_ticks` queue's payload schema, for `createQueue({ queues })`. */
export const blockTickSchema: StandardSchemaV1<BlockTick> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate: (value) =>
      isRecord(value) &&
      typeof value["block"] === "string" &&
      typeof value["name"] === "string"
        ? { value: { block: value["block"], name: value["name"] } }
        : {
            issues: [
              { message: "A block tick is { block: string, name: string }" },
            ],
          },
  },
};

/** A block as `blockSchedules` reads it: a manifest, or `createBlocks`'s list. */
export interface ScheduledBlock {
  readonly name: string;
  readonly schedules?: readonly BlockSchedule[];
}

/** The definitions `blockSchedules` returns, on the `block_ticks` queue. */
export type BlockScheduleDefinition = ScheduleDefinition<
  { readonly [BLOCK_TICKS_QUEUE]: typeof blockTickSchema },
  typeof BLOCK_TICKS_QUEUE
>;

/**
 * The timers the installed blocks declare, as queue schedules named
 * `block:<block>.<name>`: pass them to
 * `jobs.ensureSchedules(blockSchedules(blocks), { prefix: BLOCK_SCHEDULE_PREFIX
 * })` on deploy, so SLA deadlines, sequence waits, AI schedules and workflow
 * schedules all run from the one scheduler.
 */
export function blockSchedules(
  blocks: readonly ScheduledBlock[],
): readonly BlockScheduleDefinition[] {
  return blocks.flatMap((block) =>
    (block.schedules ?? []).map((schedule) => ({
      name: `${BLOCK_SCHEDULE_PREFIX}${block.name}.${schedule.name}`,
      cron: schedule.cron,
      queue: BLOCK_TICKS_QUEUE,
      payload: { block: block.name, name: schedule.name },
    })),
  );
}

/** What a block timer's handler returns; a failed `Result` retries the job. */
export type BlockTickRun = () => PromiseLike<Result<unknown>>;

/**
 * The `block_ticks` queue handler: runs the handler named `<block>.<name>`,
 * such as `"sla.check": () => sla.check()`. A tick without a handler, or a
 * failed run, throws so the queue retries it and the dead letter shows it.
 */
export function blockTickHandler(
  handlers: Readonly<Record<string, BlockTickRun>>,
): (payload: BlockTick) => Promise<void> {
  return async (payload) => {
    const key = `${payload.block}.${payload.name}`;
    const run = handlers[key];

    if (run === undefined) {
      throw new Error(
        `No handler for the block timer ${key}. Handlers: ${Object.keys(handlers).join(", ") || "none"}`,
      );
    }

    const outcome = await run();

    if (!outcome.ok) {
      throw new Error(`${key}: ${outcome.error.message}`);
    }
  };
}
