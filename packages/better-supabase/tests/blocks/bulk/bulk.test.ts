import { describe, expect, it } from "vitest";

import { createBulk } from "../../../src/blocks/bulk/index.ts";
import { BULK_ACTIONS } from "../../../src/sql/modules/bulk.ts";

function transport(results: Record<string, unknown>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      const result = results[fn];
      return Promise.resolve(Array.isArray(result) ? result.shift() : result);
    },
  };
}

const ORG = "org-1";
const step = (position: number, done: boolean) => ({
  id: "run-1",
  status: done ? "completed" : "running",
  position,
  total: 3,
  succeeded: position,
  failed: 0,
  done,
});

describe("bulk client", () => {
  it("names the SQL module's built-in actions", () => {
    const actions: readonly string[] = [
      "tags.set",
      "stateMachine.transition",
      "relations.link",
      "trash.trash",
    ];
    expect(Object.keys(BULK_ACTIONS)).toEqual(actions);
  });

  it("runs rows now with a result per row", async () => {
    const fake = transport({
      bulk_apply: {
        total: 2,
        succeeded: 1,
        failed: 1,
        results: [
          { id: "a", ok: true },
          {
            id: "b",
            ok: false,
            error: {
              code: "TAG_SUBJECT_FORBIDDEN",
              message: "no",
              sqlstate: "42501",
            },
          },
        ],
      },
    });
    const bulk = createBulk({ transport: fake });
    const result = await bulk
      .run({
        organizationId: ORG,
        subjectType: "task",
        rows: () => Promise.resolve(["a", "b"]),
        action: "tags.set",
        args: { add: ["t1"] },
        atomic: true,
      })
      .orThrow();
    expect(fake.calls[0]).toEqual({
      fn: "bulk_apply",
      args: {
        tenant: ORG,
        subject_type: "task",
        ids: ["a", "b"],
        action: "tags.set",
        args: { add: ["t1"] },
        atomic: true,
      },
    });
    expect(result.results[1]).toEqual({
      id: "b",
      ok: false,
      error: {
        code: "TAG_SUBJECT_FORBIDDEN",
        message: "no",
        sqlstate: "42501",
      },
    });
  });

  it("starts a background run beyond the limit", async () => {
    const fake = transport({
      bulk_apply: { total: 2, succeeded: 2, failed: 0, results: [] },
      start_bulk: { id: "run-1", total: 3, topic: "bulk:run-1" },
    });
    const bulk = createBulk({ transport: fake, limit: 2 });
    const input = {
      organizationId: ORG,
      subjectType: "task",
      action: "tasks.archive",
    };
    expect(
      await bulk.apply({ ...input, rows: ["a", "b"] }).orThrow(),
    ).toMatchObject({
      mode: "now",
      succeeded: 2,
    });
    expect(
      await bulk.apply({ ...input, rows: ["a", "b", "c"] }).orThrow(),
    ).toEqual({
      mode: "background",
      id: "run-1",
      total: 3,
      topic: "bulk:run-1",
    });
    expect(fake.calls.map((call) => call.fn)).toEqual([
      "bulk_apply",
      "start_bulk",
    ]);
    expect(fake.calls[1]?.args).toEqual({
      tenant: ORG,
      subject_type: "task",
      ids: ["a", "b", "c"],
      action: "tasks.archive",
      args: {},
    });
  });

  it("drains a run in steps and handles jobs", async () => {
    const fake = transport({
      bulk_step: [step(2, false), step(3, true), step(2, false), step(3, true)],
    });
    const bulk = createBulk({ transport: fake });
    expect(await bulk.drain("run-1", { size: 2 }).orThrow()).toMatchObject({
      status: "completed",
      done: true,
    });
    expect(fake.calls[0]?.args).toEqual({ run_id: "run-1", size: 2 });
    const handler = bulk.handler();
    await handler({ run: "run-1" }, {}, new AbortController().signal);
    expect(fake.calls).toHaveLength(4);
    await expect(handler({}, {}, new AbortController().signal)).rejects.toThrow(
      /run/,
    );
    const aborted = new AbortController();
    aborted.abort();
    const result = await bulk.drain("run-1", { signal: aborted.signal });
    expect(result.ok).toBe(false);
  });

  it("reads a run or null", async () => {
    const fake = transport({
      bulk_run: [
        {
          id: "run-1",
          organizationId: ORG,
          subjectType: "task",
          action: "tags.set",
          status: "weird",
          total: 1,
          position: 1,
          succeeded: 1,
          failed: 0,
          results: [{ id: "a", ok: true }],
          createdAt: "2026-10-13T00:00:00Z",
          finishedAt: null,
        },
        null,
      ],
    });
    const bulk = createBulk({ transport: fake, schema: "app" });
    expect(await bulk.get("run-1").orThrow()).toMatchObject({
      status: "pending",
      finishedAt: undefined,
      results: [{ id: "a", ok: true, error: null }],
    });
    expect(await bulk.get("run-2").orThrow()).toBeNull();
  });
});
