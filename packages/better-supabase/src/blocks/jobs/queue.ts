import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { SqlClient } from "../../postgres/executor.ts";

import { tenantFrom, tenantPathsFor } from "../../core/claims.ts";
import { type DbError, dbError } from "../../core/errors.ts";
import {
  type Actor,
  allTenantsContext,
  type RequestContext,
} from "../../core/plugin.ts";
import {
  type BlockProblemOptions,
  problemResponse,
} from "../../core/problem.ts";
import {
  AsyncResult,
  err,
  ok,
  type Result,
  toDbError,
} from "../../core/result.ts";
import { validate } from "../../core/standard.ts";
import { temporal } from "../../core/temporal-required.ts";
import { nowInstant } from "../../core/temporal.ts";
import {
  type BlockTemporalOptions,
  errorText,
  run,
  sleep,
  toInstant,
  applyTemporal,
} from "../shared.ts";
import { verifySharedSecret } from "../webhooks/verify.ts";
import {
  millis,
  type QueueBackend,
  type QueueStats,
  type QueueMessageRow,
  type QueueRpcClient,
  pgmqPublicBackend,
  sqlOnly,
  sqlQueueBackend,
} from "./backends.ts";
import { nextCronRun } from "./cron.ts";
import { unwrap, withContext } from "./envelope.ts";

// ---------------------------------------------------------------------------
// Job queue (SQL module `jobs`, on Supabase Queues / pgmq)

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
  /**
   * The `act` claim of a support or impersonated session, so the job runs
   * under the same terms (a read-only support session stays read-only).
   */
  readonly act?: Readonly<Record<string, unknown>>;
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
   * The actor and tenant recorded at enqueue, ready for `bs.forContext(job.context)`,
   * which runs as that user with RLS.
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
   * The tenant the schedule belongs to, for `listSchedules({ tenant })` and
   * `unscheduleAll({ tenant })`. Defaults to the tenant of `context`. Needs
   * `sql.modules.jobs.options.scheduler: "drain"`.
   */
  readonly tenant?: string;
  /**
   * The IANA time zone the cron fields are read in. Defaults to `UTC`.
   * Other zones need `sql.modules.jobs.options.scheduler: "drain"`.
   */
  readonly timeZone?: string;
}

/** One schedule of the set `ensureSchedules` keeps. */
export interface ScheduleDefinition<
  Q extends QueueSchemas,
  N extends Extract<keyof Q, string> = Extract<keyof Q, string>,
> extends ScheduleOptions {
  readonly name: string;
  readonly cron: string;
  readonly queue: N;
  readonly payload: PayloadIn<Q, N>;
}

/** Each queue's `ScheduleDefinition`, so `payload` follows `queue`. */
export type ScheduleDefinitions<Q extends QueueSchemas> = {
  readonly [N in Extract<keyof Q, string>]: ScheduleDefinition<Q, N>;
}[Extract<keyof Q, string>];

export interface EnsureSchedulesOptions {
  /**
   * The set's name prefix, such as `workflow:`. Every definition's name
   * starts with it, and existing schedules under it that the set doesn't
   * name are removed.
   */
  readonly prefix: string;
  /**
   * Only this tenant's schedules under the prefix are compared and removed,
   * and definitions without their own tenant get it.
   */
  readonly tenant?: string;
}

export interface EnsureSchedulesResult {
  /** The names written, in the order given. */
  readonly scheduled: readonly string[];
  /** Schedules under the prefix that the set no longer names. */
  readonly removed: readonly string[];
}

export interface ListDeadOptions {
  /** Defaults to 100, at most 1000. */
  readonly limit?: number;
  /** Only dead letters with a lower id, for the next page. */
  readonly before?: number;
}

export interface RetryDeadOptions {
  /** The dead letters to retry. Defaults to the newest `limit`. */
  readonly ids?: readonly number[];
  /** Defaults to 1000. */
  readonly limit?: number;
}

