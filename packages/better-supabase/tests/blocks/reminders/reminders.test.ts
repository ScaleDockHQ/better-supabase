import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createReminders } from "../../../src/blocks/reminders/index.ts";

const ALICE = "00000000-0000-4000-8000-00000000000a";

const DELIVERY = {
  reminderId: "r-1",
  occurrenceAt: "2026-10-14T09:00:00Z",
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
      await reminders.upsert(subject, 15),
      await reminders.list(subject),
    ]) {
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
      });
    }

    expect(calls).toEqual([]);
    session.tenant = "org-2";
    await reminders.upsert(subject, 15).orThrow();
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
