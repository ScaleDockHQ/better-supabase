import * as v from "valibot";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { DbError } from "../../src/core/errors.ts";

import { ok } from "../../src/core/result.ts";
import {
  createIdempotency,
  createInbox,
  createJobs,
  entitlementMembers,
  ENTITLEMENTS_UPDATED,
  type Job,
  type QueueRpcClient,
} from "../../src/jobs/index.ts";
import { signWebhook } from "../../src/webhooks/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { fakeSql, pgError, type SqlAnswer } from "../fixtures/fake-sql.ts";

interface Call {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function fakeClient(
  respond: (call: Call) => unknown,
  error: (call: Call) => unknown = () => null,
): {
  client: QueueRpcClient;
  calls: Call[];
} {
  const calls: Call[] = [];
  const client: QueueRpcClient = {
    schema: (schema) => ({
      rpc: (fn, args) => {
        const call = { schema, fn, args };
        calls.push(call);
        return Promise.resolve({ data: respond(call), error: error(call) });
      },
    }),
  };
  return { client, calls };
}

/** Answers the first calls with `answers` in order, then with no rows. */
function sequence(...answers: SqlAnswer[]): () => SqlAnswer {
  let index = 0;
  return () => answers[index++] ?? [];
}

const queues = {
  emails: v.object({ to: v.pipe(v.string(), v.email()) }),
  reports: v.object({
    day: v.pipe(
      v.string(),
      v.transform((value) => value.toUpperCase()),
    ),
  }),
};

const messageRow = (id: number | string, payload: unknown, extra = {}) => ({
  id,
  attempts: 1,
  enqueued_at: "2026-09-24T10:00:00Z",
  visible_until: new Date("2026-09-24T10:05:00Z"),
  message: { payload, max_attempts: 3 },
  ...extra,
});

const sampleJob = (overrides: Partial<Job> = {}): Job => ({
  id: 12,
  queue: "emails",
  payload: { to: "a@example.com" },
  attempts: 2,
  maxAttempts: 5,
  enqueuedAt: new Date(0),
  visibleUntil: new Date(0),
  lastError: null,
  ...overrides,
});

afterEach(() => {
  vi.useRealTimers();
});

describe("createJobs over pgmq_public", () => {
  it("sends, reads and archives through PostgREST", async () => {
    const { client, calls } = fakeClient(({ fn }) => {
      if (fn === "send") return [7];
      if (fn === "read") {
        return [
          {
            msg_id: 7,
            read_ct: 1,
            enqueued_at: "2026-09-24T10:00:00Z",
            vt: "2026-09-24T10:05:00Z",
            message: { payload: { to: "a@example.com" }, max_attempts: 1 },
          },
        ];
      }
      return true;
    });
    const jobs = createJobs(client, {
      emails: v.object({ to: v.pipe(v.string(), v.email()) }),
    });

    expect(
      await jobs
        .enqueue("emails", { to: "a@example.com" }, { delay: 5 })
        .orThrow(),
    ).toBe(7);
    const [job] = await jobs.claim("emails", { lease: 60 }).orThrow();
    expect(job).toMatchObject({
      id: 7,
      queue: "emails",
      attempts: 1,
      maxAttempts: 1,
      payload: { to: "a@example.com" },
      lastError: null,
    });
    expect(await jobs.fail(job!, "boom").orThrow()).toBe("dead");
    expect(calls).toEqual([
      {
        schema: "pgmq_public",
        fn: "send",
        args: {
          queue_name: "emails",
          message: { payload: { to: "a@example.com" }, max_attempts: 5 },
          sleep_seconds: 5,
        },
      },
      {
        schema: "pgmq_public",
        fn: "read",
        args: { queue_name: "emails", sleep_seconds: 60, n: 1 },
      },
      {
        schema: "pgmq_public",
        fn: "archive",
        args: { queue_name: "emails", message_id: 7 },
      },
    ]);
  });

  it("refuses SQL-only features and invalid queue names", async () => {
    const { client } = fakeClient(() => [1]);
    const jobs = createJobs(client, { emails: v.object({}) });
    const deduped = await jobs.enqueue("emails", {}, { dedupeKey: "x" });
    expect(deduped.error).toMatchObject({
      kind: "invalid_request",
      message: expect.stringContaining("dedupeKey needs a SQL connection"),
    });
    expect(
      (await jobs.schedule("nightly", "0 3 * * *", "emails", {})).error?.kind,
    ).toBe("invalid_request");
    expect((await jobs.unschedule("nightly")).error).toMatchObject({
      kind: "invalid_request",
      message: expect.stringContaining("unschedule needs a SQL connection"),
    });
    expect(() => createJobs(client, { "send-emails": v.object({}) })).toThrow(
      "pgmq queue names",
    );
    expect(() =>
      createJobs(client, { ["a".repeat(48)]: v.object({}) }),
    ).toThrow("at most 47");
  });

  it("goes through supabase-js as POST /rpc on the pgmq_public schema", async () => {
    const { client, requests } = capturingClient(({ path }) =>
      path.endsWith("/send") ? { body: ["41"] } : { body: true },
    );
    const jobs = createJobs(client, queues);
    expect(
      await jobs.enqueue("emails", { to: "a@example.com" }).orThrow(),
    ).toBe(41);
    expect(await jobs.complete(sampleJob({ id: 41 })).orThrow()).toBe(true);
    expect(requests.map((request) => [request.method, request.path])).toEqual([
      ["POST", "/rest/v1/rpc/send"],
      ["POST", "/rest/v1/rpc/archive"],
    ]);
    expect(requests[0]!.headers.get("content-profile")).toBe("pgmq_public");
    expect(requests[0]!.body).toEqual({
      queue_name: "emails",
      message: { payload: { to: "a@example.com" }, max_attempts: 5 },
      sleep_seconds: 0,
    });
  });

  it("returns a PostgREST error as a result that names the function", async () => {
    const { client } = capturingClient(() => ({
      status: 400,
      body: { code: "P0001", message: "queue emails does not exist" },
    }));
    const result = await createJobs(client, queues).claim("emails");
    expect(result.error).toMatchObject({
      kind: "unexpected",
      message: "pgmq_public.read: queue emails does not exist",
    });
  });

  it("describes a non-object rpc error with its string form", async () => {
    const { client } = fakeClient(
      () => null,
      () => "permission denied",
    );
    const result = await createJobs(client, queues).enqueue("emails", {
      to: "a@example.com",
    });
    expect(result.error?.message).toBe("pgmq_public.send: permission denied");
  });

  it("leaves a failed job queued until its last attempt, and cannot extend a lease", async () => {
    const { client, calls } = fakeClient(() => true);
    const jobs = createJobs(client, queues);
    expect(
      await jobs
        .fail(sampleJob({ attempts: 2, maxAttempts: 5 }), "x")
        .orThrow(),
    ).toBe("queued");
    expect(calls).toHaveLength(0);
    expect(await jobs.extend(sampleJob(), 60).orThrow()).toBe(false);
  });

  it("does not start a heartbeat for PostgREST workers", async () => {
    vi.useFakeTimers();
    let finish!: () => void;
    const { client, calls } = fakeClient(
      sequence(
        [
          {
            msg_id: 1,
            read_ct: 1,
            enqueued_at: "2026-09-24T10:00:00Z",
            vt: "2026-09-24T10:05:00Z",
            message: { payload: { to: "a@example.com" } },
          },
        ],
        // the archive call, then an empty read
        true as never,
        [],
      ),
    );
    const draining = createJobs(client, queues).drain(
      "emails",
      () =>
        new Promise<void>((resolve) => {
          finish = resolve;
        }),
      { lease: 2 },
    );
    await vi.advanceTimersByTimeAsync(5000);
    finish();
    expect(await draining).toEqual({ succeeded: 1, failed: 0 });
    expect(calls.map((call) => call.fn)).toEqual(["read", "archive", "read"]);
  });
});

describe("createJobs over SQL", () => {
  it("enqueues through enqueue_job with the validated payload and defaults", async () => {
    const fake = fakeSql([["enqueue_job", [{ id: "17" }]]]);
    const jobs = createJobs(fake.sql, queues);
    expect(await jobs.enqueue("reports", { day: "mon" }).orThrow()).toBe(17);
    expect(fake.calls).toEqual([
      {
        text: "select better_supabase.enqueue_job($1, $2, $3, $4, $5) as id",
        values: ["reports", '{"day":"MON"}', 0, 5, null],
      },
    ]);
  });

  it("passes delay, max attempts and the dedupe key", async () => {
    const fake = fakeSql([["enqueue_job", [{ id: 3 }]]]);
    await createJobs(fake.sql, queues)
      .enqueue(
        "emails",
        { to: "a@example.com" },
        { delay: 30, maxAttempts: 2, dedupeKey: "welcome:u1" },
      )
      .orThrow();
    expect(fake.calls[0]!.values).toEqual([
      "emails",
      '{"to":"a@example.com"}',
      30,
      2,
      "welcome:u1",
    ]);
  });

  it("turns runAt into a delay in whole seconds, never negative", async () => {
    vi.useFakeTimers({ now: new Date("2026-10-01T12:00:00.000Z") });
    const fake = fakeSql([["enqueue_job", [{ id: 1 }]]]);
    const jobs = createJobs(fake.sql, queues);
    await jobs
      .enqueue(
        "emails",
        { to: "a@example.com" },
        { runAt: new Date("2026-10-01T12:01:00.200Z") },
      )
      .orThrow();
    await jobs
      .enqueue(
        "emails",
        { to: "a@example.com" },
        { runAt: new Date("2026-10-01T11:00:00Z") },
      )
      .orThrow();
    expect(fake.calls.map((call) => call.values[2])).toEqual([61, 0]);
  });

  it("enqueues an empty object when the schema output is undefined", async () => {
    const fake = fakeSql([["enqueue_job", [{ id: 1 }]]]);
    await createJobs(fake.sql, { ping: v.optional(v.object({})) })
      .enqueue("ping", undefined)
      .orThrow();
    expect(fake.calls[0]!.values[1]).toBe("{}");
  });

  it("rejects an invalid payload without a query", async () => {
    const fake = fakeSql();
    const jobs = createJobs(fake.sql, queues);
    const result = await jobs.enqueue("emails", { to: "not an email" });
    expect(result.error?.kind).toBe("validation");
    const scheduled = await jobs.schedule("nightly", "0 3 * * *", "emails", {
      to: 1,
    } as never);
    expect(scheduled.error?.kind).toBe("validation");
    expect(fake.calls).toHaveLength(0);
  });

  it("maps a pg error from the kit functions", async () => {
    const fake = fakeSql([
      [
        "enqueue_job",
        {
          throws: pgError("23505", "duplicate key value", {
            constraint: "job_dedupe_key",
          }),
        },
      ],
    ]);
    const result = await createJobs(fake.sql, queues).enqueue("emails", {
      to: "a@example.com",
    });
    expect(result.error).toMatchObject({
      kind: "conflict",
      message: "duplicate key value",
      constraint: "job_dedupe_key",
    });
  });

  it("claims jobs and maps the rows", async () => {
    const fake = fakeSql([
      [
        "claim_jobs",
        [
          messageRow(
            "12",
            { to: "a@example.com" },
            {
              attempts: 2,
              message: {
                payload: { to: "a@example.com" },
                max_attempts: 3,
                last_error: "timeout",
              },
            },
          ),
          messageRow(13, undefined, { message: null }),
        ],
      ],
    ]);
    const jobs = await createJobs(fake.sql, queues)
      .claim("emails", { batch: 2, lease: 60 })
      .orThrow();
    expect(fake.calls[0]).toEqual({
      text: "select * from better_supabase.claim_jobs($1, $2, $3)",
      values: ["emails", 60, 2],
    });
    expect(jobs).toEqual([
      {
        id: 12,
        queue: "emails",
        payload: { to: "a@example.com" },
        attempts: 2,
        maxAttempts: 3,
        enqueuedAt: new Date("2026-09-24T10:00:00Z"),
        visibleUntil: new Date("2026-09-24T10:05:00Z"),
        lastError: "timeout",
      },
      {
        id: 13,
        queue: "emails",
        payload: undefined,
        attempts: 1,
        maxAttempts: 5,
        enqueuedAt: new Date("2026-09-24T10:00:00Z"),
        visibleUntil: new Date("2026-09-24T10:05:00Z"),
        lastError: null,
      },
    ]);
  });

  it("claims one job for 300 seconds by default, and rejects unknown queues", async () => {
    const fake = fakeSql();
    const jobs = createJobs(fake.sql, queues);
    expect(await jobs.claim("emails").orThrow()).toEqual([]);
    expect(fake.calls[0]!.values).toEqual(["emails", 300, 1]);
    const unknown = await jobs.claim("sms" as never);
    expect(unknown.error).toMatchObject({
      message: 'Unknown queue "sms". Queues: emails, reports',
    });
  });

  it("completes, fails and extends with the lease check arguments", async () => {
    const fake = fakeSql([
      ["complete_job", [{ done: true }]],
      ["fail_job", [{ status: "dead" }]],
      ["extend_job_lease", [{ extended: true }]],
    ]);
    const jobs = createJobs(fake.sql, queues);
    const job = sampleJob();
    expect(await jobs.complete(job).orThrow()).toBe(true);
    expect(
      await jobs.fail(job, new Error("smtp down"), { retryIn: 90 }).orThrow(),
    ).toBe("dead");
    expect(await jobs.extend(job, 120).orThrow()).toBe(true);
    expect(fake.calls).toEqual([
      {
        text: "select better_supabase.complete_job($1, $2, $3) as done",
        values: ["emails", 12, 2],
      },
      {
        text: "select better_supabase.fail_job($1, $2, $3, $4, $5) as status",
        values: ["emails", 12, 2, "smtp down", 90],
      },
      {
        text: "select better_supabase.extend_job_lease($1, $2, $3, $4) as extended",
        values: ["emails", 12, 2, 120],
      },
    ]);
  });

  it("reports a lost lease when the kit functions return no row", async () => {
    const fake = fakeSql();
    const jobs = createJobs(fake.sql, queues);
    const job = sampleJob();
    expect(await jobs.complete(job).orThrow()).toBe(false);
    expect(await jobs.fail(job, "x").orThrow()).toBeNull();
    expect(await jobs.extend(job, 10).orThrow()).toBe(false);
    expect(await jobs.unschedule("nightly").orThrow()).toBe(false);
    expect(fake.calls[1]!.values[4]).toBeNull();
  });

  it("stores the message of any error value", async () => {
    const fake = fakeSql([["fail_job", [{ status: "queued" }]]]);
    const jobs = createJobs(fake.sql, queues);
    await jobs.fail(sampleJob(), { message: "from a DbError" }).orThrow();
    await jobs.fail(sampleJob(), 404).orThrow();
    await jobs.fail(sampleJob(), null).orThrow();
    expect(fake.calls.map((call) => call.values[3])).toEqual([
      "from a DbError",
      "404",
      "null",
    ]);
  });

  it("schedules and unschedules through pg_cron", async () => {
    const fake = fakeSql([["unschedule_job", [{ done: true }]]]);
    const jobs = createJobs(fake.sql, queues);
    await jobs
      .schedule("nightly", "0 3 * * *", "reports", { day: "sun" })
      .orThrow();
    expect(await jobs.unschedule("nightly").orThrow()).toBe(true);
    expect(fake.calls).toEqual([
      {
        text: "select better_supabase.schedule_job($1, $2, $3, $4)",
        values: ["nightly", "0 3 * * *", "reports", '{"day":"SUN"}'],
      },
      {
        text: "select better_supabase.unschedule_job($1) as done",
        values: ["nightly"],
      },
    ]);
  });
});

describe("drain and work", () => {
  it("drains the queue with the validated payload and completes each job", async () => {
    const fake = fakeSql([
      [
        "claim_jobs",
        sequence(
          [messageRow(1, { day: "mon" })],
          [messageRow(2, { day: "tue" })],
        ),
      ],
      ["complete_job", [{ done: true }]],
    ]);
    const seen: unknown[] = [];
    const result = await createJobs(fake.sql, queues).drain(
      "reports",
      (payload, job, signal) => {
        seen.push([payload, job.payload, job.id, signal.aborted]);
      },
    );
    expect(result).toEqual({ succeeded: 2, failed: 0 });
    expect(seen).toEqual([
      [{ day: "MON" }, { day: "MON" }, 1, false],
      [{ day: "TUE" }, { day: "TUE" }, 2, false],
    ]);
    expect(
      fake.texts().filter((text) => text.includes("complete_job")),
    ).toHaveLength(2);
    expect(fake.calls.at(-1)!.text).toContain("claim_jobs");
  });

  it("fails a job whose handler throws, aborts its signal and reports the error", async () => {
    const fake = fakeSql([
      ["claim_jobs", sequence([messageRow(5, { to: "a@example.com" })])],
      ["fail_job", [{ status: "queued" }]],
    ]);
    const errors: [DbError, Job][] = [];
    let signal: AbortSignal | undefined;
    const result = await createJobs(fake.sql, queues).drain(
      "emails",
      (_payload, _job, received) => {
        signal = received;
        throw new Error("smtp down");
      },
      { onError: (error, job) => errors.push([error, job]) },
    );
    expect(result).toEqual({ succeeded: 0, failed: 1 });
    expect(signal?.aborted).toBe(true);
    const failCall = fake.calls.find((call) => call.text.includes("fail_job"));
    expect(failCall?.values).toEqual(["emails", 5, 1, "smtp down", null]);
    expect(errors).toHaveLength(1);
    expect(errors[0]![0]).toMatchObject({
      kind: "unexpected",
      message: "smtp down",
    });
    expect(errors[0]![1].id).toBe(5);
    expect(fake.texts().some((text) => text.includes("complete_job"))).toBe(
      false,
    );
  });

  it("fails a job whose handler returns a failed Result, passing the DbError on", async () => {
    const fake = fakeSql([
      ["claim_jobs", sequence([messageRow(6, { to: "a@example.com" })])],
    ]);
    const errors: DbError[] = [];
    const failure = {
      ok: false,
      error: { kind: "conflict", message: "already sent" },
    };
    const result = await createJobs(fake.sql, queues).drain(
      "emails",
      () => failure,
      { onError: (error) => errors.push(error) },
    );
    expect(result).toEqual({ succeeded: 0, failed: 1 });
    expect(errors).toEqual([failure.error]);
    expect(
      fake.calls.find((call) => call.text.includes("fail_job"))?.values[3],
    ).toBe("already sent");
  });

  it("treats a returned success Result or other value as done", async () => {
    const fake = fakeSql([
      [
        "claim_jobs",
        sequence(
          [messageRow(1, { to: "a@example.com" })],
          [messageRow(2, { to: "a@example.com" })],
          [messageRow(3, { to: "a@example.com" })],
        ),
      ],
    ]);
    const outcomes: unknown[] = [{ ok: true, data: 1 }, { ok: false }, "sent"];
    const result = await createJobs(fake.sql, queues).drain("emails", () =>
      outcomes.shift(),
    );
    expect(result).toEqual({ succeeded: 3, failed: 0 });
  });

  it("fails a job whose stored payload no longer matches the schema", async () => {
    const fake = fakeSql([
      ["claim_jobs", sequence([messageRow(8, { to: "nope" })])],
    ]);
    const handler = vi.fn();
    const errors: DbError[] = [];
    const result = await createJobs(fake.sql, queues).drain("emails", handler, {
      onError: (error) => errors.push(error),
    });
    expect(result).toEqual({ succeeded: 0, failed: 1 });
    expect(handler).not.toHaveBeenCalled();
    expect(errors[0]?.kind).toBe("validation");
    expect(
      fake.calls.find((call) => call.text.includes("fail_job"))?.values[3],
    ).toBe(errors[0]?.message);
  });

  it("counts failures without an onError callback", async () => {
    const fake = fakeSql([
      [
        "claim_jobs",
        sequence(
          [messageRow(1, { to: "nope" })],
          [messageRow(2, { to: "a@example.com" })],
        ),
      ],
    ]);
    const result = await createJobs(fake.sql, queues).drain("emails", () => {
      throw new Error("x");
    });
    expect(result).toEqual({ succeeded: 0, failed: 2 });
  });

  it("rejects when a claim fails, with the DbError as the cause", async () => {
    const fake = fakeSql([
      [
        "claim_jobs",
        {
          throws: pgError("42501", "permission denied for function claim_jobs"),
        },
      ],
    ]);
    const failure = await createJobs(fake.sql, queues)
      .drain("emails", () => undefined)
      .catch((error: unknown) => error);
    expect(failure).toBeInstanceOf(TypeError);
    expect((failure as Error).message).toBe(
      "permission denied for function claim_jobs",
    );
    expect((failure as Error).cause).toMatchObject({ kind: "forbidden" });
  });

  it("runs `concurrency` lanes at once, each claiming `batch` jobs", async () => {
    const fake = fakeSql([
      [
        "claim_jobs",
        sequence(
          [messageRow(1, { to: "a@example.com" })],
          [messageRow(2, { to: "b@example.com" })],
        ),
      ],
    ]);
    let started = 0;
    let bothStarted!: () => void;
    const barrier = new Promise<void>((resolve) => {
      bothStarted = resolve;
    });
    const result = await createJobs(fake.sql, queues).drain(
      "emails",
      async () => {
        started += 1;
        if (started === 2) bothStarted();
        await barrier;
      },
      { concurrency: 2, batch: 3 },
    );
    expect(result).toEqual({ succeeded: 2, failed: 0 });
    const claims = fake.calls.filter((call) =>
      call.text.includes("claim_jobs"),
    );
    expect(claims[0]!.values).toEqual(["emails", 300, 3]);
    expect(claims).toHaveLength(4);
  });

  it("runs one lane when concurrency is below one", async () => {
    const fake = fakeSql();
    await createJobs(fake.sql, queues).drain("emails", () => undefined, {
      concurrency: 0,
    });
    expect(fake.calls).toHaveLength(1);
  });

  it("extends the lease every half lease while a handler runs, then stops", async () => {
    vi.useFakeTimers();
    let finish!: () => void;
    const fake = fakeSql([
      ["claim_jobs", sequence([messageRow(9, { to: "a@example.com" })])],
      ["extend_job_lease", [{ extended: true }]],
      ["complete_job", [{ done: true }]],
    ]);
    const leaseExtensions = () =>
      fake.calls.filter((call) => call.text.includes("extend_job_lease"));
    const draining = createJobs(fake.sql, queues).drain(
      "emails",
      () =>
        new Promise<void>((resolve) => {
          finish = resolve;
        }),
      { lease: 4 },
    );
    await vi.advanceTimersByTimeAsync(1999);
    expect(leaseExtensions()).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(1);
    expect(leaseExtensions()).toHaveLength(1);
    expect(leaseExtensions()[0]!.values).toEqual(["emails", 9, 1, 4]);
    await vi.advanceTimersByTimeAsync(2000);
    expect(leaseExtensions()).toHaveLength(2);
    finish();
    expect(await draining).toEqual({ succeeded: 1, failed: 0 });
    await vi.advanceTimersByTimeAsync(10_000);
    expect(leaseExtensions()).toHaveLength(2);
    expect(vi.getTimerCount()).toBe(0);
  });

  it("beats at least once a second for short leases, and ignores a failed extend", async () => {
    vi.useFakeTimers();
    let finish!: () => void;
    const fake = fakeSql([
      ["claim_jobs", sequence([messageRow(9, { to: "a@example.com" })])],
      ["extend_job_lease", { throws: new Error("connection reset") }],
    ]);
    const draining = createJobs(fake.sql, queues).drain(
      "emails",
      () =>
        new Promise<void>((resolve) => {
          finish = resolve;
        }),
      { lease: 1 },
    );
    await vi.advanceTimersByTimeAsync(999);
    expect(fake.texts().filter((text) => text.includes("extend"))).toHaveLength(
      0,
    );
    await vi.advanceTimersByTimeAsync(1);
    expect(fake.texts().filter((text) => text.includes("extend"))).toHaveLength(
      1,
    );
    finish();
    expect(await draining).toEqual({ succeeded: 1, failed: 0 });
  });

  it("polls an empty queue every pollInterval until the signal aborts", async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const fake = fakeSql([
      ["claim_jobs", sequence([], [messageRow(1, { to: "a@example.com" })])],
    ]);
    const claims = () =>
      fake.texts().filter((text) => text.includes("claim_jobs"));
    const working = createJobs(fake.sql, queues).work(
      "emails",
      () => {
        controller.abort();
      },
      { signal: controller.signal, pollInterval: 50 },
    );
    await vi.advanceTimersByTimeAsync(49);
    expect(claims()).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(await working).toEqual({ succeeded: 1, failed: 0 });
    expect(claims()).toHaveLength(2);
  });

  it("waits a second between polls by default and wakes up on abort", async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const fake = fakeSql();
    const working = createJobs(fake.sql, queues).work(
      "emails",
      () => undefined,
      {
        signal: controller.signal,
      },
    );
    await vi.advanceTimersByTimeAsync(999);
    expect(fake.calls).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(fake.calls).toHaveLength(2);
    controller.abort();
    expect(await working).toEqual({ succeeded: 0, failed: 0 });
    expect(vi.getTimerCount()).toBe(0);
    expect(fake.calls).toHaveLength(2);
  });

