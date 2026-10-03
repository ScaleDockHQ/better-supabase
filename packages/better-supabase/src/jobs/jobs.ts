import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { SqlClient } from "../postgres/executor.ts";

import { claimAt, tenantClaimPaths } from "../core/claims.ts";
import {
  type DbError,
  dbError,
  DbException,
  mapDbError,
} from "../core/errors.ts";
import {
  type Actor,
  allTenantsContext,
  type RequestContext,
  tenantOf,
} from "../core/plugin.ts";
import { problemResponse } from "../core/problem.ts";
import {
  AsyncResult,
  err,
  ok,
  type Result,
  toDbError,
} from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { temporal } from "../core/temporal-required.ts";
import { nowInstant } from "../core/temporal.ts";
import { fromPgError } from "../postgres/executor.ts";
import { verifyWebhook } from "../webhooks/index.ts";

function run<T>(fn: () => Promise<T>): AsyncResult<T> {
  return AsyncResult.from(async () => {
    try {
      return ok(await fn());
    } catch (cause) {
      const raw = fromPgError(cause);
      return err(raw ? mapDbError(raw) : toDbError(cause));
    }
  });
}

function seconds(value: number | string): string {
  return typeof value === "number" ? `${String(value)} seconds` : value;
}

function workerId(): string {
  return `worker-${crypto.randomUUID().slice(0, 8)}`;
}

const sleep = (ms: number, signal?: AbortSignal): Promise<void> =>
  new Promise((resolve) => {
    if (signal?.aborted) {
      resolve();
      return;
    }
    const timer = setTimeout(done, ms);
    function done(): void {
      clearTimeout(timer);
      signal?.removeEventListener("abort", done);
      resolve();
    }
    signal?.addEventListener("abort", done, { once: true });
  });

// ---------------------------------------------------------------------------
// Job queue (SQL kit module `jobs`, on Supabase Queues / pgmq)

export type QueueSchemas = Readonly<Record<string, StandardSchemaV1>>;

type PayloadIn<
  Q extends QueueSchemas,
  N extends keyof Q,
> = StandardSchemaV1.InferInput<Q[N]>;
type PayloadOut<
  Q extends QueueSchemas,
  N extends keyof Q,
> = StandardSchemaV1.InferOutput<Q[N]>;

/** The actor and tenant of the request that enqueued a job. */
export interface JobContext {
  readonly actor?: Actor;
  readonly tenant?: string;
}

export interface Job<P = unknown> {
  /** The pgmq message id. */
  readonly id: number;
  readonly queue: string;
  readonly payload: P;
  /** 1 on the first run (pgmq's `read_ct`). */
  readonly attempts: number;
  readonly maxAttempts: number;
  readonly enqueuedAt: Temporal.Instant;
  /** End of the lease: the job becomes claimable again after this. */
  readonly visibleUntil: Temporal.Instant;
  readonly lastError: string | null;
  /**
   * The actor and tenant recorded at enqueue, ready for `db.$with(job.context)`.
   * Without a recorded tenant, `tenant()` applies its `onMissing` unless the
   * worker runs with `allTenants: true`.
   */
  readonly context: RequestContext;
}

export interface EnqueueOptions {
  /** Run no earlier than this. */
  readonly runAt?: Temporal.Instant;
  /** Seconds to wait before running. */
  readonly delay?: number;
  /** Defaults to 5. After this many failed attempts the job is archived as dead. */
  readonly maxAttempts?: number;
  /**
   * While a job with this key is waiting or running, enqueueing again returns
   * its id. SQL connections only.
   */
  readonly dedupeKey?: string;
  /**
   * The request context whose actor and tenant the job records, next to the
   * payload. The tenant is `context.tenant`, the one `tenant()` resolved, or
   * the `tenant_id` claim (then `app_metadata.tenant_id`).
   */
  readonly context?: RequestContext;
}

export interface ScheduleOptions {
  /** The actor and tenant every scheduled run records, as in `enqueue`. */
  readonly context?: RequestContext;
}

export interface ClaimOptions {
  /** Defaults to 1. */
  readonly batch?: number;
  /** Seconds a claimed job stays invisible to other workers. Defaults to 300. */
  readonly lease?: number;
}

export interface FailOptions {
  /** Retry after this many seconds instead of the exponential backoff. SQL connections only. */
  readonly retryIn?: number;
}

