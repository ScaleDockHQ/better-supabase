import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { SqlClient } from "../postgres/executor.ts";

import { claimAt, tenantClaimPaths } from "../core/claims.ts";
import { type DbError, dbError, DbException } from "../core/errors.ts";
import {
  type Actor,
  allTenantsContext,
  type RequestContext,
  tenantOf,
} from "../core/plugin.ts";
import { problemResponse } from "../core/problem.ts";
import { AsyncResult, toDbError } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { temporal } from "../core/temporal-required.ts";
import { nowInstant } from "../core/temporal.ts";
import { verifySharedSecret } from "../webhooks/verify.ts";
import { nextCronRun } from "./cron.ts";
import { errorText, run, sleep, toInstant } from "./shared.ts";

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
  /**
   * The IANA time zone the cron fields are read in. Defaults to `UTC`.
   * Other zones need `kits.jobs.options.scheduler: "drain"`.
   */
  readonly timeZone?: string;
}

export interface RunSchedulesOptions {
  /** Seconds a claimed schedule stays leased. Defaults to 60. */
  readonly lease?: number;
  /** Defaults to 100. */
  readonly batch?: number;
}

export interface DrainOptions extends Omit<
  WorkOptions,
  "pollInterval" | "maxPollInterval" | "signal"
> {
  /** Stop claiming after this many ms; claimed jobs still finish. */
  readonly budgetMs?: number;
}

export interface DrainRouteOptions<Q extends QueueSchemas> extends Omit<
  DrainOptions,
  "onError"
> {
  /**
   * The bearer token callers send (`Authorization: Bearer <secret>`), such
   * as Vercel's `CRON_SECRET`. Required.
   */
  readonly secret: string | undefined;
  /** The queues to drain, in order, with their handlers. */
  readonly handlers: {
    readonly [N in Extract<keyof Q, string>]?: JobHandler<PayloadOut<Q, N>>;
  };
  /** Total time in ms for schedules and queues. Defaults to 50000. */
  readonly budgetMs?: number;
  /** Enqueue due schedules first (the drain scheduler). Defaults to true. */
  readonly schedules?: boolean;
  readonly onError?: (error: DbError, job?: Job) => void;
}

export interface DrainRouteResult {
  /** Schedules whose run was enqueued. */
  readonly schedules: number;
  readonly queues: Readonly<Record<string, DrainResult>>;
  /** True when the budget ran out before every queue was empty. */
  readonly budgetExhausted: boolean;
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
   * Enqueues a dead letter again with its payload and attempts, and removes
   * it from the archive. Returns the new id, or `null` when `id` is not a
   * dead letter of `queue`. SQL connections only.
   */
  replay(
    queue: Extract<keyof Q, string>,
    id: number,
  ): AsyncResult<number | null>;
  /**
   * Enqueues `payload` on a cron schedule (`'0 3 * * *'`, `'@daily'`,
   * `'30 seconds'`), with pg_cron or the drain scheduler
   * (`kits.jobs.options.scheduler`). Re-scheduling a name replaces it. SQL
   * connections only.
   */
  schedule<N extends Extract<keyof Q, string>>(
    name: string,
    cron: string,
    queue: N,
    payload: PayloadIn<Q, N>,
    options?: ScheduleOptions,
  ): AsyncResult<void>;
  unschedule(name: string): AsyncResult<boolean>;
  /**
   * Enqueues one run of every due schedule (the drain scheduler) and moves
   * it to its next time. Returns how many ran. Missed runs collapse into one.
   */
  runSchedules(options?: RunSchedulesOptions): AsyncResult<number>;
  /** Processes ready jobs until the queue is empty or the budget is spent. For cron and edge invocations. */
  drain<N extends Extract<keyof Q, string>>(
    queue: N,
    handler: JobHandler<PayloadOut<Q, N>>,
    options?: DrainOptions,
  ): Promise<DrainResult>;
  /**
   * A route handler for a cron caller such as Vercel Cron: checks the bearer
   * secret, runs due schedules, then drains each queue in `handlers` within
   * the budget, and answers with a `DrainRouteResult`.
   */
  drainRoute(
    options: DrainRouteOptions<Q>,
  ): (request: Request) => Promise<Response>;
  /** Polls and processes jobs until `signal` aborts. */
  work<N extends Extract<keyof Q, string>>(
    queue: N,
    handler: JobHandler<PayloadOut<Q, N>>,
    options?: WorkOptions,
  ): Promise<DrainResult>;
}

