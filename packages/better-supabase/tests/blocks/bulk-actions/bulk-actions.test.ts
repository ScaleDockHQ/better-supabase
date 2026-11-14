import { describe, expect, it } from "vitest";

import { createBulkActions } from "../../../src/blocks/bulk-actions/index.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

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
      "collections.add",
      "appTables.set",
    ];

    const sql = renderBlocks(
      [
        "bulk-actions",
        "tags",
        "state-machine",
        "relations",
        "trash",
        "collections",
      ],
      { appTables: { tasks: { subject: { type: "task" } } } },
    )
      .filter((file) => file.module === "bulk-actions")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `array[${actions.map((name) => `'${name}'`).join(", ")}]`,
    );
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

    const bulk = createBulkActions({ transport: fake });

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

    const bulk = createBulkActions({ transport: fake, limit: 2 });

    const input = {
      organizationId: ORG,
      subjectType: "task",
      action: "tasks.archive",
    };

    expect(
      await bulk.apply({ ...input, rows: ["a", "b"] }).orThrow(),
    ).toMatchObject({ mode: "now", succeeded: 2 });
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

    const bulk = createBulkActions({ transport: fake });
    expect(await bulk.drain({ id: "run-1", size: 2 }).orThrow()).toMatchObject({
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
    const result = await bulk.drain({ id: "run-1", signal: aborted.signal });
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

    const bulk = createBulkActions({ transport: fake, schema: "app" });
    expect(await bulk.get("run-1").orThrow()).toMatchObject({
      status: "pending",
      finishedAt: undefined,
      results: [{ id: "a", ok: true, error: null }],
    });
    expect(await bulk.get("run-2").orThrow()).toBeNull();
  });
});

describe("common bulk and jobs", () => {
  it("answers bulk(ids, action) with succeeded and failed", async () => {
    const fake = transport({
      bulk_apply: {
        total: 2,
        succeeded: 1,
        failed: 1,
        results: [
          { id: "a", ok: true },
          { id: "b", ok: false, error: { code: "X", message: "no" } },
        ],
      },
    });

    const bulk = createBulkActions({ transport: fake });

    const report = await bulk
      .bulk(["a", "b", "a"], "trash.trash", {
        organizationId: ORG,
        subjectType: "task",
      })
      .orThrow();

    expect(fake.calls[0]?.args["ids"]).toEqual(["a", "b"]);
    expect(report.succeeded).toEqual(["a"]);
    expect(report.failed).toMatchObject([
      { id: "b", error: { hint: "X", message: "no" } },
    ]);
  });

  it("refuses more ids than the limit before calling the database", async () => {
    const fake = transport({});
    const bulk = createBulkActions({ transport: fake, limit: 2 });

    const result = await bulk.bulk(["a", "b", "c"], "trash.trash", {
      organizationId: ORG,
      subjectType: "task",
    });

    expect(fake.calls).toEqual([]);
    expect(!result.ok && result.error.hint).toBe("BULK_TOO_MANY");
  });

  it("starts a job and reads it back as a job result", async () => {
    const fake = transport({
      start_bulk: { id: "run-1", total: 3, topic: "t" },
      bulk_run: {
        id: "run-1",
        organizationId: ORG,
        subjectType: "task",
        action: "trash.trash",
        status: "completed",
        position: 3,
        total: 3,
        succeeded: 2,
        failed: 1,
        createdAt: "2026-11-14T10:00:00Z",
        finishedAt: "2026-11-14T10:00:05Z",
        results: [
          { id: "a", ok: true },
          { id: "b", ok: true },
          { id: "c", ok: false, error: { code: "X", message: "no" } },
        ],
      },
    });

    const bulk = createBulkActions({ transport: fake });

    expect(
      await bulk
        .startJob({
          organizationId: ORG,
          subjectType: "task",
          rows: ["a", "b", "c"],
          action: "trash.trash",
        })
        .orThrow(),
    ).toEqual({ jobId: "bulk:run-1" });

    const job = await bulk.jobs.get("run-1").orThrow();

    expect(job).toMatchObject({
      jobId: "bulk:run-1",
      status: "completed",
      done: true,
      progress: { done: 3, total: 3 },
    });
    expect(job?.result).toMatchObject({ succeeded: ["a", "b"] });
  });

  const runRow = (status: string) => ({
    id: "run-1",
    organizationId: ORG,
    subjectType: "task",
    action: "trash.trash",
    status,
    position: 1,
    total: 3,
    succeeded: 1,
    failed: 0,
    createdAt: "2026-11-14T10:00:00Z",
    finishedAt: null,
    results: [{ id: "a", ok: true }],
  });

  it("reads an unknown job as null", async () => {
    const bulk = createBulkActions({
      transport: transport({ bulk_run: null }),
    });

    expect(await bulk.jobs.get("nope").orThrow()).toBeNull();
  });

  it("reads a running job without a result", async () => {
    const bulk = createBulkActions({
      transport: transport({ bulk_run: runRow("running") }),
    });

    const job = await bulk.jobs.get("run-1").orThrow();

    expect(job).toMatchObject({ status: "running", done: false, result: null });
  });

  it("reads a failed job with its error", async () => {
    const bulk = createBulkActions({
      transport: transport({ bulk_run: runRow("failed") }),
    });

    const job = await bulk.jobs.get("run-1").orThrow();

    expect(job).toMatchObject({ status: "failed", done: true });
    expect(job?.error).not.toBeNull();
  });

  it("passes the arguments and takes the limit of the call", async () => {
    const fake = transport({
      bulk_apply: { total: 1, succeeded: 1, failed: 0, results: [] },
    });

    const bulk = createBulkActions({ transport: fake, limit: 1 });

    await bulk
      .bulk(["a", "b"], "tags.set", {
        organizationId: ORG,
        subjectType: "task",
        args: { add: ["x"] },
        limit: 5,
        atomic: true,
      })
      .orThrow();

    expect(fake.calls[0]?.args).toMatchObject({ args: { add: ["x"] } });
  });
});