export type JobHandler<P> = (
  payload: P,
  job: Job<P>,
  signal: AbortSignal,
) => unknown;

export interface WorkOptions extends ClaimOptions {
  /** Jobs handled at once. Defaults to 1. */
  readonly concurrency?: number;
  /**
   * First wait between polls when the queue is empty, in ms. Defaults to
   * 1000. Each empty poll doubles the wait up to `maxPollInterval`; a claimed
   * job resets it.
   */
  readonly pollInterval?: number;
  /** Longest wait between empty polls, in ms. Defaults to 30000. */
  readonly maxPollInterval?: number;
  /** Stops the loop; running jobs finish first. */
  readonly signal?: AbortSignal;
  readonly onError?: (error: DbError, job: Job) => void;
  /**
   * Run jobs that recorded no tenant with a context that `tenant()` and
   * tenant buckets don't scope. Off by default, so such jobs get the
   * `onMissing` of `tenant()`.
   */
  readonly allTenants?: boolean;
}

export interface DrainResult {
  readonly succeeded: number;
  readonly failed: number;
}

export interface Jobs<Q extends QueueSchemas> {
  /** Validates the payload with the queue's schema, then enqueues it. Returns the job id. */
  enqueue<N extends Extract<keyof Q, string>>(
    queue: N,
    payload: PayloadIn<Q, N>,
    options?: EnqueueOptions,
  ): AsyncResult<number>;
  claim<N extends Extract<keyof Q, string>>(
    queue: N,
    options?: ClaimOptions,
  ): AsyncResult<Job<PayloadOut<Q, N>>[]>;
  /** Archives the job. `false` when the lease was lost (another worker claimed it since). */
  complete(job: Job): AsyncResult<boolean>;
  /** Returns the new state: `queued` (will retry), `dead` (archived), or `null` when the lease was lost. */
  fail(
    job: Job,
    error: unknown,
    options?: FailOptions,
  ): AsyncResult<"queued" | "dead" | null>;
  /** Pushes the lease out by `lease` seconds. `false` when it was lost or the transport can't. */
  extend(job: Job, lease: number): AsyncResult<boolean>;
  /**
   * Enqueues `payload` on a cron schedule with pg_cron (`'0 3 * * *'`,
   * `'30 seconds'`). Re-scheduling a name replaces it. SQL connections only.
   */
  schedule<N extends Extract<keyof Q, string>>(
    name: string,
    cron: string,
    queue: N,
    payload: PayloadIn<Q, N>,
    options?: ScheduleOptions,
  ): AsyncResult<void>;
  unschedule(name: string): AsyncResult<boolean>;
  /** Processes ready jobs until the queue is empty. For cron and edge invocations. */
  drain<N extends Extract<keyof Q, string>>(
    queue: N,
    handler: JobHandler<PayloadOut<Q, N>>,
    options?: Omit<WorkOptions, "pollInterval" | "maxPollInterval" | "signal">,
  ): Promise<DrainResult>;
  /** Polls and processes jobs until `signal` aborts. */
  work<N extends Extract<keyof Q, string>>(
    queue: N,
    handler: JobHandler<PayloadOut<Q, N>>,
    options?: WorkOptions,
  ): Promise<DrainResult>;
}

interface QueueMessage {
  readonly payload?: unknown;
  readonly max_attempts?: number;
  readonly last_error?: string;
}

interface MessageRow {
  readonly id: string | number;
  readonly attempts: number;
  readonly enqueued_at: Date | string;
  readonly visible_until: Date | string;
  readonly message: QueueMessage | null;
}

/** A Supabase client, or anything with `.schema(name).rpc(fn, args)`. */
export interface QueueRpcClient {
  schema(name: string): {
    rpc(
      fn: string,
      args: Readonly<Record<string, unknown>>,
    ): PromiseLike<{ data: unknown; error: unknown }>;
  };
}

interface JobTransport {
  readonly name: "sql" | "postgrest";
  send(
    queue: string,
    payload: unknown,
    delay: number,
    maxAttempts: number,
    dedupeKey: string | undefined,
  ): Promise<number>;
  read(queue: string, lease: number, batch: number): Promise<MessageRow[]>;
  complete(job: Job): Promise<boolean>;
  fail(
    job: Job,
    error: string,
    retryIn: number | undefined,
  ): Promise<"queued" | "dead" | null>;
  extend(job: Job, lease: number): Promise<boolean>;
  schedule(
    name: string,
    cron: string,
    queue: string,
    payload: unknown,
  ): Promise<void>;
  unschedule(name: string): Promise<boolean>;
}

