import { describe, expect, it } from "vitest";

import type {
  QueueProvider,
  ScheduleProvider,
} from "../../../src/blocks/queue/backends.ts";

import { checkSchedulerPair } from "../../../src/blocks/queue/scheduler-pair.ts";

const queue = (name: string): QueueProvider =>
  // SAFETY: checkSchedulerPair reads only the name.
  ({ name }) as QueueProvider;

const scheduler = (delivers: ScheduleProvider["delivers"]): ScheduleProvider =>
  // SAFETY: checkSchedulerPair reads only the name and delivers.
  ({ name: "test", delivers }) as ScheduleProvider;

describe("checkSchedulerPair", () => {
  it("refuses pg_cron with a queue outside the database", () => {
    expect(() => {
      checkSchedulerPair(queue("vercel-queues"), scheduler("sql"), true);
    }).toThrow(/sqlScheduler\(sql, \{ mode: "drain" \}\)/);
  });

  it("accepts pg_cron with a SQL queue, given or built from options", () => {
    expect(() => {
      checkSchedulerPair(queue("transport"), scheduler("sql"), true);
    }).not.toThrow();
    expect(() => {
      checkSchedulerPair(queue("custom"), scheduler("sql"), false);
    }).not.toThrow();
  });

  it("refuses a Vercel topic scheduler on a Supabase queue", () => {
    expect(() => {
      checkSchedulerPair(queue("sql"), scheduler("vercel-queues"), false);
    }).toThrow(/bridge/);
    expect(() => {
      checkSchedulerPair(
        queue("vercel-queues"),
        scheduler("vercel-queues"),
        true,
      );
    }).not.toThrow();
  });

  it("accepts a scheduler that runs through runSchedules or a bridge", () => {
    expect(() => {
      checkSchedulerPair(queue("vercel-queues"), scheduler(undefined), true);
    }).not.toThrow();
  });
});