  it("does not sleep when the signal aborts during a claim", async () => {
    const controller = new AbortController();
    const fake = fakeSql([
      [
        "claim_jobs",
        () => {
          controller.abort();
          return [];
        },
      ],
    ]);
    const result = await createJobs(fake.sql, queues).work(
      "emails",
      () => undefined,
      {
        signal: controller.signal,
        pollInterval: 60_000,
      },
    );
    expect(result).toEqual({ succeeded: 0, failed: 0 });
  });

  it("does nothing with a signal that already aborted", async () => {
    const fake = fakeSql();
    const result = await createJobs(fake.sql, queues).work(
      "emails",
      () => undefined,
      {
        signal: AbortSignal.abort(),
      },
    );
    expect(result).toEqual({ succeeded: 0, failed: 0 });
    expect(fake.calls).toHaveLength(0);
  });
});

describe("createIdempotency", () => {
  it("calls the kit functions with the scope, key and intervals", async () => {
    const fake = fakeSql([
      [
        "begin_idempotent",
        [
          {
            state: "replay",
            status_code: 201,
            response: { body: "{}", contentType: null },
          },
        ],
      ],
    ]);
    const idempotency = createIdempotency(fake.sql);
    expect(await idempotency.begin("k1", "fp").orThrow()).toEqual({
      state: "replay",
      status: 201,
      body: { body: "{}", contentType: null },
    });
    await idempotency.complete("k1", 200, { ok: 1 }, "tenant").orThrow();
    await idempotency.release("k1").orThrow();
    expect(fake.calls).toEqual([
      {
        text: "select * from better_supabase.begin_idempotent($1, $2, $3, $4::interval, $5::interval)",
        values: ["", "k1", "fp", "24 hours", "1 minute"],
      },
      {
        text: "select better_supabase.complete_idempotent($1, $2, $3, $4)",
        values: ["tenant", "k1", 200, '{"ok":1}'],
      },
      {
        text: "select better_supabase.release_idempotent($1, $2)",
        values: ["", "k1"],
      },
    ]);
  });

  it("fingerprints the method, path and body, with a fixed scope", async () => {
    const fake = fakeSql([
      [
        "begin_idempotent",
        [{ state: "started", status_code: null, response: null }],
      ],
    ]);
    const idempotency = createIdempotency(fake.sql, { scope: "acme" });
    const response = await idempotency.handle(
      new Request("https://api.test/payments?x=1", {
        method: "POST",
        headers: { "idempotency-key": "k1" },
        body: '{"amount":10}',
      }),
      () => new Response("created", { status: 201 }),
    );
    expect(response.status).toBe(201);
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode('POST /payments\n{"amount":10}'),
    );
    const hex = Array.from(new Uint8Array(digest), (byte) =>
      byte.toString(16).padStart(2, "0"),
    ).join("");
    expect(fake.calls[0]!.values.slice(0, 3)).toEqual(["acme", "k1", hex]);
    expect(fake.calls[1]!.values).toEqual([
      "acme",
      "k1",
      201,
      JSON.stringify({
        body: "created",
        contentType: "text/plain;charset=UTF-8",
      }),
    ]);
  });

  it("replays a stored response without a content type as 200", async () => {
    const fake = fakeSql([
      [
        "begin_idempotent",
        [
          {
            state: "replay",
            status_code: null,
            response: { body: "done", contentType: null },
          },
        ],
      ],
    ]);
    const handler = vi.fn();
    const response = await createIdempotency(fake.sql).handle(
      new Request("https://api.test/x", {
        method: "POST",
        headers: { "idempotency-key": "k" },
      }),
      handler,
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("done");
    expect(response.headers.get("idempotency-replayed")).toBe("true");
    expect(handler).not.toHaveBeenCalled();
  });

  it("answers with a problem when the key cannot be stored", async () => {
    const fake = fakeSql([
      ["begin_idempotent", { throws: pgError("42501", "permission denied") }],
    ]);
    const handler = vi.fn();
    const response = await createIdempotency(fake.sql).handle(
      new Request("https://api.test/x", {
        method: "POST",
        headers: { "idempotency-key": "k" },
      }),
      handler,
    );
    expect(response.status).toBe(403);
    expect(response.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    expect(handler).not.toHaveBeenCalled();
  });
});

describe("createInbox", () => {
  const secret = `whsec_${btoa("inbox-test-secret-key")}`;

  async function signed(
    body: unknown,
    id = "msg_1",
    headers: Record<string, string> = {},
  ): Promise<Request> {
    const text = JSON.stringify(body);
    return new Request("https://api.test/webhooks/stripe", {
      method: "POST",
      headers: {
        ...(await signWebhook(secret, { id, body: text })),
        ...headers,
      },
      body: text,
    });
  }

  it("needs secrets or a verify function", () => {
    expect(() => createInbox(fakeSql().sql, { source: "stripe" })).toThrow(
      "createInbox needs `secrets` (Standard Webhooks) or `verify`",
    );
  });

  it("answers 405 to anything but POST", async () => {
    const fake = fakeSql();
    const response = await createInbox(fake.sql, {
      source: "stripe",
      secrets: secret,
    }).receive(new Request("https://api.test/webhooks/stripe"));
    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("POST");
    expect(fake.calls).toHaveLength(0);
  });

  it("verifies and stores a webhook with its type and kept headers", async () => {
    const fake = fakeSql([
      ["receive_webhook", [{ id: "5", duplicate: false }]],
    ]);
    const inbox = createInbox(fake.sql, {
      source: "stripe",
      secrets: [secret],
      keepHeaders: ["X-Request-Id", "x-missing"],
    });
    const response = await inbox.receive(
      await signed({ type: "invoice.paid", amount: 10 }, "msg_1", {
        "x-request-id": "r1",
      }),
    );
    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ id: 5, duplicate: false });
    expect(fake.calls).toEqual([
      {
        text: "select * from better_supabase.receive_webhook($1, $2, $3, $4, $5)",
        values: [
          "stripe",
          "msg_1",
          "invoice.paid",
          '{"type":"invoice.paid","amount":10}',
          '{"x-request-id":"r1"}',
        ],
      },
    ]);
  });

  it("answers 200 for a duplicate delivery and stores a null type without one", async () => {
    const fake = fakeSql([["receive_webhook", [{ id: 5, duplicate: true }]]]);
    const inbox = createInbox(fake.sql, { source: "stripe", secrets: secret });
    const response = await inbox.receive(await signed({ type: 7 }));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ id: 5, duplicate: true });
    await inbox.receive(await signed(["not", "an", "object"]));
    await inbox.receive(await signed(null));
    expect(fake.calls.map((call) => call.values[2])).toEqual([
      null,
      null,
      null,
    ]);
    expect(fake.calls[0]!.values[4]).toBe("{}");
  });

  it("rejects a bad signature with a problem and stores nothing", async () => {
    const fake = fakeSql();
    const request = await signed({ type: "x" });
    const forged = new Request(request.url, {
      method: "POST",
      headers: request.headers,
      body: '{"type":"forged"}',
    });
    const response = await createInbox(fake.sql, {
      source: "stripe",
      secrets: secret,
    }).receive(forged);
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      code: "WEBHOOK_INVALID_SIGNATURE",
    });
    expect(fake.calls).toHaveLength(0);
  });

  it("uses a custom verify and typeOf", async () => {
    const fake = fakeSql([["receive_webhook", [{ id: 1, duplicate: false }]]]);
    const verify = vi.fn(async (_request: Request, body: string) =>
      ok({ id: "evt_9", payload: JSON.parse(body) as unknown }),
    );
    const inbox = createInbox(fake.sql, {
      source: "github",
      verify,
      typeOf: () => "push",
    });
    const response = await inbox.receive(
      new Request("https://api.test/hooks", {
        method: "POST",
        body: '{"ref":"main"}',
      }),
    );
    expect(response.status).toBe(202);
    expect(verify.mock.calls[0]![1]).toBe('{"ref":"main"}');
    expect(fake.calls[0]!.values.slice(0, 4)).toEqual([
      "github",
      "evt_9",
      "push",
      '{"ref":"main"}',
    ]);
  });

  it("answers with a problem when storing fails", async () => {
    const fake = fakeSql([
      ["receive_webhook", { throws: pgError("42501", "permission denied") }],
    ]);
    const response = await createInbox(fake.sql, {
      source: "stripe",
      secrets: secret,
    }).receive(await signed({ type: "x" }));
    expect(response.status).toBe(403);
    expect(response.headers.get("content-type")).toBe(
      "application/problem+json",
    );
  });

  it("processes claimed messages, completing successes and failing errors", async () => {
    const row = (id: number, payload: unknown) => ({
      id: String(id),
      source: "stripe",
      message_id: `msg_${id}`,
      event_type: "invoice.paid",
      payload,
      headers: { "x-request-id": "r1" },
      attempts: 1,
      received_at: "2026-09-24T10:00:00Z",
    });
    const fake = fakeSql([
      [
        "claim_webhooks",
        sequence(
          [row(1, { n: 1 }), row(2, { n: 2 })],
          [row(3, { n: 3 }), row(4, { n: 4 })],
        ),
      ],
    ]);
    const seen: unknown[] = [];
    const inbox = createInbox(fake.sql, {
      source: "stripe",
      secrets: secret,
      worker: "w1",
    });
    const result = await inbox.process<{ n: number }>(
      (message) => {
        seen.push(message);
        switch (message.payload.n) {
          case 2:
            throw new Error("handler crashed");
          case 3:
            return { ok: false, error: { message: "already handled" } };
          case 4:
            return { ok: false };
          default:
            return { ok: true };
        }
      },
      { batch: 2, lease: "5 minutes" },
    );
    expect(result).toEqual({ succeeded: 1, failed: 3 });
    expect(seen[0]).toEqual({
      id: 1,
      source: "stripe",
      messageId: "msg_1",
      type: "invoice.paid",
      payload: { n: 1 },
      headers: { "x-request-id": "r1" },
      attempts: 1,
      receivedAt: new Date("2026-09-24T10:00:00Z"),
    });
    expect(
      fake.calls.map((call) => [/\.(\w+)\(/.exec(call.text)![1], call.values]),
    ).toEqual([
      ["claim_webhooks", ["stripe", "w1", 2, "5 minutes"]],
      ["complete_webhook", [1, "w1"]],
      ["fail_webhook", [2, "w1", "handler crashed"]],
      ["claim_webhooks", ["stripe", "w1", 2, "5 minutes"]],
      ["fail_webhook", [3, "w1", "already handled"]],
      ["fail_webhook", [4, "w1", "The handler failed"]],
      ["claim_webhooks", ["stripe", "w1", 2, "5 minutes"]],
    ]);
  });

  it("claims ten messages for 300 seconds with a generated worker id by default", async () => {
    const fake = fakeSql();
    const result = await createInbox(fake.sql, {
      source: "stripe",
      secrets: secret,
    }).process(() => undefined);
    expect(result).toEqual({ succeeded: 0, failed: 0 });
    expect(fake.calls[0]!.values).toEqual([
      "stripe",
      expect.stringMatching(/^worker-[0-9a-f]{8}$/),
      10,
      "300 seconds",
    ]);
  });
});

