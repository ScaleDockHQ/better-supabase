import { describe, expect, it } from "vitest";

import { createActivities } from "../../../src/blocks/activities/index.ts";

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
    const t = transport({ log_activity: () => ROW });
    const due = Temporal.Instant.from("2026-10-16T09:00:00Z");

    const engagement = await createActivities({ transport: t })
      .log("o", { type: "task", title: "Send proposal", dueAt: due }, [
        { type: "deal", id: "d1" },
      ])
      .orThrow();

    expect(t.calls[0]).toEqual([
      "log_activity",
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

  it("reads progress note fields, amends and marks errors", async () => {
    const NOTE = {
      ...ROW,
      type: "note",
      audience: "restricted",
      restricted_roles: ["nurse"],
      category: "medical",
      locked_at: "2026-10-15T09:00:00Z",
      amends_id: "e0",
      goal_id: "g1",
      marked_error_at: null,
      marked_error_by: null,
      marked_error_reason: null,
    };

    const t = transport({
      amend_activity: () => NOTE,
      mark_activity_error: () => ({
        ...NOTE,
        audience: "everyone",
        marked_error_at: "2026-10-14T10:00:00Z",
        marked_error_by: "u1",
        marked_error_reason: "Wrong client",
      }),
    });

    const engagements = createActivities({ transport: t });
    const addendum = await engagements.amend("e0", "Also ate well").orThrow();

    expect(addendum).toMatchObject({
      audience: "restricted",
      restrictedRoles: ["nurse"],
      category: "medical",
      amendsId: "e0",
      goalId: "g1",
    });
    expect(addendum.lockedAt?.toString()).toBe("2026-10-15T09:00:00Z");
    expect(addendum.markedErrorAt).toBeUndefined();

    const flagged = await engagements.markError("e1", "Wrong client").orThrow();

    expect(flagged).toMatchObject({
      markedErrorBy: "u1",
      markedErrorReason: "Wrong client",
    });
    expect(flagged.audience).toBeUndefined();
    expect(flagged.markedErrorAt).toBeDefined();
    expect(t.calls).toEqual([
      ["amend_activity", { engagement: "e0", body: "Also ate well" }],
      ["mark_activity_error", { engagement: "e1", reason: "Wrong client" }],
    ]);
  });

  it("clears with null and keeps records unless given", async () => {
    const t = transport({ update_activity: () => ROW });
    await createActivities({ transport: t })
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
      complete_activity: () => ({ ...ROW, done_at: "2026-10-14T10:00:00Z" }),
      delete_activity: () => true,
      activities_of: () => [ROW],
      next_activity: () => null,
      open_activities: () => [ROW],
    });

    const engagements = createActivities({ transport: t });
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
      ["complete_activity", { engagement: "e1", done: true, outcome: "sent" }],
      ["delete_activity", { engagement: "e1" }],
      [
        "activities_of",
        {
          subject_type: "deal",
          subject_id: "d1",
          types: ["call"],
          before: null,
          page_size: 10,
        },
      ],
      ["next_activity", { subject_type: "deal", subject_id: "d1" }],
      [
        "open_activities",
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
      complete_activity: () => full,
      next_activity: () => full,
    });

    const logged: unknown[] = [];

    const engagements = createActivities({
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
      activities_of: () => [],
      open_activities: () => [],
      update_activity: () => ROW,
    });

    const engagements = createActivities({ transport: t });
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
