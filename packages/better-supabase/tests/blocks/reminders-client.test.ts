import { describe, expect, it } from "vitest";

import { createReminders } from "../../src/blocks/reminders/reminders.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { temporal } from "../../src/core/temporal-required.ts";

const now = temporal().Instant.from("2026-11-09T12:00:00Z");

const row = {
  reminder: "r1",
  dtstart: now.toString(),
  tzid: "UTC",
  rrule: "FREQ=DAILY",
  offset_minutes: 0,
  tenant: "org-1",
  user_id: "u1",
  subject_type: "deal",
  subject_id: "d1",
};

function reminders(schedule: unknown, duplicate: boolean) {
  return createReminders({
    tenant: "org-1",
    transport: { call: () => Promise.resolve(schedule) },
    jobs: { enqueueOnce: () => AsyncResult.ok({ id: 1, duplicate }) },
  });
}

describe("reminder client", () => {
  it("refuses to schedule without a jobs queue", async () => {
    const result = await createReminders({
      tenant: "org-1",
      transport: { call: () => Promise.resolve([]) },
    }).schedule({});

    expect(result.ok).toBe(false);
  });

  it("enqueues due rows and skips a row with no rule", async () => {
    const scheduled = await reminders(
      [
        row,
        {
          ...row,
          reminder: "r2",
          rrule: undefined,
          user_id: undefined,
          subject_type: undefined,
          subject_id: undefined,
        },
        {
          ...row,
          reminder: "r4",
          user_id: undefined,
          subject_type: undefined,
          subject_id: undefined,
        },
        { ...row, reminder: "r3", tzid: "Not/AZone" },
      ],
      true,
    ).schedule({ now, lookbackMinutes: 30, horizonMinutes: 30 });

    expect(scheduled.ok ? scheduled.data.duplicates : 0).toBeGreaterThan(0);

    const failed = await createReminders({
      tenant: "org-1",
      transport: { call: () => Promise.resolve([row]) },
      jobs: {
        enqueueOnce: () => AsyncResult.err(dbError("unexpected", "full")),
      },
    }).schedule({});

    const unread = await createReminders({
      tenant: "org-1",
      transport: { call: () => Promise.reject(new Error("down")) },
      jobs: { enqueueOnce: () => AsyncResult.ok({ id: 1, duplicate: false }) },
    }).schedule({});

    expect(failed.ok).toBe(false);
    expect(unread.ok).toBe(false);
  });

  it("limits a subject's reminders", async () => {
    const client = createReminders({
      tenant: "org-1",
      transport: {
        call: () =>
          Promise.resolve([
            { id: "r1", method: "in_app", offsetMinutes: 0 },
            {
              id: "r2",
              method: "in_app",
              offsetMinutes: 15,
              remindAt: now.toString(),
            },
          ]),
      },
    });

    const subject = { type: "deal", id: "d1" };

    expect((await client.list(subject, { limit: 1 })).ok).toBe(true);
    expect((await client.list(subject)).ok).toBe(true);

    const quiet = createReminders({
      tenant: "org-1",
      transport: {
        call: (_schema: string, fn: string) =>
          Promise.resolve(fn === "save_reminder" ? { id: "r1" } : true),
      },
      logger: { debug() {}, info() {}, warn() {}, error() {} },
    });

    expect(
      (
        await quiet.deliver({
          reminderId: "r1",
          occurrenceAt: now,
          organizationId: "org-1",
        })
      ).ok,
    ).toBe(true);

    const saved = await quiet.upsert({ subject, when: { at: now } });

    expect(saved.ok).toBe(true);
  });
});
