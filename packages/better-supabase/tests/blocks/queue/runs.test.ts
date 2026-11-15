import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createQueue } from "../../../src/blocks/queue/index.ts";
import { createJobs } from "../../../src/core/jobs.ts";

const run = (overrides: Record<string, unknown> = {}) => ({
  queue: "mail",
  id: 7,
  state: "waiting",
  attempts: 0,
  maxAttempts: 5,
  enqueuedAt: "2026-11-15T10:00:00Z",
  finishedAt: null,
  lastError: null,
  ...overrides,
});

function queue(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  const client = createQueue({
    queues: { mail: v.object({ to: v.string() }) },
    transport: {
      call(_schema, fn, args) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  });

  return { calls, client, jobs: createJobs({ queue: client.runs }) };
}

describe("queue runs", () => {
  it("returns a job ref from enqueueJob", async () => {
    const { client } = queue({ enqueue_job: 7 });

    expect(
      await client
        .enqueueJob({ queue: "mail", payload: { to: "a@b.c" } })
        .orThrow(),
    ).toEqual({ jobId: "queue:mail:7" });
  });

  it("reads one message without its payload", async () => {
    const { calls, client } = queue({ get_job: run({ state: "running" }) });

    expect(await client.get({ queue: "mail", id: 7 }).orThrow()).toMatchObject({
      state: "running",
      attempts: 0,
    });
    expect(calls).toEqual([["get_job", { queue: "mail", job_id: 7 }]]);
  });

  it("maps each state to a job status", async () => {
    const read = async (row: Record<string, unknown>) =>
      queue({ get_job: run(row) })
        .jobs.get("queue:mail:7")
        .orThrow();

    expect(await read({})).toMatchObject({ status: "pending", done: false });
    expect(await read({ state: "running" })).toMatchObject({
      status: "running",
    });
    expect(await read({ state: "done", finishedAt: "x" })).toMatchObject({
      status: "completed",
      done: true,
    });
    expect(await read({ state: "dead", lastError: "boom" })).toMatchObject({
      status: "failed",
      error: { message: "boom", hint: "QUEUE_JOB_DEAD" },
    });
  });

  it("reads an unknown message, queue or id as null", async () => {
    const read = (results: Record<string, unknown>, id: string) =>
      queue(results).client.runs.get(id).orThrow();

    expect(await read({ get_job: null }, "mail:9")).toBeNull();
    expect(await read({ get_job: run() }, "other:7")).toBeNull();
    expect(await read({ get_job: run() }, "mail:x")).toBeNull();
    expect(
      await queue({ get_job: null }).jobs.get("queue:mail:9"),
    ).toMatchObject({ ok: false, error: { kind: "not_found" } });
  });
});
