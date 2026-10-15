import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createIdempotency,
  createJobs,
  createRateLimit,
  purgeWebhookInbox,
  transportQueueBackend,
  withLease,
} from "../../../src/blocks/jobs/index.ts";
import { renderModules } from "../../../src/sql/render.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";

interface Call {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function fakeTransport(answers: Readonly<Record<string, unknown>>): {
  transport: BlockTransport;
  calls: Call[];
} {
  const calls: Call[] = [];
  return {
    calls,
    transport: {
      call: (schema, fn, args) => {
        calls.push({ schema, fn, args });
        return Promise.resolve(answers[fn] ?? null);
      },
    },
  };
}

/** The argument names of each wrapper `blocks.<module>.api` writes. */
function wrapperArgs(module: string): Map<string, readonly string[]> {
  const [file] = renderModules([module], {
    modules: { [module]: { api: "api" } },
  });
  const args = new Map<string, readonly string[]>();
  for (const match of file!.contents.matchAll(
    /create or replace function "api"\."(\w+)"\(([^)]*(?:\([^)]*\)[^)]*)*)\)/g,
  )) {
    args.set(
      match[1]!,
      match[2]!
        .split(",")
        .map((part) => part.trim().split(/\s+/)[0]!)
        .filter(Boolean),
    );
  }
  return args;
}

function expectWrapped(module: string, calls: readonly Call[]): void {
  const wrappers = wrapperArgs(module);
  expect(wrappers.size).toBeGreaterThan(3);
  for (const call of calls) {
    const declared = wrappers.get(call.fn);
    expect({ fn: call.fn, wrapped: declared !== undefined }).toEqual({
      fn: call.fn,
      wrapped: true,
    });
    for (const name of Object.keys(call.args)) {
      expect({
        fn: call.fn,
        arg: name,
        declared: declared?.includes(name),
      }).toEqual({
        fn: call.fn,
        arg: name,
        declared: true,
      });
    }
  }
}

const ROW = {
  id: 7,
  attempts: 1,
  enqueued_at: "2026-01-01T00:00:00Z",
  visible_until: "2026-01-01T00:05:00Z",
  message: { payload: { to: "a@b.test" }, max_attempts: 3 },
};

