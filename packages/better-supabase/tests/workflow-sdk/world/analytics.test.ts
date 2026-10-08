import type { Pool } from "pg";

import { describe, expect, it, vi } from "vitest";

import { createAnalytics } from "../../../src/workflow-sdk/world/analytics.ts";

function fakePool(rows: Record<string, unknown>[] = []) {
  const query = vi.fn(async (_text: string, _params: unknown[]) => ({ rows }));
  // SAFETY: analytics only calls query on its pool.
  return { pool: { query } as unknown as Pool, query };
}

const lastCall = (query: ReturnType<typeof fakePool>["query"]) =>
  query.mock.calls.at(-1)!;

describe("createAnalytics", () => {
  it("pages runs with an offset cursor and drops SQL nulls", async () => {
    const { pool, query } = fakePool([
      { runId: "a", errorCode: null },
      { runId: "b", errorCode: null },
      { runId: "c", errorCode: null },
    ]);
    const analytics = createAnalytics(pool);
    const page = await analytics.runs.list({
      workflowName: "w",
      status: "running",
      attributes: { "bs.key": "k" },
      startTime: "2026-01-01T00:00:00Z",
      endTime: "2026-01-02T00:00:00Z",
      pagination: { limit: 2, cursor: "4", sortOrder: "asc" },
    });
    expect(page).toEqual({
      data: [{ runId: "a" }, { runId: "b" }],
      hasMore: true,
      cursor: "6",
    });
    const [sql, params] = lastCall(query);
    expect(sql).toContain("r.attributes @> $3::jsonb");
    expect(sql).toContain("order by r.created_at asc");
    expect(params).toEqual([
      "w",
      "running",
      '{"bs.key":"k"}',
      "2026-01-01T00:00:00Z",
      "2026-01-02T00:00:00Z",
      3,
      4,
    ]);

    const last = await analytics.runs.list({ pagination: { cursor: "x" } });
    expect(last.hasMore).toBe(false);
    expect(last.cursor).toBeNull();
    expect(lastCall(query)[1]).toEqual([101, 0]);
  });

  it("rejects pages, windows and filters past the limits", async () => {
    const { pool } = fakePool();
    const analytics = createAnalytics(pool);
    await expect(
      analytics.runs.list({ pagination: { limit: 101 } }),
    ).rejects.toThrow("page limit is 100");
    await expect(
      analytics.runs.list({ startTime: "2026-01-01T00:00:00Z" }),
    ).rejects.toThrow("startTime and endTime go together");
    const attributes = Object.fromEntries(
      Array.from({ length: 9 }, (_, index) => [`k${String(index)}`, "v"]),
    );
    await expect(analytics.runs.list({ attributes })).rejects.toThrow(
      "at most 8 attributes",
    );
    expect(() =>
      analytics.events.getMany(
        "r",
        Array.from({ length: 101 }, (_, index) => String(index)),
      ),
    ).toThrow("at most 100 events");
    await expect(
      analytics.steps.list({ runId: "r", pagination: { limit: 1001 } }),
    ).rejects.toThrow("page limit is 1000");
  });

  it("throws when a single entity is missing", async () => {
    const { pool } = fakePool();
    const analytics = createAnalytics(pool);
    await expect(analytics.runs.get("r")).rejects.toThrow(
      'workflow run "r" not found',
    );
    await expect(analytics.events.get("r", "e")).rejects.toThrow(
      'workflow event "e" not found',
    );
    await expect(analytics.hooks.get("h")).rejects.toThrow(
      'workflow hook "h" not found',
    );
    await expect(analytics.waits.get("r", "w")).rejects.toThrow(
      'workflow wait "w" not found',
    );
  });

  it("scopes steps, events, hooks, waits and attribute keys to their filters", async () => {
    const { pool, query } = fakePool([{ id: 1 }]);
    const analytics = createAnalytics(pool);

    await analytics.attributes.list({
      workflowName: "w",
      startTime: "a",
      endTime: "b",
    });
    expect(lastCall(query)[1]).toEqual(["w", "a", "b", 101, 0]);
    await analytics.attributes.list();
    expect(lastCall(query)[1]).toEqual([101, 0]);

    await analytics.steps.get("r", "s");
    expect(lastCall(query)[1]).toEqual(["r", "s"]);
    await analytics.steps.list({ runId: "r" });
    expect(lastCall(query)[1]).toEqual(["r", 1001, 0]);

    await analytics.events.list({ runId: "r", eventType: "step_created" });
    expect(lastCall(query)[0]).toContain("e.type = $2");
    // oxlint-disable-next-line typescript/no-deprecated -- covers the method the World interface still requires.
    await analytics.events.listByCorrelationId({
      runId: "r",
      correlationId: "c",
      pagination: { limit: 5 },
    });
    expect(lastCall(query)[1]).toEqual(["r", "c", 6, 0]);
    // oxlint-disable-next-line typescript/no-deprecated -- covers the method the World interface still requires.
    await analytics.events.listByCorrelationId({
      runId: "r",
      correlationId: "c",
    });
    expect(lastCall(query)[1]).toEqual(["r", "c", 1001, 0]);
    await analytics.events.getMany("r", ["e1", "e1", "e2"]);
    expect(lastCall(query)[1]).toEqual(["r", ["e1", "e2"]]);

    await analytics.hooks.get("h", { runId: "r" });
    expect(lastCall(query)[1]).toEqual(["h", "r"]);
    await analytics.hooks.list({ runId: "r" });
    expect(lastCall(query)[1]).toEqual(["r", 101, 0]);

    await analytics.waits.list({ runId: "r", status: "waiting" });
    expect(lastCall(query)[1]).toEqual(["r", "waiting", 1001, 0]);
    await analytics.waits.list({ runId: "r" });
    expect(lastCall(query)[1]).toEqual(["r", 1001, 0]);
  });
});
