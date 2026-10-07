import * as v from "valibot";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { DbError } from "../../../src/core/errors.ts";
import type { Executor } from "../../../src/core/executor.ts";

import {
  createIdempotency,
  createInbox,
  createJobs,
  type Job,
  pgmqPublicBackend,
  type QueueBackend,
  type QueueRpcClient,
  sqlQueueBackend,
} from "../../../src/blocks/jobs/index.ts";
import { signWebhook } from "../../../src/blocks/webhooks/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { spansAllTenants } from "../../../src/core/plugin.ts";
import { ok } from "../../../src/core/result.ts";
import { tenant } from "../../../src/plugins/tenant/index.ts";
import { capturingClient } from "../../fixtures/client.ts";
import { fakeSql, pgError, type SqlAnswer } from "../../fixtures/fake-sql.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const echoExecutor: Executor = {
  name: "echo",
  execute: () => Promise.resolve(ok({ rows: [], count: null })),
};

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
    schema: (schema: string) => ({
      rpc: (fn: string, args: Readonly<Record<string, unknown>>) => {
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
  enqueuedAt: Temporal.Instant.fromEpochMilliseconds(0),
  visibleUntil: Temporal.Instant.fromEpochMilliseconds(0),
  lastError: null,
  context: {},
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

  it("archives a message read past its last attempt instead of returning it", async () => {
    const { client, calls } = fakeClient(({ fn }) =>
      fn === "read"
        ? [
            {
              msg_id: 8,
              read_ct: 4,
              enqueued_at: "2026-09-24T10:00:00Z",
              vt: "2026-09-24T10:05:00Z",
              message: { payload: {}, max_attempts: 3 },
            },
          ]
        : true,
    );
    const jobs = createJobs(client, { emails: v.object({}) });
    expect(await jobs.claim("emails").orThrow()).toEqual([]);
    expect(calls.at(-1)).toEqual({
      schema: "pgmq_public",
      fn: "archive",
      args: { queue_name: "emails", message_id: 8 },
    });
    expect((await jobs.replay("emails", 8)).error).toMatchObject({
      kind: "invalid_request",
      message: expect.stringContaining("replay needs a SQL connection"),
    });
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

describe("job context", () => {
  const ACTOR = { id: "u1", kind: "user", impersonator: "admin" } as const;

  function memoryQueue(): { client: QueueRpcClient; sent: unknown[] } {
    const sent: unknown[] = [];
    const { client } = fakeClient(({ fn, args }) => {
      if (fn === "send") {
        sent.push(args["message"]);
        return [sent.length];
      }
      if (fn === "read") {
        return sent.splice(0).map((message, index) => ({
          msg_id: index + 1,
          read_ct: 1,
          enqueued_at: "2026-09-24T10:00:00Z",
          vt: "2026-09-24T10:05:00Z",
          message,
        }));
      }
      return true;
    });
    return { client, sent };
  }

  it("records the actor and tenant next to the payload, and restores them on claim", async () => {
    const { client, sent } = memoryQueue();
    const jobs = createJobs(client, queues);
    await jobs
      .enqueue(
        "emails",
        { to: "a@example.com" },
        { context: { actor: ACTOR, claims: { tenant_id: "o1" } } },
      )
      .orThrow();
    expect(sent).toEqual([
      {
        payload: {
          $bs: 1,
          context: { actor: ACTOR, tenant: "o1" },
          payload: { to: "a@example.com" },
        },
        max_attempts: 5,
      },
    ]);
    const [job] = await jobs.claim("emails").orThrow();
    expect(job?.payload).toEqual({ to: "a@example.com" });
    expect(job?.context).toEqual({ actor: ACTOR, tenant: "o1" });
  });

  it("records a support session's act claim, so the job stays read-only", async () => {
    const { client, sent } = memoryQueue();
    const jobs = createJobs(client, queues);
    const act = {
      kind: "support",
      sub: "admin-1",
      session_id: "s-1",
      read_only: true,
      reason: "ticket 7",
    };
    await jobs
      .enqueue(
        "emails",
        { to: "a@example.com" },
        {
          context: {
            actor: { ...ACTOR, impersonator: "admin-1" },
            claims: { act, email: "a@example.com" },
          },
        },
      )
      .orThrow();
    expect(sent).toMatchObject([
      {
        payload: { $bs: 1, context: { act }, payload: { to: "a@example.com" } },
      },
    ]);
    const [job] = await jobs.claim("emails").orThrow();
    expect(job?.context).toEqual({
      actor: { ...ACTOR, impersonator: "admin-1" },
      claims: { act },
    });
  });

  it("drops a recorded act claim that isn't a support or impersonation level", async () => {
    const { client, sent } = memoryQueue();
    sent.push({
      payload: {
        $bs: 1,
        context: { actor: ACTOR, act: { sub: "client-1" } },
        payload: { to: "a@example.com" },
      },
    });
    const [job] = await createJobs(client, queues).claim("emails").orThrow();
    expect(job?.context).toEqual({ actor: ACTOR });
  });

  it("prefers context.tenant, and stores bare payloads without an actor or tenant", async () => {
    const { client, sent } = memoryQueue();
    const jobs = createJobs(client, queues);
    await jobs
      .enqueue(
        "emails",
        { to: "a@example.com" },
        { context: { tenant: "o2", claims: { tenant_id: "o1" } } },
      )
      .orThrow();
    await jobs
      .enqueue("emails", { to: "b@example.com" }, { context: { claims: {} } })
      .orThrow();
    expect(
      sent.map((message) => (message as { payload: unknown }).payload),
    ).toEqual([
      { $bs: 1, context: { tenant: "o2" }, payload: { to: "a@example.com" } },
      { to: "b@example.com" },
    ]);
  });

  it("records the tenant tenant() resolved from a custom claim path", async () => {
    const { client, sent } = memoryQueue();
    const db = defineSupabase(schema)
      .use(tenant({ claim: "app_metadata.organization" }))
      .connect(echoExecutor, {
        claims: { tenant_id: "o1", app_metadata: { organization: "o9" } },
      });
    await createJobs(client, queues)
      .enqueue("emails", { to: "a@example.com" }, { context: db.$context })
      .orThrow();
    expect(
      sent.map((message) => (message as { payload: unknown }).payload),
    ).toEqual([
      { $bs: 1, context: { tenant: "o9" }, payload: { to: "a@example.com" } },
    ]);
  });

  it("drops a recorded actor or tenant that isn't well formed", async () => {
    const { client, sent } = memoryQueue();
    sent.push({
      payload: {
        $bs: 1,
        context: { actor: { id: 1, kind: "root" }, tenant: "" },
        payload: { to: "a@example.com" },
      },
    });
    const [job] = await createJobs(client, queues).claim("emails").orThrow();
    expect(job).toMatchObject({
      payload: { to: "a@example.com" },
      context: {},
    });
  });

  it("hands the handler the recorded context, marking tenantless jobs only with allTenants", async () => {
    const { client } = memoryQueue();
    const jobs = createJobs(client, queues);
    const context = { actor: ACTOR };
    await jobs
      .enqueue("emails", { to: "a@example.com" }, { context })
      .orThrow();
    await jobs
      .enqueue(
        "emails",
        { to: "b@example.com" },
        { context: { ...context, tenant: "o1" } },
      )
      .orThrow();
    const seen: [string, boolean][] = [];
    const record = (payload: { to: string }, job: Job) => {
      seen.push([payload.to, spansAllTenants(job.context)]);
    };
    await jobs.drain("emails", record, { batch: 2 });
    await jobs
      .enqueue("emails", { to: "a@example.com" }, { context })
      .orThrow();
    await jobs
      .enqueue(
        "emails",
        { to: "b@example.com" },
        { context: { ...context, tenant: "o1" } },
      )
      .orThrow();
    await jobs.drain("emails", record, { batch: 2, allTenants: true });
    expect(seen).toEqual([
      ["a@example.com", false],
      ["b@example.com", false],
      ["a@example.com", true],
      ["b@example.com", false],
    ]);
  });

  it("records the context on schedules", async () => {
    const fake = fakeSql();
    await createJobs(fake.sql, queues)
      .schedule(
        "nightly",
        "0 3 * * *",
        "emails",
        { to: "a@example.com" },
        { context: { tenant: "o1" } },
      )
      .orThrow();
    expect(JSON.parse(String(fake.calls[0]?.values[3]))).toEqual({
      $bs: 1,
      context: { tenant: "o1" },
      payload: { to: "a@example.com" },
    });
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
    vi.useFakeTimers({
      now: Temporal.Instant.from("2026-10-01T12:00:00Z").epochMilliseconds,
    });
    const fake = fakeSql([["enqueue_job", [{ id: 1 }]]]);
    const jobs = createJobs(fake.sql, queues);
    await jobs
      .enqueue(
        "emails",
        { to: "a@example.com" },
        { runAt: Temporal.Instant.from("2026-10-01T12:01:00.200Z") },
      )
      .orThrow();
    await jobs
      .enqueue(
        "emails",
        { to: "a@example.com" },
        { runAt: Temporal.Instant.from("2026-10-01T11:00:00Z") },
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

  it("maps a pg error from the block functions", async () => {
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
        enqueuedAt: Temporal.Instant.from("2026-09-24T10:00:00Z"),
        visibleUntil: Temporal.Instant.from("2026-09-24T10:05:00Z"),
        lastError: "timeout",
        context: {},
      },
      {
        id: 13,
        queue: "emails",
        payload: undefined,
        attempts: 1,
        maxAttempts: 5,
        enqueuedAt: Temporal.Instant.from("2026-09-24T10:00:00Z"),
        visibleUntil: Temporal.Instant.from("2026-09-24T10:05:00Z"),
        lastError: null,
        context: {},
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

  it("replays a dead letter through replay_dead_job", async () => {
    const fake = fakeSql([
      ["replay_dead_job", sequence([{ id: "41" }], [{ id: null }])],
    ]);
    const jobs = createJobs(fake.sql, queues);
    expect(await jobs.replay("emails", 12).orThrow()).toBe(41);
    expect(await jobs.replay("emails", 13).orThrow()).toBeNull();
    expect(fake.calls[0]).toEqual({
      text: "select better_supabase.replay_dead_job($1, $2) as id",
      values: ["emails", 12],
    });
  });

  it("reports a lost lease when the block functions return no row", async () => {
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
        text: "select better_supabase.schedule_job($1, $2, $3, $4, $5, $6, $7)",
        values: [
          "nightly",
          "0 3 * * *",
          "reports",
          '{"day":"SUN"}',
          "UTC",
          expect.stringMatching(/T03:00:00Z$/),
          null,
        ],
      },
      {
        text: "select better_supabase.unschedule_job($1) as done",
        values: ["nightly"],
      },
    ]);
  });
});

describe("schedules with the drain scheduler", () => {
  it("passes the time zone and the next run in that zone", async () => {
    const fake = fakeSql([]);
    await createJobs(fake.sql, queues)
      .schedule(
        "digest",
        "0 9 * * 1-5",
        "reports",
        { day: "mon" },
        {
          timeZone: "Europe/Amsterdam",
        },
      )
      .orThrow();
    const [name, , , , zone, next] = fake.calls[0]!.values;
    expect([name, zone]).toEqual(["digest", "Europe/Amsterdam"]);
    const local = Temporal.Instant.from(String(next)).toZonedDateTimeISO(
      "Europe/Amsterdam",
    );
    expect([local.hour, local.minute]).toEqual([9, 0]);
    expect(local.dayOfWeek).toBeLessThanOrEqual(5);
  });

  it("rejects an invalid cron before calling the database", async () => {
    const fake = fakeSql([]);
    const result = await createJobs(fake.sql, queues).schedule(
      "bad",
      "61 * * * *",
      "reports",
      { day: "mon" },
    );
    expect(result.ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });

  it("enqueues each due schedule once and moves it on", async () => {
    const fake = fakeSql([
      [
        "claim_due_schedules",
        [
          {
            job_name: "digest",
            schedule: "0 * * * *",
            timezone: "UTC",
            queue: "reports",
            payload: { day: "mon" },
            next_run: new Date("2026-01-01T10:00:00Z"),
          },
        ],
      ],
      ["enqueue_job", [{ id: 7 }]],
      ["advance_schedule", [{ advanced: true }]],
    ]);
    expect(await createJobs(fake.sql, queues).runSchedules().orThrow()).toBe(1);
    const [, enqueue, advance] = fake.calls;
    expect(enqueue!.values).toEqual([
      "reports",
      '{"day":"mon"}',
      0,
      5,
      "schedule:digest:2026-01-01T10:00:00Z",
    ]);
    expect(advance!.values[0]).toBe("digest");
    expect(advance!.values[1]).toBe("2026-01-01T10:00:00Z");
    expect(String(advance!.values[2])).toMatch(/:00:00Z$/);
  });

  it("computes the first run of a schedule written in SQL without one", async () => {
    const pending = (
      name: string,
      schedule: string,
      firstAfter: string | null,
    ) => ({
      job_name: name,
      schedule,
      timezone: "UTC",
      queue: "reports",
      payload: { day: "mon" },
      next_run: null,
      first_after: firstAfter,
    });
    const fake = fakeSql([
      [
        "claim_due_schedules",
        [
          pending("past", "0 * * * *", "2026-01-01T10:30:00Z"),
          pending("future", "0 0 1 1 *", null),
          pending("broken", "not a cron", "2026-01-01T10:30:00Z"),
        ],
      ],
      ["enqueue_job", [{ id: 1 }]],
      ["advance_schedule", [{ advanced: true }]],
    ]);
    expect(await createJobs(fake.sql, queues).runSchedules().orThrow()).toBe(1);
    const calls = fake.calls.map((call) => [
      /\.(\w+)\(/.exec(call.text)![1],
      call.values,
    ]);
    expect(calls[1]).toEqual([
      "advance_schedule",
      ["future", expect.stringMatching(/-01-01T00:00:00Z$/)],
    ]);
    expect(fake.calls[1]!.text).toContain("advance_schedule($1, null, $2)");
    expect(calls[2]![1]).toEqual([
      "reports",
      '{"day":"mon"}',
      0,
      5,
      "schedule:past:2026-01-01T11:00:00Z",
    ]);
    expect((calls[3]![1] as unknown[]).slice(0, 2)).toEqual([
      "past",
      "2026-01-01T11:00:00Z",
    ]);
    expect(calls).toHaveLength(4);
  });

  it("counts a schedule another drain advanced as not run", async () => {
    const fake = fakeSql([
      [
        "claim_due_schedules",
        [
          {
            job_name: "tick",
            schedule: "30 seconds",
            timezone: "UTC",
            queue: "reports",
            payload: {},
            next_run: "2026-01-01T10:00:00Z",
          },
        ],
      ],
      ["enqueue_job", [{ id: 1 }]],
      ["advance_schedule", [{ advanced: false }]],
    ]);
    expect(await createJobs(fake.sql, queues).runSchedules().orThrow()).toBe(0);
  });

  it("records the schedule's tenant from the options or the context", async () => {
    const fake = fakeSql([]);
    const jobs = createJobs(fake.sql, queues);
    await jobs
      .schedule("a", "@daily", "reports", { day: "mon" }, { tenant: "t1" })
      .orThrow();
    await jobs
      .schedule(
        "b",
        "@daily",
        "reports",
        { day: "mon" },
        { context: { tenant: "t2" } },
      )
      .orThrow();
    await jobs.schedule("c", "@daily", "reports", { day: "mon" }).orThrow();
    expect(fake.calls.map((call) => call.values[6])).toEqual([
      "t1",
      "t2",
      null,
    ]);
  });

  it("lists and removes a tenant's schedules", async () => {
    const fake = fakeSql([
      [
        "list_schedules",
        [
          {
            job_name: "workflow:1",
            schedule: "0 * * * *",
            timezone: "Europe/Amsterdam",
            queue: "reports",
            tenant: "t1",
            next_run: new Date("2026-01-01T10:00:00Z"),
            last_run: null,
            locked_until: null,
            created_at: "2025-12-01T00:00:00Z",
          },
        ],
      ],
      ["unschedule_tenant", [{ removed: 2 }]],
    ]);
    const jobs = createJobs(fake.sql, queues);
    const [first] = await jobs
      .listSchedules({ prefix: "workflow:", tenant: "t1" })
      .orThrow();
    expect(first).toMatchObject({
      name: "workflow:1",
      timeZone: "Europe/Amsterdam",
      tenant: "t1",
      lastRun: null,
    });
    expect(first!.nextRun?.toString()).toBe("2026-01-01T10:00:00Z");
    expect(fake.calls[0]!.values).toEqual(["workflow:", "t1"]);
    expect(await jobs.listSchedules().orThrow()).toHaveLength(1);
    expect(fake.calls[1]!.values).toEqual([null, null]);
    expect(await jobs.unscheduleAll({ tenant: "t1" }).orThrow()).toBe(2);
    expect(
      await createJobs(fakeSql([]).sql, queues)
        .unscheduleAll({ tenant: "t1" })
        .orThrow(),
    ).toBe(0);
  });

  it("ensures a named set of schedules under a prefix", async () => {
    const listed = (name: string) => ({
      job_name: name,
      schedule: "0 * * * *",
      timezone: "UTC",
      queue: "reports",
      tenant: "t1",
      next_run: null,
      last_run: null,
      locked_until: null,
      created_at: null,
    });
    const fake = fakeSql([
      ["list_schedules", [listed("wf:keep"), listed("wf:stale")]],
      ["unschedule_job", [{ done: true }]],
    ]);
    const jobs = createJobs(fake.sql, queues);
    const result = await jobs
      .ensureSchedules(
        [
          {
            name: "wf:keep",
            cron: "0 * * * *",
            queue: "reports",
            payload: { day: "mon" },
          },
          {
            name: "wf:new",
            cron: "0 9 * * *",
            queue: "emails",
            payload: { to: "a@example.com" },
            timeZone: "Europe/Amsterdam",
            tenant: "t2",
          },
        ],
        { prefix: "wf:", tenant: "t1" },
      )
      .orThrow();
    expect(result).toEqual({
      scheduled: ["wf:keep", "wf:new"],
      removed: ["wf:stale"],
    });
    const calls = fake.calls.map((call) => [
      /\.(\w+)\(/.exec(call.text)![1],
      call.values,
    ]);
    expect(calls[0]).toEqual(["list_schedules", ["wf:", "t1"]]);
    expect(calls[1]![0]).toBe("schedule_job");
    expect(calls[1]![1]).toEqual([
      "wf:keep",
      "0 * * * *",
      "reports",
      '{"day":"MON"}',
      "UTC",
      expect.any(String),
      "t1",
    ]);
    expect((calls[2]![1] as unknown[]).at(-1)).toBe("t2");
    expect(calls[3]).toEqual(["unschedule_job", ["wf:stale"]]);
  });

  it("checks the whole set before ensureSchedules writes anything", async () => {
    const fake = fakeSql([]);
    const jobs = createJobs(fake.sql, queues);
    const ensure = (
      definitions: Parameters<typeof jobs.ensureSchedules>[0],
      prefix = "wf:",
    ) => jobs.ensureSchedules(definitions, { prefix });
    const good = {
      name: "wf:a",
      cron: "@daily",
      queue: "reports",
      payload: { day: "mon" },
    } as const;
    expect(await ensure([good], "")).toMatchObject({
      error: { kind: "invalid_request", message: /non-empty prefix/ },
    });
    expect(await ensure([{ ...good, name: "other" }])).toMatchObject({
      error: { message: 'Schedule "other" does not start with "wf:"' },
    });
    expect(await ensure([good, good])).toMatchObject({
      error: { message: 'Schedule "wf:a" is defined twice' },
    });
    expect(
      await ensure([good, { ...good, name: "wf:b", cron: "61 * * * *" }]),
    ).toMatchObject({ error: { kind: "validation" } });
    expect(
      await ensure([
        good,
        { name: "wf:c", cron: "@daily", queue: "emails", payload: { to: "x" } },
      ]),
    ).toMatchObject({ error: { kind: "validation" } });
    expect(fake.calls).toEqual([]);
    expect(await ensure([])).toEqual({
      ok: true,
      error: null,
      data: { scheduled: [], removed: [] },
    });
    const { client } = fakeClient(() => []);
    expect(
      await createJobs(client, queues).ensureSchedules([good], {
        prefix: "wf:",
      }),
    ).toMatchObject({ error: { kind: "invalid_request" } });
  });

  it("can't list schedules over pgmq_public", async () => {
    const { client } = fakeClient(() => []);
    const jobs = createJobs(client, queues);
    expect(await jobs.listSchedules()).toMatchObject({
      ok: false,
      error: { kind: "invalid_request" },
    });
    expect(await jobs.unscheduleAll({ tenant: "t1" })).toMatchObject({
      ok: false,
    });
  });

  it("runs no schedules over pgmq_public", async () => {
    const { client } = fakeClient(() => []);
    expect(await createJobs(client, queues).runSchedules().orThrow()).toBe(0);
  });
});

describe("drainRoute", () => {
  const request = (init: RequestInit = {}) =>
    new Request("https://app.test/api/jobs/drain", {
      headers: { authorization: "Bearer s3cret" },
      ...init,
    });

  it("needs a secret", () => {
    expect(() =>
      createJobs(fakeSql([]).sql, queues).drainRoute({
        secret: undefined,
        handlers: {},
      }),
    ).toThrow(/secret/);
  });

  it("rejects an unknown queue", () => {
    expect(() =>
      createJobs(fakeSql([]).sql, queues).drainRoute({
        secret: "s3cret",
        // @ts-expect-error not a queue
        handlers: { nope: () => undefined },
      }),
    ).toThrow(/Unknown queue/);
  });

  it("answers 401 without the bearer secret and 405 for other methods", async () => {
    const route = createJobs(fakeSql([]).sql, queues).drainRoute({
      secret: "s3cret",
      handlers: {},
    });
    const denied = await route(request({ headers: {} }));
    expect(denied.status).toBe(401);
    expect((await route(request({ method: "PUT" }))).status).toBe(405);
  });

  it("runs schedules, then drains each queue", async () => {
    const fake = fakeSql([
      ["claim_due_schedules", []],
      ["claim_jobs", sequence([messageRow(1, { day: "mon" })])],
      ["complete_job", [{ done: true }]],
    ]);
    const handled: unknown[] = [];
    const route = createJobs(fake.sql, queues).drainRoute({
      secret: "s3cret",
      handlers: {
        reports: (payload) => {
          handled.push(payload);
        },
      },
    });
    const response = await route(request());
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      schedules: 0,
      queues: { reports: { succeeded: 1, failed: 0 } },
      budgetExhausted: false,
      errors: 0,
    });
    expect(handled).toEqual([{ day: "MON" }]);
  });

  it("reports schedule and queue errors and keeps going", async () => {
    const fake = fakeSql([
      ["claim_due_schedules", { throws: pgError("42883", "no function") }],
      ["claim_jobs", { throws: pgError("42P01", "no table") }],
    ]);
    const errors: DbError[] = [];
    const route = createJobs(fake.sql, queues).drainRoute({
      secret: "s3cret",
      schedules: true,
      handlers: { emails: () => undefined, reports: () => undefined },
      onError: (error) => errors.push(error),
    });
    const body = await (await route(request({ method: "POST" }))).json();
    expect(body).toMatchObject({
      queues: {
        emails: { succeeded: 0, failed: 0 },
        reports: { succeeded: 0, failed: 0 },
      },
    });
    expect(errors).toHaveLength(3);
    expect(body).toMatchObject({ errors: 3 });
  });

  it("calls the monitor around an authorized drain and survives its errors", async () => {
    const fake = fakeSql([["claim_due_schedules", []]]);
    const seen: unknown[] = [];
    const errors: DbError[] = [];
    const route = createJobs(fake.sql, queues).drainRoute({
      secret: "s3cret",
      handlers: {},
      onError: (error) => errors.push(error),
      monitor: {
        onStart: (req) => {
          seen.push(["start", new URL(req.url).pathname]);
          return "check-in-1";
        },
        onFinish: (result, started) => {
          seen.push(["finish", result.errors, started]);
          throw new Error("monitor down");
        },
      },
    });
    expect((await route(request({ headers: {} }))).status).toBe(401);
    expect(seen).toEqual([]);
    expect((await route(request())).status).toBe(200);
    expect(seen).toEqual([
      ["start", "/api/jobs/drain"],
      ["finish", 0, "check-in-1"],
    ]);
    expect(errors.map((error) => error.message)).toEqual(["monitor down"]);
    const quiet = createJobs(fake.sql, queues).drainRoute({
      secret: "s3cret",
      handlers: {},
      monitor: {},
    });
    expect((await quiet(request())).status).toBe(200);
  });

  it("stops claiming once the budget is spent", async () => {
    const fake = fakeSql([["claim_jobs", [messageRow(1, { day: "mon" })]]]);
    const route = createJobs(fake.sql, queues).drainRoute({
      secret: "s3cret",
      budgetMs: 0,
      schedules: false,
      handlers: { reports: () => undefined },
    });
    const body = await (await route(request())).json();
    expect(body).toEqual({
      schedules: 0,
      queues: {},
      budgetExhausted: true,
      errors: 0,
    });
    expect(fake.calls).toEqual([]);
  });
});

describe("queue health", () => {
  it("reads stats per queue, lists dead letters and retries them", async () => {
    const fake = fakeSql([
      [
        "job_queue_stats",
        [
          {
            ready: "2",
            in_flight: 1,
            delayed: "0",
            dead: "3",
            oldest_age_seconds: "12.5",
          },
        ],
      ],
      [
        "list_dead_jobs",
        [
          {
            id: "9",
            attempts: 5,
            enqueued_at: "2026-01-01T00:00:00Z",
            died_at: new Date("2026-01-01T01:00:00Z"),
            message: {
              payload: {
                $bs: 1,
                context: { tenant: "t1" },
                payload: { to: "a@example.com" },
              },
              max_attempts: 5,
              last_error: "boom",
            },
          },
          {
            id: 8,
            attempts: 1,
            enqueued_at: "2026-01-01T00:00:00Z",
            died_at: null,
            message: null,
          },
        ],
      ],
      ["retry_dead_jobs", [{ retried: 2 }]],
    ]);
    const jobs = createJobs(fake.sql, queues);
    expect(await jobs.stats().orThrow()).toEqual({
      emails: {
        ready: 2,
        inFlight: 1,
        delayed: 0,
        dead: 3,
        oldestAgeSeconds: 12.5,
      },
      reports: {
        ready: 2,
        inFlight: 1,
        delayed: 0,
        dead: 3,
        oldestAgeSeconds: 12.5,
      },
    });
    expect(Object.keys(await jobs.stats(["emails"]).orThrow())).toEqual([
      "emails",
    ]);
    const dead = await jobs
      .listDead("emails", { limit: 5, before: 10 })
      .orThrow();
    expect(dead[0]).toMatchObject({
      id: 9,
      queue: "emails",
      payload: { to: "a@example.com" },
      context: { tenant: "t1" },
      maxAttempts: 5,
      lastError: "boom",
    });
    expect(dead[0]!.diedAt?.toString()).toBe("2026-01-01T01:00:00Z");
    expect(dead[1]).toMatchObject({
      id: 8,
      payload: undefined,
      maxAttempts: 5,
      lastError: null,
      diedAt: null,
    });
    await jobs.listDead("emails").orThrow();
    expect(await jobs.retryDead("emails", { ids: [9, 8] }).orThrow()).toBe(2);
    await jobs.retryDead("emails").orThrow();
    const values = fake.calls.map((call) => call.values);
    expect(values.slice(3)).toEqual([
      ["emails", 5, 10],
      ["emails", 100, null],
      ["emails", [9, 8], 1000],
      ["emails", null, 1000],
    ]);
    expect(await jobs.stats(["nope" as "emails"])).toMatchObject({
      ok: false,
    });
  });

  it("answers zeros for a queue with no row and refuses over pgmq_public", async () => {
    const fake = fakeSql([
      [
        "job_queue_stats",
        [
          {
            ready: 0,
            in_flight: 0,
            delayed: 0,
            dead: 0,
            oldest_age_seconds: null,
          },
        ],
      ],
    ]);
    expect(
      (await createJobs(fake.sql, queues).stats(["emails"]).orThrow()).emails,
    ).toEqual({
      ready: 0,
      inFlight: 0,
      delayed: 0,
      dead: 0,
      oldestAgeSeconds: null,
    });
    expect(
      await createJobs(fakeSql([]).sql, queues).retryDead("emails").orThrow(),
    ).toBe(0);
    const { client } = fakeClient(() => []);
    const remote = createJobs(client, queues);
    for (const result of [
      await remote.stats(),
      await remote.listDead("emails"),
      await remote.retryDead("emails"),
    ]) {
      expect(result).toMatchObject({ error: { kind: "invalid_request" } });
    }
  });
});

describe("drain budget", () => {
  it("stops claiming at the deadline", async () => {
    const fake = fakeSql([
      ["claim_jobs", [messageRow(1, { day: "mon" })]],
      ["complete_job", [{ done: true }]],
    ]);
    const result = await createJobs(fake.sql, queues).drain(
      "reports",
      () => undefined,
      { budgetMs: 0 },
    );
    expect(result).toEqual({ succeeded: 0, failed: 0 });
  });
});

describe("custom queue backends", () => {
  it("runs jobs on any QueueBackend", async () => {
    const sent: unknown[] = [];
    const backend: QueueBackend = {
      apiVersion: 1,
      name: "memory",
      leases: false,
      send: (queue, payload) => {
        sent.push([queue, payload]);
        return Promise.resolve(sent.length);
      },
      read: () => Promise.resolve([]),
      complete: () => Promise.resolve(true),
      fail: () => Promise.resolve("queued"),
      extend: () => Promise.resolve(false),
      schedule: () => Promise.resolve(),
      unschedule: () => Promise.resolve(true),
    };
    const jobs = createJobs(backend, queues);
    expect(
      await jobs.enqueue("emails", { to: "a@example.com" }).orThrow(),
    ).toBe(1);
    expect(sent).toEqual([["emails", { to: "a@example.com" }]]);
    expect(await jobs.runSchedules().orThrow()).toBe(0);
  });

  it("exposes the built-in backends", () => {
    expect(sqlQueueBackend(fakeSql([]).sql)).toMatchObject({
      apiVersion: 1,
      name: "sql",
      leases: true,
    });
    expect(pgmqPublicBackend(fakeClient(() => null).client)).toMatchObject({
      apiVersion: 1,
      name: "pgmq_public",
      leases: false,
    });
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

  it("retries a transient claim error with backoff", async () => {
    const fake = fakeSql([
      [
        "claim_jobs",
        sequence(
          { throws: pgError("57014", "canceling statement due to timeout") },
          [messageRow(1, { to: "a@example.com" })],
        ),
      ],
    ]);
    const stop = new AbortController();
    const result = await createJobs(fake.sql, queues).work(
      "emails",
      () => {
        stop.abort();
      },
      { pollInterval: 1, signal: stop.signal },
    );
    expect(result).toEqual({ succeeded: 1, failed: 0 });
  });

  it("gives up after repeated transient claim errors and stops every lane", async () => {
    let claims = 0;
    const fake = fakeSql([
      [
        "claim_jobs",
        () => {
          claims += 1;
          return { throws: pgError("40001", "could not serialize access") };
        },
      ],
    ]);
    const failure = await createJobs(fake.sql, queues)
      .work("emails", () => undefined, { pollInterval: 1, concurrency: 2 })
      .catch((error: unknown) => error);
    expect(failure).toBeInstanceOf(TypeError);
    expect((failure as Error).cause).toMatchObject({ kind: "serialization" });
    expect(claims).toBeLessThanOrEqual(8);
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

  it("doubles the wait after each empty poll up to maxPollInterval", async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const fake = fakeSql();
    const working = createJobs(fake.sql, queues).work(
      "emails",
      () => undefined,
      { signal: controller.signal, pollInterval: 100, maxPollInterval: 300 },
    );
    const claims = () => fake.calls.length;
    await vi.advanceTimersByTimeAsync(100);
    expect(claims()).toBe(2);
    await vi.advanceTimersByTimeAsync(199);
    expect(claims()).toBe(2);
    await vi.advanceTimersByTimeAsync(1);
    expect(claims()).toBe(3);
    await vi.advanceTimersByTimeAsync(300);
    expect(claims()).toBe(4);
    await vi.advanceTimersByTimeAsync(300);
    expect(claims()).toBe(5);
    controller.abort();
    await working;
  });

  it("keeps the leases of jobs waiting in a claimed batch alive", async () => {
    vi.useFakeTimers();
    let finish!: () => void;
    const fake = fakeSql([
      [
        "claim_jobs",
        sequence([
          messageRow(1, { to: "a@example.com" }),
          messageRow(2, { to: "b@example.com" }),
        ]),
      ],
      ["extend_job_lease", [{ extended: true }]],
      ["complete_job", [{ done: true }]],
    ]);
    let calls = 0;
    const draining = createJobs(fake.sql, queues).drain(
      "emails",
      () => {
        calls += 1;
        if (calls > 1) return;
        return new Promise<void>((resolve) => {
          finish = resolve;
        });
      },
      { lease: 4, batch: 2 },
    );
    await vi.advanceTimersByTimeAsync(2000);
    const extended = fake.calls
      .filter((call) => call.text.includes("extend_job_lease"))
      .map((call) => call.values[1]);
    expect(extended).toEqual([1, 2]);
    finish();
    expect(await draining).toEqual({ succeeded: 2, failed: 0 });
    expect(vi.getTimerCount()).toBe(0);
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
  it("calls the block functions with the scope, key and intervals", async () => {
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

  it("scopes keys to the caller's credentials by default", async () => {
    const fake = fakeSql([
      [
        "begin_idempotent",
        () => [{ state: "started", status_code: null, response: null }],
      ],
    ]);
    const idempotency = createIdempotency(fake.sql);
    const send = (headers: Record<string, string>) =>
      idempotency.handle(
        new Request("https://api.test/payments", {
          method: "POST",
          headers: { "idempotency-key": "k1", ...headers },
          body: "{}",
        }),
        () => new Response("ok"),
      );
    await send({ authorization: "Bearer alice" });
    await send({ authorization: "Bearer bob" });
    await send({
      cookie: "theme=dark; sb-ref-auth-token.0=a; sb-ref-auth-token.1=b",
    });
    await send({
      cookie: "sb-ref-auth-token.1=b; theme=light; sb-ref-auth-token.0=a",
    });
    await send({});
    const scopes = fake.calls
      .filter((call) => call.text.includes("begin_idempotent"))
      .map((call) => call.values[0]);
    expect(scopes[0]).toMatch(/^caller:[0-9a-f]{64}$/);
    expect(scopes[1]).not.toBe(scopes[0]);
    expect(scopes[2]).toMatch(/^caller:/);
    expect(scopes[3]).toBe(scopes[2]);
    expect(scopes[4]).toBe("");
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

  it("stores events without secrets or verify, and refuses to receive", async () => {
    const fake = fakeSql([["receive_webhook", [{ id: 3, duplicate: false }]]]);
    const inbox = createInbox(fake.sql, { source: "chat" });
    expect(
      await inbox.store({ id: "e1", payload: { type: "message" } }).orThrow(),
    ).toEqual({ id: 3, duplicate: false });
    await expect(
      inbox.receive(
        new Request("https://api.test/hooks", { method: "POST", body: "{}" }),
      ),
    ).rejects.toThrow(
      'The inbox for "chat" has no `secrets` or `verify`, so it only stores events through `store`',
    );
    expect(fake.calls).toHaveLength(1);
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
        text: "select * from better_supabase.receive_webhook($1, $2, $3, $4, $5, $6, $7)",
        values: [
          "stripe",
          "msg_1",
          "invoice.paid",
          '{"type":"invoice.paid","amount":10}',
          '{"x-request-id":"r1"}',
          null,
          8,
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

  it("stores pre-verified events with a tenant, lists and purges per tenant", async () => {
    const fake = fakeSql([
      ["receive_webhook", [{ id: 9, duplicate: false }]],
      [
        "list_webhooks",
        [
          {
            id: 9,
            source: "chat",
            message_id: "d1",
            event_type: "message",
            payload: {},
            headers: {},
            attempts: 2,
            received_at: new Date("2026-01-01T00:00:00Z"),
            tenant: "t1",
            status: "dead",
            last_error: "boom",
            processed_at: null,
          },
          {
            id: 10,
            source: "chat",
            message_id: "d2",
            event_type: null,
            payload: {},
            headers: {},
            attempts: 1,
            received_at: "2026-01-02T00:00:00Z",
            processed_at: "2026-01-02T00:00:01Z",
          },
        ],
      ],
      ["purge_webhooks", [{ purged: 3 }]],
    ]);
    const inbox = createInbox(fake.sql, {
      source: "chat",
      secrets: secret,
      tenantOf: (payload) =>
        (payload as { account?: string } | null)?.account ?? null,
    });
    expect(
      await inbox
        .store({ id: "d1", payload: { account: "t1", kind: "message" } })
        .orThrow(),
    ).toEqual({ id: 9, duplicate: false });
    expect(fake.calls[0]!.values).toEqual([
      "chat",
      "d1",
      null,
      '{"account":"t1","kind":"message"}',
      "{}",
      "t1",
      8,
    ]);
    await inbox
      .store({ id: "d2", payload: {}, type: "message", tenant: "t2" })
      .orThrow();
    expect(fake.calls[1]!.values[2]).toBe("message");
    expect(fake.calls[1]!.values[5]).toBe("t2");
    const listed = await inbox
      .list({ tenant: "t1", status: "dead", limit: 5 })
      .orThrow();
    expect(fake.calls[2]!.values).toEqual(["t1", "chat", "dead", 5]);
    expect(listed[0]).toMatchObject({
      id: 9,
      maxAttempts: 8,
      status: "dead",
      lastError: "boom",
      tenant: "t1",
      processedAt: null,
    });
    expect(listed[1]).toMatchObject({
      status: "pending",
      tenant: null,
      lastError: null,
    });
    expect(listed[1]!.processedAt?.toString()).toBe("2026-01-02T00:00:01Z");
    await inbox.list({ tenant: "t1" }).orThrow();
    expect(fake.calls[3]!.values).toEqual(["t1", "chat", null, 100]);
    expect(
      await inbox
        .purge({ tenant: "t1", olderThan: 0, includeDead: true })
        .orThrow(),
    ).toBe(3);
    expect(fake.calls[4]!.values).toEqual(["0 seconds", true, 10_000, "t1"]);
    await inbox.purge().orThrow();
    expect(fake.calls[5]!.values).toEqual(["30 days", false, 10_000, null]);
  });

  it("takes the tenant from verify and saves checkpoints while processing", async () => {
    const fake = fakeSql([
      ["receive_webhook", [{ id: 1, duplicate: false }]],
      [
        "claim_webhooks",
        sequence([
          {
            id: 1,
            source: "chat",
            message_id: "d1",
            event_type: null,
            payload: {},
            headers: {},
            attempts: 2,
            received_at: "2026-01-01T00:00:00Z",
            tenant: "t9",
            checkpoint: { cursor: "a" },
          },
        ]),
      ],
      ["checkpoint_webhook", [{ saved: true }]],
    ]);
    const inbox = createInbox(fake.sql, {
      source: "chat",
      verify: () =>
        Promise.resolve(ok({ id: "d1", payload: {}, tenant: "t9" })),
    });
    await inbox.receive(
      new Request("https://api.test/hooks", { method: "POST", body: "{}" }),
    );
    expect(fake.calls[0]!.values[5]).toBe("t9");
    const progress: unknown[] = [];
    await inbox.process(async (message) => {
      progress.push(message.progress, message.tenant);
      expect(await message.checkpoint({ cursor: "b" })).toBe(true);
    });
    expect(progress).toEqual([{ cursor: "a" }, "t9"]);
    const saved = fake.calls.find((call) =>
      call.text.includes("checkpoint_webhook"),
    )!;
    expect(saved.values.slice(2)).toEqual(['{"cursor":"b"}']);
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
      maxAttempts: 8,
      receivedAt: Temporal.Instant.from("2026-09-24T10:00:00Z"),
      tenant: null,
      progress: {},
      checkpoint: expect.any(Function),
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

  it("stores the source's maxAttempts and hands the handler its last attempt", async () => {
    const fake = fakeSql([
      ["receive_webhook", [{ id: 1, duplicate: false }]],
      [
        "claim_webhooks",
        sequence([
          {
            id: 1,
            source: "crm",
            message_id: "m1",
            event_type: null,
            payload: {},
            headers: {},
            attempts: 3,
            max_attempts: 3,
            received_at: "2026-01-01T00:00:00Z",
          },
        ]),
      ],
    ]);
    const inbox = createInbox(fake.sql, { source: "crm", maxAttempts: 3 });
    await inbox.store({ id: "m1", payload: {} }).orThrow();
    expect(fake.calls[0]!.values[6]).toBe(3);
    const last: boolean[] = [];
    await inbox.process((message) => {
      last.push(message.attempts === message.maxAttempts);
    });
    expect(last).toEqual([true]);
    for (const maxAttempts of [0, 1.5]) {
      expect(() =>
        createInbox(fake.sql, { source: "crm", maxAttempts }),
      ).toThrow(/maxAttempts must be a positive integer/);
    }
  });

  it("stops claiming once the budget is spent, finishing claimed messages", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const fake = fakeSql([
      [
        "claim_webhooks",
        [
          {
            id: 1,
            source: "crm",
            message_id: "m1",
            event_type: null,
            payload: {},
            headers: {},
            attempts: 1,
            received_at: "2026-01-01T00:00:00Z",
          },
        ],
      ],
    ]);
    const inbox = createInbox(fake.sql, { source: "crm" });
    const result = await inbox.process(
      () => {
        vi.setSystemTime(Date.now() + 600);
      },
      { budgetMs: 1000 },
    );
    expect(result).toEqual({ succeeded: 2, failed: 0 });
    expect(
      fake.calls.filter((call) => call.text.includes("claim_webhooks")),
    ).toHaveLength(2);
    expect(await inbox.process(() => undefined, { budgetMs: 0 })).toEqual({
      succeeded: 0,
      failed: 0,
    });
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
