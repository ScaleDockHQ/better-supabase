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
      if (!result) return Promise.reject(new Error(`unexpected ${fn}`));
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