function sqlTransport(sql: SqlClient): JobTransport {
  return {
    name: "sql",
    async send(queue, payload, delay, maxAttempts, dedupeKey) {
      const [row] = await sql.queryRaw<{ id: string | number }>(
        "select better_supabase.enqueue_job($1, $2, $3, $4, $5) as id",
        [
          queue,
          JSON.stringify(payload ?? {}),
          delay,
          maxAttempts,
          dedupeKey ?? null,
        ],
      );
      return Number(row!.id);
    },
    read: (queue, lease, batch) =>
      sql.queryRaw<MessageRow>(
        "select * from better_supabase.claim_jobs($1, $2, $3)",
        [queue, lease, batch],
      ),
    async complete(job) {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.complete_job($1, $2, $3) as done",
        [job.queue, job.id, job.attempts],
      );
      return row?.done ?? false;
    },
    async fail(job, error, retryIn) {
      const [row] = await sql.queryRaw<{ status: "queued" | "dead" | null }>(
        "select better_supabase.fail_job($1, $2, $3, $4, $5) as status",
        [job.queue, job.id, job.attempts, error, retryIn ?? null],
      );
      return row?.status ?? null;
    },
    async extend(job, lease) {
      const [row] = await sql.queryRaw<{ extended: boolean }>(
        "select better_supabase.extend_job_lease($1, $2, $3, $4) as extended",
        [job.queue, job.id, job.attempts, lease],
      );
      return row?.extended ?? false;
    },
    async schedule(name, cron, queue, payload) {
      await sql.queryRaw(
        "select better_supabase.schedule_job($1, $2, $3, $4)",
        [name, cron, queue, JSON.stringify(payload ?? {})],
      );
    },
    async unschedule(name) {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.unschedule_job($1) as done",
        [name],
      );
      return row?.done ?? false;
    },
  };
}

function sqlOnly(feature: string): never {
  throw new DbException(
    dbError(
      "invalid_request",
      `${feature} needs a SQL connection; pgmq_public (PostgREST) does not support it`,
    ),
  );
}

/**
 * Supabase's `pgmq_public` RPCs (Integrations → Queues → "Expose Queues via
 * PostgREST"). No lease check on complete, no retry delay and no
 * deduplication: a failed job simply reappears when its lease ends.
 */
function postgrestTransport(client: QueueRpcClient): JobTransport {
  const call = async <T>(
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): Promise<T> => {
    const { data, error } = await client.schema("pgmq_public").rpc(fn, args);
    if (error) {
      const message =
        typeof error === "object" && "message" in error
          ? String(error.message)
          : String(error);
      throw new Error(`pgmq_public.${fn}: ${message}`, { cause: error });
    }
    // SAFETY: T is the return type the caller declares for this pgmq_public function.
    return data as T;
  };
  const archive = (job: Job): Promise<boolean> =>
    call<boolean>("archive", { queue_name: job.queue, message_id: job.id });
  return {
    name: "postgrest",
    async send(queue, payload, delay, maxAttempts, dedupeKey) {
      if (dedupeKey !== undefined) sqlOnly("dedupeKey");
      const ids = await call<readonly (number | string)[]>("send", {
        queue_name: queue,
        message: { payload: payload ?? {}, max_attempts: maxAttempts },
        sleep_seconds: delay,
      });
      return Number(ids[0]);
    },
    async read(queue, lease, batch) {
      const rows = await call<
        readonly {
          msg_id: number;
          read_ct: number;
          enqueued_at: string;
          vt: string;
          message: QueueMessage | null;
        }[]
      >("read", { queue_name: queue, sleep_seconds: lease, n: batch });
      return rows.map((row) => ({
        id: row.msg_id,
        attempts: row.read_ct,
        enqueued_at: row.enqueued_at,
        visible_until: row.vt,
        message: row.message,
      }));
    },
    complete: archive,
    async fail(job) {
      if (job.attempts < job.maxAttempts) return "queued";
      await archive(job);
      return "dead";
    },
    extend: () => Promise.resolve(false),
    schedule: () => sqlOnly("schedule"),
    unschedule: () => sqlOnly("unschedule"),
  };
}

