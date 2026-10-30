import { describe, expect, it, vi } from "vitest";

import type { WorkItem, Tasks } from "../../../src/blocks/tasks/index.ts";

import {
  nextWorkItemOccurrence,
  workItemRecurrenceSink,
} from "../../../src/blocks/tasks/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const instant = (value: string) => Temporal.Instant.from(value);

const RULE = {
  rrule: "FREQ=WEEKLY;BYDAY=MO;COUNT=3",
  tzid: "Europe/Amsterdam",
  dtstart: instant("2026-10-19T08:00:00Z"),
};

const closed = (data: Record<string, unknown>, type = "task.closed") => ({
  specversion: "1.0" as const,
  id: crypto.randomUUID(),
  source: "test",
  type: `dev.better-supabase.${type}`,
  data,
});

function stub(item: Partial<WorkItem> | undefined) {
  const get = vi.fn((_id: string): AsyncResult<WorkItem | undefined> =>
    AsyncResult.ok(
      item === undefined ? undefined : ({ id: "w1", ...item } as WorkItem),
    ),
  );

  const repeat = vi.fn(
    (_id: string, _dueAt: Temporal.Instant): AsyncResult<WorkItem> =>
      AsyncResult.ok({ id: "w2" } as WorkItem),
  );

  return { get, repeat } satisfies Pick<Tasks, "get" | "repeat">;
}

describe("nextWorkItemOccurrence", () => {
  it("finds the next occurrence and stops when the rule ends", () => {
    expect(
      nextWorkItemOccurrence(RULE, instant("2026-10-19T08:00:00Z"))?.toString(),
    ).toBe("2026-10-26T09:00:00Z");
    expect(
      nextWorkItemOccurrence(RULE, instant("2026-11-02T09:00:00Z")),
    ).toBeUndefined();
  });
});

describe("workItemRecurrenceSink", () => {
  it("repeats a completed item at its next occurrence, once per event", async () => {
    const items = stub({
      recurrence: RULE,
      dueAt: instant("2026-10-19T08:00:00Z"),
    });

    await workItemRecurrenceSink(items).send([
      closed({ subjectId: "w1", state: "completed" }),
      closed({ subjectId: "w1", state: "canceled" }),
      closed({ subjectId: "w1", state: "completed" }, "task.reopened"),
      closed({ state: "completed" }),
    ]);

    expect(items.repeat).toHaveBeenCalledOnce();
    expect(items.repeat.mock.calls[0]?.[1].toString()).toBe(
      "2026-10-26T09:00:00Z",
    );
  });

  it("skips items without a rule or past its end, and follows a renamed type", async () => {
    const plain = stub({});
    const gone = stub(undefined);
    const ended = stub({ recurrence: RULE });
    const now = () => instant("2026-12-01T00:00:00Z");

    const event = closed(
      { subjectId: "w1", state: "completed" },
      "task.closed",
    );

    await workItemRecurrenceSink(plain, { type: "task.closed" }).send([event]);
    await workItemRecurrenceSink(gone, { type: "task.closed" }).send([event]);
    await workItemRecurrenceSink(ended, { type: "task.closed", now }).send([
      event,
    ]);

    expect(plain.get).toHaveBeenCalledOnce();
    expect(
      [plain, gone, ended].map((items) => items.repeat.mock.calls.length),
    ).toEqual([0, 0, 0]);
  });

  it("throws when reading or repeating fails, so the relay retries", async () => {
    const event = closed({ subjectId: "w1", state: "completed" });
    const broken = stub({});
    broken.get.mockReturnValueOnce(
      AsyncResult.err(dbError("not_found", "down")),
    );

    await expect(workItemRecurrenceSink(broken).send([event])).rejects.toThrow(
      "reading w1 failed: down",
    );

    const stuck = stub({ recurrence: RULE, dueAt: RULE.dtstart });
    stuck.repeat.mockReturnValueOnce(
      AsyncResult.err(dbError("not_found", "nope")),
    );

    await expect(workItemRecurrenceSink(stuck).send([event])).rejects.toThrow(
      "repeating w1 failed: nope",
    );
  });
});