describe("entitlementMembers", () => {
  const event = (customer: unknown) => ({
    type: ENTITLEMENTS_UPDATED,
    data: { object: { customer } },
  });

  it("names the Stripe event", () => {
    expect(ENTITLEMENTS_UPDATED).toBe(
      "entitlements.active_entitlement_summary.updated",
    );
  });

  it("looks up members of a customer id or customer object", async () => {
    const fake = fakeSql([
      ["entitlement_members", [{ user_id: "u1" }, { user_id: "u2" }]],
    ]);
    expect(
      await entitlementMembers(fake.sql, event("cus_1")).orThrow(),
    ).toEqual(["u1", "u2"]);
    expect(
      await entitlementMembers(fake.sql, event({ id: "cus_2" })).orThrow(),
    ).toEqual(["u1", "u2"]);
    expect(fake.calls).toEqual([
      {
        text: "select user_id from better_supabase.entitlement_members($1) as user_id",
        values: ["cus_1"],
      },
      {
        text: "select user_id from better_supabase.entitlement_members($1) as user_id",
        values: ["cus_2"],
      },
    ]);
  });

  it("returns no members without a query for payloads without a customer", async () => {
    const fake = fakeSql();
    for (const payload of [
      null,
      "evt",
      {},
      { data: {} },
      event(undefined),
      event({ id: 3 }),
    ]) {
      expect(await entitlementMembers(fake.sql, payload).orThrow()).toEqual([]);
    }
    expect(fake.calls).toHaveLength(0);
  });

  it("returns a database error as a result", async () => {
    const fake = fakeSql([
      [
        "entitlement_members",
        { throws: pgError("42883", "function does not exist") },
      ],
    ]);
    const result = await entitlementMembers(fake.sql, event("cus_1"));
    expect(result.ok).toBe(false);
    expect(result.error?.message).toBe("function does not exist");
  });
});