/** pgmq and the inbox return `timestamptz` as text over RPC and as `Date` from `pg`. */
const toInstant = (value: Date | string): Temporal.Instant =>
  value instanceof Date
    ? temporal().Instant.fromEpochMilliseconds(value.getTime())
    : temporal().Instant.from(value);

/** Marks a payload that carries a job context; pgmq stores it as the payload. */
const ENVELOPE = "$bs";

function withContext(
  payload: unknown,
  context: RequestContext | undefined,
): unknown {
  if (!context) return payload;
  const tenant =
    tenantOf(context) ??
    tenantClaimPaths()
      .map((path) => claimAt(context.claims, path))
      .find((id) => id !== undefined);
  const recorded: JobContext = {
    ...(context.actor ? { actor: context.actor } : {}),
    ...(tenant === undefined ? {} : { tenant }),
  };
  if (!recorded.actor && recorded.tenant === undefined) return payload;
  return { [ENVELOPE]: 1, context: recorded, payload };
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isActor(value: unknown): value is Actor {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    (value["kind"] === "user" ||
      value["kind"] === "service" ||
      value["kind"] === "anon")
  );
}

function unwrap(stored: unknown): {
  payload: unknown;
  context: RequestContext;
} {
  if (
    !isRecord(stored) ||
    stored[ENVELOPE] !== 1 ||
    !Object.hasOwn(stored, "payload")
  ) {
    return { payload: stored, context: {} };
  }
  const recorded = isRecord(stored["context"]) ? stored["context"] : {};
  const { actor, tenant } = recorded;
  return {
    payload: stored["payload"],
    context: {
      ...(isActor(actor) ? { actor } : {}),
      ...(typeof tenant === "string" && tenant.length > 0 ? { tenant } : {}),
    },
  };
}

function toJob(queue: string, row: MessageRow): Job {
  const message = row.message ?? {};
  const { payload, context } = unwrap(message.payload);
  return {
    id: Number(row.id),
    queue,
    payload,
    context,
    attempts: row.attempts,
    maxAttempts: message.max_attempts ?? 5,
    enqueuedAt: toInstant(row.enqueued_at),
    visibleUntil: toInstant(row.visible_until),
    lastError: message.last_error ?? null,
  };
}

function errorText(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error !== null && "message" in error) {
    return String(error.message);
  }
  return String(error);
}

const QUEUE_NAME = /^[a-z_][a-z0-9_]{0,46}$/;

function isSqlClient(source: SqlClient | QueueRpcClient): source is SqlClient {
  // SAFETY: reading queryRaw from either client is safe; only a SqlClient has
  // it as a function.
  return typeof (source as Partial<SqlClient>).queryRaw === "function";
}

/**
 * Typed jobs on Supabase Queues (pgmq), over the `jobs` SQL kit module.
 *
 * Pass a service SQL connection (`postgres.admin`, `ctx.sql`) for the full
 * feature set, or a service-role Supabase client to go through the
 * `pgmq_public` RPCs where no direct connection exists (edge functions).
 * Queue names are lowercase letters, digits and underscores.
 */