/** A dead letter as `listDead` returns it. */
export interface DeadJob<P = unknown> {
  readonly id: number;
  readonly queue: string;
  /** The stored payload, unvalidated: its schema may have changed since. */
  readonly payload: P;
  readonly context: RequestContext;
  readonly attempts: number;
  readonly maxAttempts: number;
  readonly lastError: string | null;
  readonly enqueuedAt: Temporal.Instant;
  /** When it was archived as dead. */
  readonly diedAt: Temporal.Instant | null;
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

export interface DrainRouteOptions<Q extends QueueSchemas>
  extends Omit<DrainOptions, "onError">, BlockProblemOptions {
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
  /** Hooks around each authorized drain, such as cron monitor check-ins. */
  readonly monitor?: DrainMonitor;
}

export interface DrainRouteResult {
  /** Schedules whose run was enqueued. */
  readonly schedules: number;
  readonly queues: Readonly<Record<string, DrainResult>>;
  /** True when the budget ran out before every queue was empty. */
  readonly budgetExhausted: boolean;
  /** Schedule or queue runs that failed as a whole (individual job failures are in `queues`). */
  readonly errors: number;
}

/**
 * Hooks around one authorized drain, for cron monitoring such as Sentry
 * check-ins. A hook that throws is reported to `onError` and never fails
 * the drain.
 */
export interface DrainMonitor {
  /** Before schedules run. Its return value (a check-in id) is passed to `onFinish`. */
  onStart?(request: Request): unknown;
  /** After the queues ran, with the result the route answers with. */
  onFinish?(result: DrainRouteResult, started: unknown): unknown;
}

/** A schedule as `listSchedules` returns it. */
export interface ScheduleInfo {
  readonly name: string;
  readonly cron: string;
  readonly timeZone: string;
  /** Null under pg_cron, which keeps only the command. */
  readonly queue: string | null;
  readonly tenant: string | null;
  /** The next run; null under pg_cron. */
  readonly nextRun: Temporal.Instant | null;
  readonly lastRun: Temporal.Instant | null;
  /** Set while a drain holds the schedule. */
  readonly leasedUntil: Temporal.Instant | null;
  readonly createdAt: Temporal.Instant | null;
}

export interface ScheduleFilter {
  /** Schedules whose name starts with this, e.g. `workflow:`. */
  readonly prefix?: string;
  readonly tenant?: string;
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
   * Counts per queue (ready, in flight, delayed, dead and the oldest
   * waiting message's age), for an admin page. Defaults to every queue
   * `createJobs` declared. SQL connections only.
   */
  stats<N extends Extract<keyof Q, string>>(
    queues?: readonly N[],
  ): AsyncResult<Record<N, QueueStats>>;
  /** A queue's dead letters, newest first, for an admin page. SQL connections only. */
  listDead<N extends Extract<keyof Q, string>>(
    queue: N,
    options?: ListDeadOptions,
  ): AsyncResult<DeadJob<PayloadOut<Q, N>>[]>;
  /**
   * Enqueues dead letters again, the `ids` given or the newest `limit`
   * (1000), each with its payload, attempts and dedupe key. Returns how many
   * went back on the queue. SQL connections only.
   */
  retryDead(
    queue: Extract<keyof Q, string>,
    options?: RetryDeadOptions,
  ): AsyncResult<number>;
  /**
   * Enqueues `payload` on a cron schedule (`'0 3 * * *'`, `'@daily'`,
   * `'30 seconds'`), with pg_cron or the drain scheduler
   * (`sql.modules.jobs.options.scheduler`). Re-scheduling a name replaces it. SQL
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
   * Makes the schedules under `prefix` (and `tenant`) exactly `definitions`:
   * writes each one, keeping the next run of a schedule whose cron and time
   * zone didn't change, and removes the rest. Every payload and cron is
   * checked before anything is written. Run it on deploy or after a
   * settings change; running it twice changes nothing. SQL connections only.
   */
  ensureSchedules(
    definitions: readonly ScheduleDefinitions<Q>[],
    options: EnsureSchedulesOptions,
  ): AsyncResult<EnsureSchedulesResult>;
  /** Schedules by name prefix or tenant, with their next and last run. SQL connections only. */
  listSchedules(filter?: ScheduleFilter): AsyncResult<ScheduleInfo[]>;
  /** Removes every schedule of a tenant, for tenant deletion; returns how many. SQL connections only. */
  unscheduleAll(filter: { readonly tenant: string }): AsyncResult<number>;
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
 * Typed jobs on Supabase Queues (pgmq), over the `jobs` SQL module.
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
  options: BlockTemporalOptions = {},
): Jobs<Q> {
  applyTemporal(options);
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

  interface PreparedSchedule {
    readonly name: string;
    readonly cron: string;
    readonly queue: string;
    readonly payload: unknown;
    readonly timeZone: string;
    readonly tenant: string | undefined;
  }

  const prepare = async (
    name: string,
    cron: string,
    queue: string,
    payload: unknown,
    scheduleOptions: ScheduleOptions,
    tenantDefault?: string,
  ): Promise<Result<PreparedSchedule>> => {
    const valid = await validate(schemaOf(queue), payload, "payload");
    if (!valid.ok) return valid;
    const timeZone = scheduleOptions.timeZone ?? "UTC";
    try {
      nextCronRun(cron, timeZone, nowInstant());
    } catch (cause) {
      return err(
        dbError("validation", errorText(cause), {
          issues: [{ message: errorText(cause), path: [name, "cron"] }],
        }),
      );
    }
    return ok({
      name,
      cron,
      queue,
      payload: withContext(valid.data, scheduleOptions.context),
      timeZone,
      tenant:
        scheduleOptions.tenant ??
        (scheduleOptions.context
          ? tenantFrom(scheduleOptions.context, tenantPathsFor(undefined))
          : undefined) ??
        tenantDefault,
    });
  };

  const write = (prepared: PreparedSchedule): Promise<void> =>
    transport.schedule(
      prepared.name,
      prepared.cron,
      prepared.queue,
      prepared.payload,
      prepared.timeZone,
      millis(nextCronRun(prepared.cron, prepared.timeZone, nowInstant())),
      prepared.tenant,
    );

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
    stats: (names) =>
      run(async () => {
        const stats = (queue: string): Promise<QueueStats> =>
          transport.stats?.(queue) ?? sqlOnly("stats");
        const list = names ?? Object.keys(queues);
        const entries = await Promise.all(
          list.map(async (queue) => {
            schemaOf(queue);
            return [queue, await stats(queue)] as const;
          }),
        );
        // SAFETY: the entries are exactly the requested queue names.
        return Object.fromEntries(entries) as Record<
          (typeof list)[number],
          QueueStats
        >;
      }),
    listDead: (queue, listOptions = {}) =>
      run(async () => {
        if (!transport.listDead) sqlOnly("listDead");
        schemaOf(queue);
        const rows = await transport.listDead(
          queue,
          listOptions.limit ?? 100,
          listOptions.before,
        );
        return rows.map((row) => {
          const message = row.message ?? {};
          const { payload, context } = unwrap(message.payload);
          return {
            id: Number(row.id),
            queue,
            // SAFETY: the payload was validated with this queue's schema at enqueue.
            payload: payload as never,
            context,
            attempts: row.attempts,
            maxAttempts: message.max_attempts ?? 5,
            lastError: message.last_error ?? null,
            enqueuedAt: toInstant(row.enqueued_at),
            diedAt: row.died_at === null ? null : toInstant(row.died_at),
          };
        });
      }),
    retryDead: (queue, retryOptions = {}) =>
      run(async () => {
        if (!transport.retryDead) sqlOnly("retryDead");
        schemaOf(queue);
        return transport.retryDead(
          queue,
          retryOptions.ids,
          retryOptions.limit ?? 1000,
        );
      }),
    replay: (queue, id) =>
      run(() => {
        if (!transport.replay) sqlOnly("replay");
        return transport.replay(queue, id);
      }),
    schedule(name, cron, queue, payload, scheduleOptions = {}) {
      return AsyncResult.from(async () => {
        const prepared = await prepare(
          name,
          cron,
          queue,
          payload,
          scheduleOptions,
        );
        if (!prepared.ok) return prepared;
        return run(() => write(prepared.data));
      });
    },
    unschedule: (name) => run(() => transport.unschedule(name)),
    ensureSchedules(definitions, ensureOptions) {
      return AsyncResult.from(async () => {
        const { prefix, tenant } = ensureOptions;
        if (prefix.length === 0) {
          return err(
            dbError(
              "invalid_request",
              "ensureSchedules needs a non-empty prefix",
            ),
          );
        }
        const names = new Set<string>();
        const prepared: PreparedSchedule[] = [];
        for (const definition of definitions) {
          if (
            !definition.name.startsWith(prefix) ||
            names.has(definition.name)
          ) {
            return err(
              dbError(
                "invalid_request",
                names.has(definition.name)
                  ? `Schedule "${definition.name}" is defined twice`
                  : `Schedule "${definition.name}" does not start with "${prefix}"`,
              ),
            );
          }
          names.add(definition.name);
          const ready = await prepare(
            definition.name,
            definition.cron,
            definition.queue,
            definition.payload,
            definition,
            tenant,
          );
          if (!ready.ok) return ready;
          prepared.push(ready.data);
        }
        return run(async () => {
          if (!transport.listSchedules) sqlOnly("ensureSchedules");
          const existing = await transport.listSchedules({
            prefix,
            ...(tenant === undefined ? {} : { tenant }),
          });
          for (const schedule of prepared) await write(schedule);
          const removed: string[] = [];
          for (const schedule of existing) {
            if (names.has(schedule.name)) continue;
            if (await transport.unschedule(schedule.name))
              removed.push(schedule.name);
          }
          return { scheduled: [...names], removed };
        });
      });
    },
    listSchedules: (filter = {}) =>
      run(async () => {
        if (!transport.listSchedules) sqlOnly("listSchedules");
        return [...(await transport.listSchedules(filter))];
      }),
    unscheduleAll: (filter) =>
      run(() => {
        if (!transport.unscheduleTenant) sqlOnly("unscheduleAll");
        return transport.unscheduleTenant(filter.tenant);
      }),
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
            { instance, format: routeOptions.problem },
          );
        }
        const deadline = Date.now() + (routeOptions.budgetMs ?? 50_000);
        const monitor = routeOptions.monitor;
        let errors = 0;
        const report = (cause: unknown): void => {
          errors += 1;
          routeOptions.onError?.(toDbError(cause));
        };
        const watch = async (fn: () => unknown): Promise<unknown> => {
          try {
            return await fn();
          } catch (cause) {
            routeOptions.onError?.(toDbError(cause));
            return undefined;
          }
        };
        const started = monitor?.onStart
          ? await watch(() => monitor.onStart?.(request))
          : undefined;
        let scheduled = 0;
        if (routeOptions.schedules ?? true) {
          const ran = await run(() => runSchedules({}));
          if (ran.ok) scheduled = ran.data;
          else {
            errors += 1;
            routeOptions.onError?.(ran.error);
          }
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
            report(cause);
            results[queue] = { succeeded: 0, failed: 0 };
          }
        }
        const result: DrainRouteResult = {
          schedules: scheduled,
          queues: results,
          budgetExhausted: Date.now() >= deadline,
          errors,
        };
        if (monitor?.onFinish) {
          await watch(() => monitor.onFinish?.(result, started));
        }
        return Response.json(result);
      };
    },
  };
}