describe("transportQueueBackend", () => {
  it("calls every jobs function by name with the wrapper's argument names", async () => {
    const { transport, calls } = fakeTransport({
      enqueue_job: "7",
      claim_jobs: [ROW],
      complete_job: true,
      fail_job: "dead",
      extend_job_lease: true,
      replay_dead_job: 9,
      job_queue_stats: [
        {
          ready: "1",
          in_flight: 2,
          delayed: 0,
          dead: 3,
          oldest_age_seconds: "4.5",
        },
      ],
      list_dead_jobs: [{ ...ROW, died_at: null }],
      retry_dead_jobs: 2,
      unschedule_job: true,
      list_schedules: [
        {
          job_name: "nightly",
          schedule: "0 3 * * *",
          timezone: "UTC",
          queue: "emails",
          tenant: null,
          next_run: "2026-01-02T03:00:00Z",
          last_run: null,
          locked_until: null,
          created_at: "2026-01-01T00:00:00Z",
        },
      ],
      unschedule_tenant: 1,
      claim_due_schedules: [
        {
          job_name: "nightly",
          schedule: "0 3 * * *",
          timezone: "UTC",
          queue: "emails",
          payload: {},
          next_run: "2026-01-02T03:00:00Z",
        },
        {
          job_name: "later",
          schedule: "0 3 * * *",
          timezone: "UTC",
          queue: "emails",
          payload: {},
          next_run: null,
          first_after: "2999-01-01T00:00:00Z",
        },
      ],
      advance_schedule: true,
    });
    const backend = transportQueueBackend(transport, { schema: "api" });
    expect(
      await backend.send("emails", { to: "x" }, 0, 3, "k", "waiting"),
    ).toBe(7);
    const [row] = await backend.read("emails", 30, 1);
    expect(row?.id).toBe(7);
    const job = {
      id: 7,
      queue: "emails",
      payload: {},
      context: {},
      attempts: 1,
      maxAttempts: 3,
      enqueuedAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      visibleUntil: Temporal.Instant.from("2026-01-01T00:05:00Z"),
      lastError: null,
    };
    expect(await backend.complete(job)).toBe(true);
    expect(await backend.fail(job, "boom", 5)).toBe("dead");
    expect(await backend.extend(job, 60)).toBe(true);
    expect(await backend.replay!("emails", 7)).toBe(9);
    expect(await backend.stats!("emails")).toEqual({
      ready: 1,
      inFlight: 2,
      delayed: 0,
      dead: 3,
      oldestAgeSeconds: 4.5,
    });
    expect(await backend.listDead!("emails", 10, undefined)).toHaveLength(1);
    expect(await backend.retryDead!("emails", [1, 2], 10)).toBe(2);
    await backend.schedule(
      "nightly",
      "0 3 * * *",
      "emails",
      { kind: "digest" },
      "UTC",
      Temporal.Instant.from("2026-01-02T03:00:00Z"),
      "acme",
    );
    expect(await backend.unschedule("nightly")).toBe(true);
    const [info] = await backend.listSchedules!({ prefix: "n" });
    expect(info?.nextRun?.toString()).toBe("2026-01-02T03:00:00Z");
    expect(await backend.unscheduleTenant!("acme")).toBe(1);
    const due = await backend.dueSchedules!(60, 10);
    expect(due.map((entry) => entry.name)).toEqual(["nightly"]);
    expect(
      await backend.advanceSchedule!(
        "nightly",
        Temporal.Instant.from("2026-01-02T03:00:00Z"),
        Temporal.Instant.from("2026-01-03T03:00:00Z"),
      ),
    ).toBe(true);

    expect(new Set(calls.map((call) => call.schema))).toEqual(new Set(["api"]));
    expect(calls[0]!.args).toEqual({
      queue: "emails",
      payload: { to: "x" },
      delay: 0,
      max_attempts: 3,
      dedupe_key: "k",
      dedupe_running: false,
    });
    expect(
      calls.find((call) => call.fn === "advance_schedule")!.args,
    ).toMatchObject({ job_name: "later", ran: null });
    expectWrapped("jobs", calls);
  });

  it("is what createJobs uses for a transport, with stats and dead letters", async () => {
    const { transport, calls } = fakeTransport({
      job_queue_stats: {
        ready: 0,
        in_flight: 0,
        delayed: 0,
        dead: 1,
        oldest_age_seconds: null,
      },
      list_dead_jobs: [],
    });
    const jobs = createJobs(transport, { emails: v.object({}) });
    expect((await jobs.stats(["emails"]).orThrow()).emails.dead).toBe(1);
    expect(await jobs.listDead("emails").orThrow()).toEqual([]);
    expect(calls.map((call) => [call.schema, call.fn])).toEqual([
      ["better_supabase", "job_queue_stats"],
      ["better_supabase", "list_dead_jobs"],
    ]);
  });

  it("refuses a composite value it can't read as rows", async () => {
    const { transport } = fakeTransport({ claim_jobs: "(1,2)" });
    await expect(
      transportQueueBackend(transport).read("emails", 30, 1),
    ).rejects.toThrow(/pass a SqlClient/);
    const { transport: empty } = fakeTransport({ enqueue_job: null });
    await expect(
      transportQueueBackend(empty).send("emails", {}, 0, 1, undefined),
    ).rejects.toThrow(/no id/);
  });
});

describe("idempotency and leases over a transport", () => {
  it("begins, completes and releases keys by name", async () => {
    const { transport, calls } = fakeTransport({
      begin_idempotent: [
        { state: "started", status_code: null, response: null, holder: "h-1" },
      ],
      complete_idempotent: true,
      release_idempotent: true,
    });
    const idempotency = createIdempotency(transport, {
      schema: "api",
      ttl: 60,
    });
    const response = await idempotency.handle(
      new Request("https://api.test/orders", {
        method: "POST",
        headers: { "idempotency-key": "k-1" },
        body: "{}",
      }),
      () => Response.json({ ok: true }, { status: 201 }),
    );
    expect(response.status).toBe(201);
    expect(await idempotency.release("k-1", "h-1").orThrow()).toBe(true);
    expect(calls.map((call) => call.fn)).toEqual([
      "begin_idempotent",
      "complete_idempotent",
      "release_idempotent",
    ]);
    expect(calls[0]!.args).toMatchObject({ key: "k-1", ttl: "60 seconds" });
    expect(calls[1]!.args).toMatchObject({ holder: "h-1", status_code: 201 });

    const { transport: none } = fakeTransport({ begin_idempotent: [] });
    expect((await createIdempotency(none).begin("k", "f")).ok).toBe(false);
    expectWrapped("idempotency", calls);
  });

  it("acquires, extends and releases a lease", async () => {
    const { transport, calls } = fakeTransport({
      acquire_lease: "holder-1",
      extend_lease: true,
      release_lease: true,
    });
    const outcome = await withLease(
      transport,
      "nightly",
      async (lease) => {
        expect(await lease.extend(120).orThrow()).toBe(true);
        return lease.holder;
      },
      { scope: "acme" },
    ).orThrow();
    expect(outcome).toEqual({ acquired: true, value: "holder-1" });
    expect(calls.map((call) => call.fn)).toEqual([
      "acquire_lease",
      "extend_lease",
      "release_lease",
    ]);
    expect(calls[1]!.args).toEqual({
      key: "nightly",
      holder: "holder-1",
      seconds: 120,
      scope: "acme",
    });
    expectWrapped("idempotency", calls);

    const { transport: taken } = fakeTransport({ acquire_lease: null });
    expect(await withLease(taken, "nightly", () => 1).orThrow()).toEqual({
      acquired: false,
    });
  });
});