export function createJobs<const Q extends QueueSchemas>(
  source: SqlClient | QueueRpcClient,
  queues: Q,
): Jobs<Q> {
  for (const name of Object.keys(queues)) {
    if (!QUEUE_NAME.test(name)) {
      throw new TypeError(
        `Queue "${name}": pgmq queue names are lowercase letters, digits and underscores (at most 47)`,
      );
    }
  }
  const transport = isSqlClient(source)
    ? sqlTransport(source)
    : postgrestTransport(source);

  const schemaOf = (queue: string): StandardSchemaV1 => {
    const schema = queues[queue];
    if (!schema) {
      throw new TypeError(
        `Unknown queue "${queue}". Queues: ${Object.keys(queues).join(", ")}`,
      );
    }
    return schema;
  };

  const complete = (job: Job): AsyncResult<boolean> =>
    run(() => transport.complete(job));
  const fail = (
    job: Job,
    error: unknown,
    failOptions: FailOptions = {},
  ): AsyncResult<"queued" | "dead" | null> =>
    run(() => transport.fail(job, errorText(error), failOptions.retryIn));
  const claim = (
    queue: string,
    claimOptions: ClaimOptions = {},
  ): AsyncResult<Job[]> =>
    run(async () => {
      schemaOf(queue);
      const rows = await transport.read(
        queue,
        claimOptions.lease ?? 300,
        claimOptions.batch ?? 1,
      );
      return rows.map((row) => toJob(queue, row));
    });

  /**
   * Extends the lease of every job in `held` at half the lease, so jobs
   * waiting their turn in a claimed batch don't expire before they run.
   */
  const heartbeat = (
    held: ReadonlySet<Job>,
    lease: number,
  ): ReturnType<typeof setInterval> | undefined =>
    transport.name === "sql"
      ? setInterval(
          () => {
            for (const job of held)
              void run(() => transport.extend(job, lease));
          },
          Math.max(1000, (lease * 1000) / 2),
        )
      : undefined;

  const handle = async (
    job: Job,
    handler: JobHandler<unknown>,
    workOptions: WorkOptions,
  ): Promise<boolean> => {
    const controller = new AbortController();
    try {
      const payload = await validate(
        schemaOf(job.queue),
        job.payload,
        "payload",
      );
      if (!payload.ok) {
        await fail(job, payload.error.message);
        workOptions.onError?.(payload.error, job);
        return false;
      }
      const context =
        workOptions.allTenants && job.context.tenant === undefined
          ? allTenantsContext(job.context)
          : job.context;
      const outcome: unknown = await handler(
        payload.data,
        { ...job, payload: payload.data, context },
        controller.signal,
      );
      if (
        typeof outcome === "object" &&
        outcome !== null &&
        "ok" in outcome &&
        outcome.ok === false &&
        "error" in outcome
      ) {
        // SAFETY: the in check above proves outcome has an error field.
        throw (outcome as { error: unknown }).error;
      }
      await complete(job);
      return true;
    } catch (cause) {
      controller.abort();
      await fail(job, cause);
      // SAFETY: repositories only reject with DbError objects, which carry a kind field.
      workOptions.onError?.(
        typeof cause === "object" && cause !== null && "kind" in cause
          ? (cause as DbError)
          : toDbError(cause),
        job,
      );
      return false;
    }
  };

  const loop = async (
    queue: string,
    handler: JobHandler<unknown>,
    workOptions: WorkOptions,
    forever: boolean,
  ): Promise<DrainResult> => {
    const concurrency = Math.max(1, workOptions.concurrency ?? 1);
    const lease = workOptions.lease ?? 300;
    const firstWait = workOptions.pollInterval ?? 1000;
    const maxWait = Math.max(firstWait, workOptions.maxPollInterval ?? 30_000);
    let succeeded = 0;
    let failed = 0;
    const lanes = Array.from({ length: concurrency }, async () => {
      let wait = firstWait;
      while (!workOptions.signal?.aborted) {
        const claimed = await claim(queue, {
          ...workOptions,
          batch: workOptions.batch ?? 1,
        });
        if (!claimed.ok)
          throw new TypeError(claimed.error.message, { cause: claimed.error });
        if (claimed.data.length === 0) {
          if (!forever) return;
          await sleep(wait, workOptions.signal);
          wait = Math.min(maxWait, wait * 2);
          continue;
        }
        wait = firstWait;
        const held = new Set(claimed.data);
        const timer = heartbeat(held, lease);
        try {
          for (const job of claimed.data) {
            if (await handle(job, handler, workOptions)) succeeded += 1;
            else failed += 1;
            held.delete(job);
          }
        } finally {
          clearInterval(timer);
        }
      }
    });
    await Promise.all(lanes);
    return { succeeded, failed };
  };

  return {
    enqueue(queue, payload, enqueueOptions = {}) {
      return AsyncResult.from(async () => {
        const valid = await validate(schemaOf(queue), payload, "payload");
        if (!valid.ok) return valid;
        const delay =
          enqueueOptions.delay ??
          (enqueueOptions.runAt
            ? Math.max(
                0,
                Math.ceil(
                  (enqueueOptions.runAt.epochMilliseconds -
                    nowInstant().epochMilliseconds) /
                    1000,
                ),
              )
            : 0);
        return run(() =>
          transport.send(
            queue,
            withContext(valid.data, enqueueOptions.context),
            delay,
            enqueueOptions.maxAttempts ?? 5,
            enqueueOptions.dedupeKey,
          ),
        );
      });
    },
    claim: claim,
    complete,
    fail,
    extend: (job, lease) => run(() => transport.extend(job, lease)),
    schedule(name, cron, queue, payload, scheduleOptions = {}) {
      return AsyncResult.from(async () => {
        const valid = await validate(schemaOf(queue), payload, "payload");
        if (!valid.ok) return valid;
        const stored = withContext(valid.data, scheduleOptions.context);
        return run(() => transport.schedule(name, cron, queue, stored));
      });
    },
    unschedule: (name) => run(() => transport.unschedule(name)),
    drain: (queue, handler, drainOptions = {}) =>
      loop(queue, handler, drainOptions, false),
    work: (queue, handler, workOptions = {}) =>
      loop(queue, handler, workOptions, true),
  };
}

