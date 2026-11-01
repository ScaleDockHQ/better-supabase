import { describe, expect, expectTypeOf, it } from "vitest";

import type { Queue } from "../../../src/blocks/queue/types.ts";
import type {
  ReminderJobs,
  REMINDER_DELIVERY_QUEUE,
} from "../../../src/blocks/reminders/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createReminders,
  reminderJobSchema,
} from "../../../src/blocks/reminders/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const ALICE = "00000000-0000-4000-8000-00000000000a";

const DELIVERY = {
  reminderId: "r-1",
  occurrenceAt: Temporal.Instant.from("2026-10-14T09:00:00Z"),
  organizationId: "org-1",
  userId: ALICE,
  subject: { type: "invoice", id: "7" },
};

function fake(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];

  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push({ fn, args });

      if (fn === "mark_reminder_sent") {
        return true;
      }

      const result = results[fn];

      if (!result) {
        throw new Error(`unexpected ${fn}`);
      }

      return result({ ...args });
    },
  };

  return { transport, calls };
}

describe("createReminders: audience", () => {
  it("records the occurrence but skips a user the audience leaves out", async () => {
    const { transport, calls } = fake({});
    const notified: unknown[] = [];

    const reminders = createReminders({
      transport,
      audience: () => [],
      notifyDelivery: (delivery) => notified.push(delivery),
    });

    expect(await reminders.deliver(DELIVERY).orThrow()).toBe(true);
    expect(notified).toEqual([]);
    expect(calls.map((call) => call.fn)).toEqual(["mark_reminder_sent"]);
  });

  it("defaults to subjectReaders under authorization", async () => {
    const { transport, calls } = fake({
      subject_types: () => ["invoice"],
      can_subject_for: () => true,
    });

    const notified: unknown[] = [];

    const reminders = createReminders({
      transport,
      authorization: {},
      notifyDelivery: (delivery) => notified.push(delivery),
    });

    await reminders.deliver(DELIVERY).orThrow();
    expect(notified).toHaveLength(1);
    expect(calls).toContainEqual({
      fn: "can_subject_for",
      args: {
        member: ALICE,
        subject_type: "invoice",
        subject_id: "7",
        action: "read",
      },
    });
  });

  it("fails before recording when the audience throws, so the job retries", async () => {
    const { transport, calls } = fake({});

    const reminders = createReminders({
      transport,
      audience: () => {
        throw new Error("provider down");
      },
      notifyDelivery: () => undefined,
    });

    const result = await reminders.deliver(DELIVERY);
    expect(!result.ok && result.error.hint).toBe("REMINDER_AUDIENCE_FAILED");
    expect(calls).toEqual([]);
  });
});

describe("createReminders: list and remove", () => {
  it("lists the caller's reminders on a subject", async () => {
    const { transport, calls } = fake({
      list_my_reminders: () => [
        { id: "r-1", method: "notification", offsetMinutes: 60 },
      ],
    });

    const reminders = createReminders({ transport, tenant: "org-1" });

    expect(
      await reminders.list({ type: "calendar_event", id: "e-1" }).orThrow(),
    ).toEqual([{ id: "r-1", method: "notification", offsetMinutes: 60 }]);
    expect(calls).toEqual([
      {
        fn: "list_my_reminders",
        args: {
          tenant: "org-1",
          subject_type: "calendar_event",
          subject_id: "e-1",
        },
      },
    ]);
  });

  it("fails without a tenant", async () => {
    const { transport, calls } = fake({ save_reminder: () => ({ id: "r-1" }) });
    const session: { tenant?: string } = {};

    const reminders = createReminders({
      transport,
      tenant: () => session.tenant,
    });

    const subject = { type: "invoice", id: "7" };

    for (const result of [
      await reminders.upsert({ subject, when: 15 }),
      await reminders.list(subject),
    ]) {
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
      });
    }

    expect(calls).toEqual([]);
    session.tenant = "org-2";
    await reminders.upsert({ subject, when: 15 }).orThrow();
    expect(calls).toEqual([
      {
        fn: "save_reminder",
        args: {
          tenant: "org-2",
          subject_type: "invoice",
          subject_id: "7",
          offset_minutes: 15,
          fields: undefined,
        },
      },
    ]);
  });

  it("reads the subject of a queued delivery, nested or flat", async () => {
    const { transport } = fake({});
    const notified: unknown[] = [];

    const reminders = createReminders({
      transport,
      notifyDelivery: (delivery) => notified.push(delivery),
    });

    const signal = new AbortController().signal;
    await reminders.job(DELIVERY, undefined as never, signal);
    const { subject: _, ...flat } = DELIVERY;
    await reminders.job(
      { ...flat, subjectType: "invoice", subjectId: "7" },
      undefined as never,
      signal,
    );
    expect(notified).toEqual([DELIVERY, DELIVERY]);
  });

  it("removes a reminder and reports whether it existed", async () => {
    const { transport, calls } = fake({ delete_reminder: () => false });

    const reminders = createReminders({ transport });

    expect(await reminders.remove("r-9").orThrow()).toBe(false);
    expect(calls).toEqual([
      { fn: "delete_reminder", args: { reminder: "r-9" } },
    ]);
  });
});

