import { describe, expect, it } from "vitest";

import { createEngagements } from "../../../src/blocks/engagements/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }
      return Promise.resolve(result(args));
    },
  };
}

const ROW = {
  id: "e1",
  tenant_id: "o",
  type: "task",
  title: "Send proposal",
  body: null,
  outcome: null,
  owner_user_id: "u1",
  due_at: "2026-10-16T09:00:00Z",
  done_at: null,
  duration_seconds: null,
  external_ref: null,
  created_by: "u1",
  created_at: "2026-10-14T09:00:00Z",
  updated_at: "2026-10-14T09:00:00Z",
  subjects: [{ type: "deal", id: "d1" }],
  overdue: false,
};

describe("engagements block", () => {
  it("logs with instants as ISO text and reads the row", async () => {
    const t = transport({ log_engagement: () => ROW });
    const due = Temporal.Instant.from("2026-10-16T09:00:00Z");
    const engagement = await createEngagements({ transport: t })
      .log("o", { type: "task", title: "Send proposal", dueAt: due }, [
        { type: "deal", id: "d1" },
      ])
      .orThrow();
    expect(t.calls[0]).toEqual([
      "log_engagement",
      {
        tenant: "o",
        attrs: {
          type: "task",
          title: "Send proposal",
          dueAt: "2026-10-16T09:00:00Z",
        },
        subjects: [{ type: "deal", id: "d1" }],
      },
    ]);
    expect(engagement).toMatchObject({
      id: "e1",
      ownerId: "u1",
      subjects: [{ type: "deal", id: "d1" }],
      overdue: false,
    });
    expect(engagement.dueAt?.equals(due)).toBe(true);
    expect(engagement.doneAt).toBeUndefined();
  });

  it("clears with null and keeps records unless given", async () => {
    const t = transport({ update_engagement: () => ROW });
    await createEngagements({ transport: t })
      .update("e1", { dueAt: null, body: null })
      .orThrow();
    expect(t.calls[0]?.[1]).toEqual({
      engagement: "e1",
      attrs: { body: null, dueAt: null },
      subjects: null,
    });
  });

  it("completes, removes and reads lists", async () => {
    const t = transport({
      complete_engagement: () => ({ ...ROW, done_at: "2026-10-14T10:00:00Z" }),
      delete_engagement: () => true,
      engagements_of: () => [ROW],
      next_engagement: () => null,
      open_engagements: () => [ROW],
    });
    const engagements = createEngagements({ transport: t });
    expect(
      (await engagements.complete("e1", { outcome: "sent" }).orThrow()).doneAt,
    ).toBeDefined();
    expect(await engagements.remove("e1").orThrow()).toBe(true);
    expect(
      await engagements
        .of({ type: "deal", id: "d1" }, { types: ["call"], limit: 10 })
        .orThrow(),
    ).toHaveLength(1);
    expect(
      await engagements.next({ type: "deal", id: "d1" }).orThrow(),
    ).toBeUndefined();
    expect(await engagements.open("o").orThrow()).toHaveLength(1);
    expect(t.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "complete_engagement",
        { engagement: "e1", done: true, outcome: "sent" },
      ],
      ["delete_engagement", { engagement: "e1" }],
      [
        "engagements_of",
        {
          subject_type: "deal",
          subject_id: "d1",
          types: ["call"],
          before: null,
          page_size: 10,
        },
      ],
      ["next_engagement", { subject_type: "deal", subject_id: "d1" }],
      [
        "open_engagements",
        { tenant: "o", owner: null, due_before: null, page_size: null },
      ],
    ]);
  });
});

describe("engagements block, optional fields", () => {
  it("reads every optional field and reopens with done false", async () => {
    const full = {
      ...ROW,
      body: "Notes",
      outcome: "connected",
      done_at: "2026-10-14T10:00:00Z",
      duration_seconds: 900,
      external_ref: "msg-1",
      overdue: true,
    };
    const t = transport({
      complete_engagement: () => full,
      next_engagement: () => full,
    });
    const logged: unknown[] = [];
    const engagements = createEngagements({
      transport: t,
      logger: {
        error: (...args: unknown[]) => void logged.push(args),
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: { next: { after: () => undefined } },
    });
    const done = await engagements.complete("e1", { done: false }).orThrow();
    expect(done).toMatchObject({
      body: "Notes",
      outcome: "connected",
      durationSeconds: 900,
      externalRef: "msg-1",
      overdue: true,
    });
    expect(
      (await engagements.next({ type: "deal", id: "d1" }).orThrow())?.id,
    ).toBe("e1");
    expect(t.calls[0]?.[1]).toEqual({
      engagement: "e1",
      done: false,
      outcome: null,
    });
  });

  it("passes list windows and owners", async () => {
    const t = transport({
      engagements_of: () => [],
      open_engagements: () => [],
      update_engagement: () => ROW,
    });
    const engagements = createEngagements({ transport: t });
    const at = Temporal.Instant.from("2026-10-14T00:00:00Z");
    await engagements.of({ type: "deal", id: "d1" }, { before: at }).orThrow();
    await engagements
      .open("o", { ownerId: "u2", dueBefore: at, limit: 5 })
      .orThrow();
    await engagements
      .update("e1", { doneAt: at }, [{ type: "deal", id: "d1" }])
      .orThrow();
    expect(t.calls.map(([, args]) => args)).toEqual([
      {
        subject_type: "deal",
        subject_id: "d1",
        types: null,
        before: "2026-10-14T00:00:00Z",
        page_size: null,
      },
      {
        tenant: "o",
        owner: "u2",
        due_before: "2026-10-14T00:00:00Z",
        page_size: 5,
      },
      {
        engagement: "e1",
        attrs: { doneAt: "2026-10-14T00:00:00Z" },
        subjects: [{ type: "deal", id: "d1" }],
      },
    ]);
  });
});