// ---------------------------------------------------------------------------
// Idempotency keys (SQL kit module `idempotency`)

export interface IdempotencyOptions {
  /** Separates keys of different endpoints or tenants. Defaults to `''`. */
  readonly scope?: string | ((request: Request) => string);
  /** How long a completed response is replayed. Defaults to `24 hours`. */
  readonly ttl?: number | string;
  /** How long a running request holds the key. Defaults to `1 minute`. */
  readonly lock?: number | string;
  /** Answer 400 when the header is missing. Defaults to false (run without a key). */
  readonly required?: boolean;
  /** Defaults to `Idempotency-Key`. */
  readonly header?: string;
}

export type IdempotencyState = "started" | "replay" | "running" | "mismatch";

export interface Idempotency {
  /**
   * Runs `handler` at most once per key: retries with the same key and body
   * get the stored response (with `Idempotency-Replayed: true`).
   */
  handle(
    request: Request,
    handler: (request: Request) => Promise<Response> | Response,
  ): Promise<Response>;
  /** The lower-level protocol, for non-HTTP callers. */
  begin(
    key: string,
    fingerprint: string,
    scope?: string,
  ): AsyncResult<{
    state: IdempotencyState;
    status: number | null;
    body: unknown;
  }>;
  complete(
    key: string,
    status: number,
    body: unknown,
    scope?: string,
  ): AsyncResult<void>;
  release(key: string, scope?: string): AsyncResult<void>;
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

interface StoredResponse {
  readonly body: string;
  readonly contentType: string | null;
}

/** HTTP idempotency keys (IETF `Idempotency-Key` header) over the `idempotency` SQL kit module. */
export function createIdempotency(
  sql: SqlClient,
  options: IdempotencyOptions = {},
): Idempotency {
  const headerName = options.header ?? "idempotency-key";
  const ttl = seconds(options.ttl ?? "24 hours");
  const lock = seconds(options.lock ?? "1 minute");

  const begin: Idempotency["begin"] = (key, fingerprint, scope = "") =>
    run(async () => {
      const [row] = await sql.queryRaw<{
        state: IdempotencyState;
        status_code: number | null;
        response: unknown;
      }>(
        "select * from better_supabase.begin_idempotent($1, $2, $3, $4::interval, $5::interval)",
        [scope, key, fingerprint, ttl, lock],
      );
      return {
        state: row!.state,
        status: row!.status_code,
        body: row!.response,
      };
    });
  const complete: Idempotency["complete"] = (key, status, body, scope = "") =>
    run(async () => {
      await sql.queryRaw(
        "select better_supabase.complete_idempotent($1, $2, $3, $4)",
        [scope, key, status, JSON.stringify(body)],
      );
    });
  const release: Idempotency["release"] = (key, scope = "") =>
    run(async () => {
      await sql.queryRaw("select better_supabase.release_idempotent($1, $2)", [
        scope,
        key,
      ]);
    });

  return {
    begin,
    complete,
    release,
    async handle(request, handler) {
      const key = request.headers.get(headerName);
      const instance = new URL(request.url).pathname;
      if (!key) {
        return options.required
          ? problemResponse(
              dbError(
                "invalid_request",
                `The ${headerName} header is required`,
                {
                  code: "IDEMPOTENCY_KEY_MISSING",
                },
              ),
              { instance },
            )
          : handler(request);
      }
      if (key.length > 255) {
        return problemResponse(
          dbError("invalid_request", `The ${headerName} header is too long`, {
            code: "IDEMPOTENCY_KEY_INVALID",
          }),
          { instance },
        );
      }
      const scope =
        typeof options.scope === "function"
          ? options.scope(request)
          : (options.scope ?? "");
      const body = await request.clone().text();
      const fingerprint = await sha256(
        `${request.method} ${instance}\n${body}`,
      );
      const started = await begin(key, fingerprint, scope);
      if (!started.ok) return problemResponse(started.error, { instance });
      const { state } = started.data;
      switch (state) {
        case "replay": {
          // SAFETY: the replay state is only written with the stored response
          // of the first request.
          const stored = started.data.body as StoredResponse;
          return new Response(stored.body, {
            status: started.data.status ?? 200,
            headers: {
              ...(stored.contentType
                ? { "content-type": stored.contentType }
                : {}),
              "idempotency-replayed": "true",
            },
          });
        }
        case "running":
          return problemResponse(
            dbError(
              "conflict",
              "A request with this idempotency key is still running",
              {
                code: "IDEMPOTENCY_KEY_IN_USE",
              },
            ),
            { instance, headers: { "retry-after": "1" } },
          );
        case "mismatch":
          return problemResponse(
            dbError(
              "validation",
              "This idempotency key was used for a different request",
              {
                code: "IDEMPOTENCY_KEY_REUSED",
                issues: [
                  {
                    message: "Use a new key for a new request",
                    path: [headerName],
                  },
                ],
              },
            ),
            { instance },
          );
        case "started":
          break;
        default: {
          const unknown: never = state;
          throw new TypeError(`Unknown idempotency state ${String(unknown)}`);
        }
      }
      let response: Response;
      try {
        response = await handler(request);
      } catch (cause) {
        await release(key, scope);
        throw cause;
      }
      if (response.status >= 500) {
        await release(key, scope);
        return response;
      }
      const stored: StoredResponse = {
        body: await response.clone().text(),
        contentType: response.headers.get("content-type"),
      };
      await complete(key, response.status, stored, scope);
      return response;
    },
  };
}

// ---------------------------------------------------------------------------
// Webhook inbox (SQL kit module `webhook-inbox`)

export interface InboxMessage<T = unknown> {
  readonly id: number;
  readonly source: string;
  readonly messageId: string;
  readonly type: string | null;
  readonly payload: T;
  readonly headers: Readonly<Record<string, string>>;
  readonly attempts: number;
  readonly receivedAt: Temporal.Instant;
}

export interface InboxOptions {
  /** Name of the sender, e.g. `stripe` or `supabase-auth`. */
  readonly source: string;
  /** Standard Webhooks secrets; the signature is verified before storing. */
  readonly secrets?: string | readonly string[];
  /** Custom verification for senders that don't use Standard Webhooks. */
  readonly verify?: (
    request: Request,
    body: string,
  ) => Promise<Result<{ id: string; payload: unknown }>>;
  /** Event type from the payload. Defaults to `payload.type`. */
  readonly typeOf?: (payload: unknown) => string | null;
  /** Headers kept with the message. Defaults to none. */
  readonly keepHeaders?: readonly string[];
  readonly worker?: string;
}

export interface Inbox {
  /** Verifies and stores a webhook; answers 202, or 200 for a duplicate delivery. */
  receive(request: Request): Promise<Response>;
  /** Processes stored messages until none are ready. */
  process<T = unknown>(
    handler: (message: InboxMessage<T>) => unknown,
    options?: { readonly batch?: number; readonly lease?: number | string },
  ): Promise<DrainResult>;
}

interface InboxRow {
  id: string | number;
  source: string;
  message_id: string;
  event_type: string | null;
  payload: unknown;
  headers: Record<string, string>;
  attempts: number;
  received_at: Date | string;
}

function defaultType(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null) return null;
  // SAFETY: payload is a non-null object here, and type is checked below.
  const type = (payload as { type?: unknown }).type;
  return typeof type === "string" ? type : null;
}