describe("createReminders: one-time reminders", () => {
  it("saves a reminder at a time and lists it back", async () => {
    const { transport, calls } = fake({
      save_reminder: () => ({ id: "r-2" }),
      list_my_reminders: () => [
        {
          id: "r-2",
          method: "notification",
          offsetMinutes: 0,
          remindAt: "2026-10-14T09:00:00Z",
        },
        { id: "r-3", method: "notification", offsetMinutes: 5, remindAt: null },
      ],
    });

    const reminders = createReminders({ transport, tenant: "org-1" });
    const subject = { type: "task", id: "t1" };
    const at = Temporal.Instant.from("2026-10-14T09:00:00Z");

    await reminders.upsert({ subject, when: { at } }).orThrow();
    await reminders.upsert({ subject }).orThrow();

    expect(calls.map((call) => call.args)).toEqual([
      {
        tenant: "org-1",
        subject_type: "task",
        subject_id: "t1",
        offset_minutes: 0,
        remind_at: at,
        fields: undefined,
      },
      {
        tenant: "org-1",
        subject_type: "task",
        subject_id: "t1",
        offset_minutes: 0,
        fields: undefined,
      },
    ]);
    expect(await reminders.list(subject).orThrow()).toEqual([
      { id: "r-2", method: "notification", offsetMinutes: 0, remindAt: at },
      { id: "r-3", method: "notification", offsetMinutes: 5 },
    ]);
  });
});

describe("createReminders: schedule", () => {
  const NOW = Temporal.Instant.from("2026-10-14T08:00:00Z");

  const ROWS = [
    {
      reminder: "r-1",
      dtstart: "2020-01-06T09:00:00+00:00",
      tzid: "Europe/Amsterdam",
      rrule: "FREQ=DAILY",
      offset_minutes: 30,
      tenant: "org-1",
      subject_type: "task",
      subject_id: "t1",
      user_id: ALICE,
    },
    {
      reminder: "r-2",
      dtstart: "2026-10-14T07:50:00+00:00",
      tzid: "UTC",
      rrule: "FREQ=DAILY;COUNT=1",
      offset_minutes: 0,
      tenant: "org-1",
      subject_type: "task",
      subject_id: "t2",
      user_id: null,
    },
    {
      reminder: "r-3",
      dtstart: "2026-10-14T09:00:00Z",
      tzid: "UTC",
      rrule: null,
      offset_minutes: 0,
      tenant: "org-1",
    },
    {
      reminder: "r-4",
      dtstart: "2026-10-14T09:00:00Z",
      tzid: "Nowhere/City",
      rrule: "FREQ=DAILY",
      offset_minutes: 0,
      tenant: "org-1",
    },
  ];

  it("enqueues each occurrence due in the window once", async () => {
    const { transport } = fake({ list_reminder_schedule: () => ROWS });
    const enqueued: { payload: unknown; options: unknown }[] = [];

    const reminders = createReminders({
      transport,
      jobs: {
        enqueueOnce: ({ queue: _queue, payload, options }) => {
          enqueued.push({ payload, options });

          return AsyncResult.ok({
            id: enqueued.length,
            duplicate: payload.reminderId === "r-2",
          });
        },
      },
    });

    expect(
      await reminders.schedule({ now: NOW, horizonMinutes: 60 * 24 }).orThrow(),
    ).toEqual({ planned: 2, enqueued: 1, duplicates: 1, skipped: 2 });
    expect(enqueued).toEqual([
      {
        payload: {
          reminderId: "r-1",
          occurrenceAt: "2026-10-15T08:00:00Z",
          organizationId: "org-1",
          userId: ALICE,
          subject: { type: "task", id: "t1" },
        },
        options: {
          dedupeKey: "r-1:2026-10-15T08:00:00Z",
          runAt: Temporal.Instant.from("2026-10-15T07:30:00Z"),
          context: { tenant: "org-1" },
        },
      },
      {
        payload: {
          reminderId: "r-2",
          occurrenceAt: "2026-10-14T07:50:00Z",
          organizationId: "org-1",
          subject: { type: "task", id: "t2" },
        },
        options: {
          dedupeKey: "r-2:2026-10-14T07:50:00Z",
          runAt: NOW,
          context: { tenant: "org-1" },
        },
      },
    ]);
  });

  it("needs a jobs queue and passes a failed enqueue on", async () => {
    const { transport } = fake({ list_reminder_schedule: () => ROWS });
    const missing = await createReminders({ transport }).schedule();

    expect(!missing.ok && missing.error.hint).toBe("REMINDER_JOBS_MISSING");

    const failed = await createReminders({
      transport,
      jobs: {
        enqueueOnce: () => AsyncResult.err(dbError("unexpected", "down")),
      },
    }).schedule({ now: NOW });

    expect(!failed.ok && failed.error.message).toBe("down");
  });
});

describe("reminderJobSchema", () => {
  it("reads a delivery payload and keeps its time as ISO text", async () => {
    const result = await reminderJobSchema["~standard"].validate({
      ...DELIVERY,
      occurrenceAt: "2026-10-14T09:00:00Z",
    });

    expect(result).toEqual({
      value: { ...DELIVERY, occurrenceAt: "2026-10-14T09:00:00Z" },
    });
  });

  it("reports a payload that isn't a delivery", async () => {
    const result = await reminderJobSchema["~standard"].validate("nope");

    expect(result.issues?.[0]?.message).toContain("needs an object payload");
  });

  it("types a queue with the schema as the jobs option", () => {
    expectTypeOf<
      Queue<{ readonly [REMINDER_DELIVERY_QUEUE]: typeof reminderJobSchema }>
    >().toExtend<ReminderJobs>();
  });
});
