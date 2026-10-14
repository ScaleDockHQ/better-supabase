import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createReminders } from "../../../src/blocks/reminders/index.ts";

const ALICE = "00000000-0000-4000-8000-00000000000a";

const DELIVERY = {
  reminderId: "r-1",
  occurrenceAt: "2026-10-14T09:00:00Z",
  organizationId: "org-1",
  userId: ALICE,
  subjectType: "invoice",
  subjectId: "7",
};

function fake(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: { fn: string; args: Readonly<Record<string, unknown>> }[] = [];
  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      calls.push({ fn, args });
      if (fn === "mark_reminder_sent") return true;
      const result = results[fn];
      if (!result) throw new Error(`unexpected ${fn}`);
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