/** Store-then-process webhooks: acknowledge fast, process with retries, never twice. */
export function createInbox(sql: SqlClient, options: InboxOptions): Inbox {
  const worker = options.worker ?? workerId();
  if (!options.secrets && !options.verify) {
    throw new TypeError(
      "createInbox needs `secrets` (Standard Webhooks) or `verify`",
    );
  }

  const verified = async (
    request: Request,
  ): Promise<Result<{ id: string; payload: unknown }>> => {
    if (options.verify)
      return options.verify(request, await request.clone().text());
    const result = await verifyWebhook(request, options.secrets!);
    return result.ok
      ? ok({ id: result.data.id, payload: result.data.payload })
      : result;
  };

  return {
    async receive(request) {
      const instance = new URL(request.url).pathname;
      if (request.method !== "POST") {
        return new Response(null, { status: 405, headers: { allow: "POST" } });
      }
      const message = await verified(request);
      if (!message.ok) return problemResponse(message.error, { instance });
      const headers = Object.fromEntries(
        (options.keepHeaders ?? []).flatMap((name) => {
          const value = request.headers.get(name);
          return value === null ? [] : [[name.toLowerCase(), value]];
        }),
      );
      const stored = await run(() =>
        sql.queryRaw<{ id: string | number; duplicate: boolean }>(
          "select * from better_supabase.receive_webhook($1, $2, $3, $4, $5)",
          [
            options.source,
            message.data.id,
            (options.typeOf ?? defaultType)(message.data.payload),
            JSON.stringify(message.data.payload),
            JSON.stringify(headers),
          ],
        ),
      );
      if (!stored.ok) return problemResponse(stored.error, { instance });
      const row = stored.data[0]!;
      return Response.json(
        { id: Number(row.id), duplicate: row.duplicate },
        { status: row.duplicate ? 200 : 202 },
      );
    },

    async process(handler, processOptions = {}) {
      let succeeded = 0;
      let failed = 0;
      for (;;) {
        const rows = await sql.queryRaw<InboxRow>(
          "select * from better_supabase.claim_webhooks($1, $2, $3, $4::interval)",
          [
            options.source,
            worker,
            processOptions.batch ?? 10,
            seconds(processOptions.lease ?? 300),
          ],
        );
        if (rows.length === 0) return { succeeded, failed };
        for (const row of rows) {
          // SAFETY: the handler's payload type comes from its event type, and
          // the inbox stores the payload as JSON.
          const message = {
            id: Number(row.id),
            source: row.source,
            messageId: row.message_id,
            type: row.event_type,
            payload: row.payload as never,
            headers: row.headers,
            attempts: row.attempts,
            receivedAt: toInstant(row.received_at),
          };
          try {
            const outcome: unknown = await handler(message);
            if (
              typeof outcome === "object" &&
              outcome !== null &&
              "ok" in outcome &&
              outcome.ok === false
            ) {
              // SAFETY: the check above proves outcome is a failed Result,
              // which has an error field.
              throw new Error(
                errorText(
                  (outcome as { error?: unknown }).error ??
                    "The handler failed",
                ),
              );
            }
            await sql.queryRaw(
              "select better_supabase.complete_webhook($1, $2)",
              [message.id, worker],
            );
            succeeded += 1;
          } catch (cause) {
            await sql.queryRaw(
              "select better_supabase.fail_webhook($1, $2, $3)",
              [message.id, worker, errorText(cause)],
            );
            failed += 1;
          }
        }
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Stripe entitlements (SQL kit module `entitlements`)

/** The Stripe event sent when a customer's active entitlements change. */
export const ENTITLEMENTS_UPDATED =
  "entitlements.active_entitlement_summary.updated";

function stripeCustomerOf(payload: unknown): string | undefined {
  if (typeof payload !== "object" || payload === null) return undefined;
  // SAFETY: payload is a non-null object, and every nested field is optional and checked.
  const object = (payload as { data?: { object?: { customer?: unknown } } })
    .data?.object;
  const customer = object?.customer;
  if (typeof customer === "string") return customer;
  // SAFETY: a Stripe customer is an id string or an object with an id; the
  // string case returned above.
  const id = (customer as { id?: unknown } | undefined)?.id;
  return typeof id === "string" ? id : undefined;
}

/**
 * Users whose `memberships` claim carries the entitlements of the Stripe
 * customer in an `entitlements.active_entitlement_summary.updated` event, so
 * a job can invalidate their sessions. Empty for other payloads.
 */
export function entitlementMembers(
  sql: SqlClient,
  payload: unknown,
): AsyncResult<readonly string[]> {
  const customer = stripeCustomerOf(payload);
  if (customer === undefined) return AsyncResult.ok([]);
  return run(() =>
    sql.queryRaw<{ user_id: string }>(
      "select user_id from better_supabase.entitlement_members($1) as user_id",
      [customer],
    ),
  ).map((rows) => rows.map((row) => row.user_id));
}