describe("purge", () => {
  const signal = new AbortController().signal;

  it("purges every declared queue's archive by name", async () => {
    const { transport, calls } = fakeTransport({ purge_job_archive: 2 });
    const jobs = createJobs(transport, {
      emails: v.object({}),
      reports: v.object({}),
    });
    expect(
      await jobs
        .purge({ olderThan: 3600, deadOlderThan: "90 days", batch: 5 })
        .orThrow(),
    ).toBe(4);
    expect(
      await jobs.purgeJob({ queues: ["emails"] })({}, {} as never, signal),
    ).toBe(2);
    expect(calls.map((call) => call.args)).toEqual([
      {
        queue: "emails",
        older_than: "3600 seconds",
        batch: 5,
        dead_older_than: "90 days",
      },
      {
        queue: "reports",
        older_than: "3600 seconds",
        batch: 5,
        dead_older_than: "90 days",
      },
      { queue: "emails" },
    ]);
    expectWrapped("jobs", calls);
  });

  it("purges the archive over SQL with only the options given", async () => {
    const fake = fakeSql([["purge_job_archive", [{ purged: 3 }]]]);
    const jobs = createJobs(fake.sql, { emails: v.object({}) });
    expect(await jobs.purge({ batch: 10 }).orThrow()).toBe(3);
    expect(fake.calls).toEqual([
      {
        text: "select better_supabase.purge_job_archive(queue => $1, batch => $2) as purged",
        values: ["emails", 10],
      },
    ]);
  });

  it("purges idempotency keys, rate limits and the inbox over a transport", async () => {
    const { transport, calls } = fakeTransport({
      purge_idempotency_keys: 4,
      purge_rate_limits: "6",
      purge_webhooks: 1,
    });
    expect(
      await createIdempotency(transport, { schema: "api" }).purge().orThrow(),
    ).toBe(4);
    expect(
      await createRateLimit(transport).purge({ batch: 100 }).orThrow(),
    ).toBe(6);
    expect(
      await createRateLimit(transport).purgeJob()({}, {} as never, signal),
    ).toBe(6);
    expect(
      await purgeWebhookInbox(transport, {
        tenant: "acme",
        olderThan: 0,
      }).orThrow(),
    ).toBe(1);
    expect(calls.map((call) => [call.schema, call.fn, call.args])).toEqual([
      ["api", "purge_idempotency_keys", {}],
      ["better_supabase", "purge_rate_limits", { batch: 100 }],
      ["better_supabase", "purge_rate_limits", { batch: undefined }],
      [
        "better_supabase",
        "purge_webhooks",
        {
          older_than: "0 seconds",
          include_dead: false,
          batch: 10_000,
          for_tenant: "acme",
        },
      ],
    ]);
    expectWrapped("idempotency", calls.slice(0, 1));
  });

  it("purges idempotency keys and rate limits over SQL", async () => {
    const fake = fakeSql([
      ["purge_idempotency_keys", [{ purged: 2 }]],
      ["purge_rate_limits", [{ value: 7 }]],
    ]);
    expect(await createIdempotency(fake.sql).purge().orThrow()).toBe(2);
    expect(await createRateLimit(fake.sql).purge().orThrow()).toBe(7);
  });
});
