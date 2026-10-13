import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { DbError } from "../../core/errors.ts";
import type { Actor, RequestContext } from "../../core/plugin.ts";
import type { BlockProblemOptions } from "../../core/problem.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";
import type { QueueStats } from "./backends.ts";

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
   * Which jobs with the same `dedupeKey` take the enqueue: `"always"` (the
   * default) a waiting or running one, `"waiting"` only one no worker has
   * claimed yet, so a change made during a run queues one follow-up (a
   * debounce).
   */
  readonly dedupe?: "always" | "waiting";
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

export interface ListDeadOptions extends CursorPageOptions<number> {
  /** Defaults to 100, at most 1000. */
  readonly limit?: number;
  /** Only dead letters with a lower id, for the next page. */
  readonly cursor?: number;
}

export interface RetryDeadOptions {
  /** The dead letters to retry. Defaults to the newest `limit`. */
  readonly ids?: readonly number[];
  /** Defaults to 1000. */
  readonly limit?: number;
}

export interface PurgeJobsOptions<N extends string = string> {
  readonly queues?: readonly N[];
  /** Seconds, or an interval such as `"7 days"`. */
  readonly olderThan?: number | string;
  /** Seconds, or an interval such as `"30 days"`. */
  readonly deadOlderThan?: number | string;
  /** Defaults to 10000. */
  readonly batch?: number;
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
   * Deletes archived messages (`purge_job_archive`): completed ones after
   * `olderThan` (7 days) and dead letters after `deadOlderThan` (30 days), up
   * to `batch` per queue. Covers every queue `createJobs` declared unless
   * `queues` is given. Returns how many. SQL connections or a transport only.
   */
  purge<N extends Extract<keyof Q, string>>(
    options?: PurgeJobsOptions<N>,
  ): AsyncResult<number>;
  /** A job handler that runs `purge`; schedule it nightly. */
  purgeJob(
    options?: PurgeJobsOptions<Extract<keyof Q, string>>,
  ): JobHandler<unknown>;
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

/** The options `createJobs` takes. */
export interface JobsOptions extends BlockTemporalOptions {
  /**
   * The clock for `runAt` delays and schedule runs; pass the definition's
   * `now` option to share one clock. Defaults to `Temporal.Now.instant()`.
   */
  readonly now?: () => Temporal.Instant;
}