/** The body of a queued message, on pgmq and the table backend alike. */
export interface QueueMessageBody {
  readonly payload?: unknown;
  readonly max_attempts?: number;
  readonly last_error?: string;
}

/** A claimed message, as `better_supabase.claim_jobs` returns it. */
export interface QueueMessageRow {
  readonly id: string | number;
  /** 1 on the first claim; a lease token for complete, fail and extend. */
  readonly attempts: number;
  readonly enqueued_at: Date | string;
  readonly visible_until: Date | string;
  readonly message: QueueMessageBody | null;
}

/** A schedule whose run is due, claimed by `runSchedules`. */
export interface DueSchedule {
  readonly name: string;
  readonly cron: string;
  readonly timeZone: string;
  readonly queue: string;
  /** The payload as stored, with its recorded context. */
  readonly payload: unknown;
  readonly nextRun: Temporal.Instant;
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

/**
 * Where `createJobs` stores jobs. `sqlQueueBackend` (the `jobs` SQL kit
 * module, on pgmq or its table backend) and `pgmqPublicBackend` ship with
 * the package; `testQueueBackend` from `better-supabase/testing` checks
 * another one.
 */
export interface QueueBackend {
  readonly apiVersion: 1;
  readonly name: string;
  /** Whether `extend` works, so long-running batches keep their lease. */
  readonly leases: boolean;
  send(
    queue: string,
    payload: unknown,
    delay: number,
    maxAttempts: number,
    dedupeKey: string | undefined,
  ): Promise<number>;
  read(
    queue: string,
    lease: number,
    batch: number,
  ): Promise<readonly QueueMessageRow[]>;
  /** `false` when the lease was lost. */
  complete(job: Job): Promise<boolean>;
  fail(
    job: Job,
    error: string,
    retryIn: number | undefined,
  ): Promise<"queued" | "dead" | null>;
  extend(job: Job, lease: number): Promise<boolean>;
  /** Re-enqueues a dead letter; `null` when it isn't one. Absent when the backend can't. */
  replay?(queue: string, id: number): Promise<number | null>;
  schedule(
    name: string,
    cron: string,
    queue: string,
    payload: unknown,
    timeZone: string,
    nextRun: Temporal.Instant,
  ): Promise<void>;
  unschedule(name: string): Promise<boolean>;
  /** Leases due schedules (the drain scheduler); absent or empty with pg_cron. */
  dueSchedules?(lease: number, batch: number): Promise<readonly DueSchedule[]>;
  /** Moves a schedule from `ran` to `next`; `false` when it changed since the claim. */
  advanceSchedule?(
    name: string,
    ran: Temporal.Instant,
    next: Temporal.Instant,
  ): Promise<boolean>;
}

interface ScheduleRow {
  readonly job_name: string;
  readonly schedule: string;
  readonly timezone: string;
  readonly queue: string;
  readonly payload: unknown;
  readonly next_run: Date | string;
}

/**
 * The `jobs` SQL kit module over a service SQL connection. The same
 * functions back both `kits.jobs.options.backend` values (pgmq and table)
 * and both schedulers.
 */
export function sqlQueueBackend(sql: SqlClient): QueueBackend {
  return {
    apiVersion: 1,
    name: "sql",
    leases: true,
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
      sql.queryRaw<QueueMessageRow>(
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
    async replay(queue, id) {
      const [row] = await sql.queryRaw<{ id: string | number | null }>(
        "select better_supabase.replay_dead_job($1, $2) as id",
        [queue, id],
      );
      return row?.id === null || row?.id === undefined ? null : Number(row.id);
    },
    async schedule(name, cron, queue, payload, timeZone, nextRun) {
      await sql.queryRaw(
        "select better_supabase.schedule_job($1, $2, $3, $4, $5, $6)",
        [
          name,
          cron,
          queue,
          JSON.stringify(payload ?? {}),
          timeZone,
          nextRun.toString(),
        ],
      );
    },
    async unschedule(name) {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.unschedule_job($1) as done",
        [name],
      );
      return row?.done ?? false;
    },
    async dueSchedules(lease, batch) {
      const rows = await sql.queryRaw<ScheduleRow>(
        "select * from better_supabase.claim_due_schedules($1, $2)",
        [lease, batch],
      );
      return rows.map((row) => ({
        name: row.job_name,
        cron: row.schedule,
        timeZone: row.timezone,
        queue: row.queue,
        payload: row.payload,
        nextRun: toInstant(row.next_run),
      }));
    },
    async advanceSchedule(name, ran, next) {
      const [row] = await sql.queryRaw<{ advanced: boolean }>(
        "select better_supabase.advance_schedule($1, $2, $3) as advanced",
        [name, ran.toString(), next.toString()],
      );
      return row?.advanced ?? false;
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
 * Supabase's `pgmq_public` RPCs (Integrations, Queues, "Expose Queues via
 * PostgREST"). No lease check on complete, no retry delay, no deduplication
 * and no schedules: a failed job reappears when its lease ends.
 */
export function pgmqPublicBackend(client: QueueRpcClient): QueueBackend {
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
    apiVersion: 1,
    name: "pgmq_public",
    leases: false,
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
          message: QueueMessageBody | null;
        }[]
      >("read", { queue_name: queue, sleep_seconds: lease, n: batch });
      const live = [];
      for (const row of rows) {
        // A message read past max_attempts lost its worker on the last attempt.
        if (row.read_ct > (row.message?.max_attempts ?? 5)) {
          await call<boolean>("archive", {
            queue_name: queue,
            message_id: row.msg_id,
          });
        } else live.push(row);
      }
      return live.map((row) => ({
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

/** Marks a payload that carries a job context; pgmq stores it as the payload. */
const ENVELOPE = "$bs";

/** Schedule times are stored to the millisecond, the precision `Date` reads back. */
const millis = (instant: Temporal.Instant): Temporal.Instant =>
  instant.round({ smallestUnit: "millisecond", roundingMode: "floor" });

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

function toJob(queue: string, row: QueueMessageRow): Job {
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

const QUEUE_NAME = /^[a-z_][a-z0-9_]{0,46}$/;

function isBackend(
  source: SqlClient | QueueRpcClient | QueueBackend,
): source is QueueBackend {
  return "apiVersion" in source;
}

function isSqlClient(source: SqlClient | QueueRpcClient): source is SqlClient {
  // SAFETY: reading queryRaw from either client is safe; only a SqlClient has
  // it as a function.
  return typeof (source as Partial<SqlClient>).queryRaw === "function";
}

function backendOf(
  source: SqlClient | QueueRpcClient | QueueBackend,
): QueueBackend {
  if (isBackend(source)) {
    return source;
  }
  return isSqlClient(source)
    ? sqlQueueBackend(source)
    : pgmqPublicBackend(source);
}

const later = (a: Temporal.Instant, b: Temporal.Instant): Temporal.Instant =>
  temporal().Instant.compare(a, b) >= 0 ? a : b;

/**
 * Typed jobs on Supabase Queues (pgmq), over the `jobs` SQL kit module.
 *
 * Pass a service SQL connection (`postgres.admin`, `ctx.sql`) for the full
 * feature set, a service-role Supabase client to go through the
 * `pgmq_public` RPCs where no direct connection exists (edge functions), or
 * any `QueueBackend`. Queue names are lowercase letters, digits and
 * underscores.
 */
export function createJobs<const Q extends QueueSchemas>(
  source: SqlClient | QueueRpcClient | QueueBackend,
  queues: Q,
): Jobs<Q> {
  for (const name of Object.keys(queues)) {
    if (!QUEUE_NAME.test(name)) {
      throw new TypeError(
        `Queue "${name}": pgmq queue names are lowercase letters, digits and underscores (at most 47)`,
      );
    }
  }
  const transport = backendOf(source);

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
    transport.leases
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
    deadline?: number,
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
        if (deadline !== undefined && Date.now() >= deadline) return;
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

  const runSchedules = async (
    scheduleOptions: RunSchedulesOptions,
  ): Promise<number> => {
    if (!transport.dueSchedules || !transport.advanceSchedule) return 0;
    const due = await transport.dueSchedules(
      scheduleOptions.lease ?? 60,
      scheduleOptions.batch ?? 100,
    );
    let ran = 0;
    for (const schedule of due) {
      await transport.send(
        schedule.queue,
        schedule.payload,
        0,
        5,
        `schedule:${schedule.name}:${schedule.nextRun.toString()}`,
      );
      const next = millis(
        nextCronRun(
          schedule.cron,
          schedule.timeZone,
          later(nowInstant(), schedule.nextRun),
        ),
      );
      if (
        await transport.advanceSchedule(schedule.name, schedule.nextRun, next)
      )
        ran += 1;
    }
    return ran;
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
    replay: (queue, id) =>
      run(() => {
        if (!transport.replay) sqlOnly("replay");
        return transport.replay(queue, id);
      }),
    schedule(name, cron, queue, payload, scheduleOptions = {}) {
      return AsyncResult.from(async () => {
        const valid = await validate(schemaOf(queue), payload, "payload");
        if (!valid.ok) return valid;
        const stored = withContext(valid.data, scheduleOptions.context);
        const timeZone = scheduleOptions.timeZone ?? "UTC";
        return run(() => {
          const nextRun = millis(nextCronRun(cron, timeZone, nowInstant()));
          return transport.schedule(
            name,
            cron,
            queue,
            stored,
            timeZone,
            nextRun,
          );
        });
      });
    },
    unschedule: (name) => run(() => transport.unschedule(name)),
    runSchedules: (scheduleOptions = {}) =>
      run(() => runSchedules(scheduleOptions)),
    drain: (queue, handler, drainOptions = {}) =>
      loop(
        queue,
        handler,
        drainOptions,
        false,
        drainOptions.budgetMs === undefined
          ? undefined
          : Date.now() + drainOptions.budgetMs,
      ),
    work: (queue, handler, workOptions = {}) =>
      loop(queue, handler, workOptions, true),
    drainRoute(routeOptions) {
      const secret = routeOptions.secret;
      if (!secret) {
        throw new TypeError(
          "drainRoute needs a secret, such as process.env.CRON_SECRET",
        );
      }
      for (const queue of Object.keys(routeOptions.handlers)) schemaOf(queue);
      return async (request) => {
        const instance = new URL(request.url).pathname;
        if (request.method !== "GET" && request.method !== "POST") {
          return new Response(null, {
            status: 405,
            headers: { allow: "GET, POST" },
          });
        }
        if (!verifySharedSecret(request, secret)) {
          return problemResponse(
            dbError("unauthorized", "The drain route needs its bearer secret"),
            { instance },
          );
        }
        const deadline = Date.now() + (routeOptions.budgetMs ?? 50_000);
        let scheduled = 0;
        if (routeOptions.schedules ?? true) {
          const ran = await run(() => runSchedules({}));
          if (ran.ok) scheduled = ran.data;
          else routeOptions.onError?.(ran.error);
        }
        const results: Record<string, DrainResult> = {};
        for (const [queue, handler] of Object.entries(routeOptions.handlers)) {
          if (handler === undefined) continue;
          if (Date.now() >= deadline) break;
          try {
            results[queue] = await loop(
              queue,
              // SAFETY: handlers maps each queue name to the handler for its
              // payload; loop validates the payload with that queue's schema.
              handler as JobHandler<unknown>,
              routeOptions,
              false,
              deadline,
            );
          } catch (cause) {
            routeOptions.onError?.(toDbError(cause));
            results[queue] = { succeeded: 0, failed: 0 };
          }
        }
        const result: DrainRouteResult = {
          schedules: scheduled,
          queues: results,
          budgetExhausted: Date.now() >= deadline,
        };
        return Response.json(result);
      };
    },
  };
}
