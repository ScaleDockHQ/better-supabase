import type { SqlClient } from "../../postgres/executor.ts";
import type { Job, ScheduleFilter, ScheduleInfo } from "./queue.ts";

import { dbError, DbException } from "../../core/errors.ts";
import { temporal } from "../../core/temporal-required.ts";
import { nowInstant } from "../../core/temporal.ts";
import { toInstant } from "../shared.ts";
import { nextCronRun } from "./cron.ts";

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

/** A queue's counts, as `jobs.stats` returns them. */
export interface QueueStats {
  /** Visible now: the next claim takes them. */
  readonly ready: number;
  /** Claimed by a worker, or waiting out the backoff before a retry. */
  readonly inFlight: number;
  /** Enqueued with a delay and not claimed yet. */
  readonly delayed: number;
  /** Dead letters kept in the archive. */
  readonly dead: number;
  /** Seconds since the oldest message that isn't done was enqueued; null when none is waiting. */
  readonly oldestAgeSeconds: number | null;
}

/** A dead letter, as `better_supabase.list_dead_jobs` returns it. */
export interface DeadJobRow {
  readonly id: string | number;
  readonly attempts: number;
  readonly enqueued_at: Date | string;
  readonly died_at: Date | string | null;
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
  /**
   * `never` parameters, so a typed `SupabaseClient<Database>` whose types
   * leave out `pgmq_public` fits too.
   */
  schema(name: never): {
    rpc(fn: never, args: never): PromiseLike<{ data: unknown; error: unknown }>;
  };
}

/** How the backend calls the client. */
interface UntypedQueueClient {
  schema(name: string): {
    rpc(
      fn: string,
      args: Readonly<Record<string, unknown>>,
    ): PromiseLike<{ data: unknown; error: unknown }>;
  };
}

/**
 * Where `createJobs` stores jobs. `sqlQueueBackend` (the `jobs` SQL module
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
    /** `"waiting"` coalesces only onto a job no worker has claimed; `undefined` means `"always"`. */
    dedupe?: "always" | "waiting",
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
  /** Counts for one queue. Absent when the backend can't. */
  stats?(queue: string): Promise<QueueStats>;
  /** Dead letters, newest first, before `before` when given. Absent when the backend can't. */
  listDead?(
    queue: string,
    limit: number,
    before: number | undefined,
  ): Promise<readonly DeadJobRow[]>;
  /** Re-enqueues the dead letters `ids`, or the newest `limit`; returns how many. */
  retryDead?(
    queue: string,
    ids: readonly number[] | undefined,
    limit: number,
  ): Promise<number>;
  schedule(
    name: string,
    cron: string,
    queue: string,
    payload: unknown,
    timeZone: string,
    nextRun: Temporal.Instant,
    tenant?: string,
  ): Promise<void>;
  unschedule(name: string): Promise<boolean>;
  /** Schedules by name prefix and tenant. Absent when the backend can't list them. */
  listSchedules?(filter: ScheduleFilter): Promise<readonly ScheduleInfo[]>;
  /** Removes a tenant's schedules and returns how many. Absent when the backend can't. */
  unscheduleTenant?(tenant: string): Promise<number>;
  /** Leases due schedules (the drain scheduler); absent or empty with pg_cron. */
  dueSchedules?(lease: number, batch: number): Promise<readonly DueSchedule[]>;
  /** Moves a schedule from `ran` to `next`; `false` when it changed since the claim. */
  advanceSchedule?(
    name: string,
    ran: Temporal.Instant,
    next: Temporal.Instant,
  ): Promise<boolean>;
}

interface ScheduleListRow {
  readonly job_name: string;
  readonly schedule: string;
  readonly timezone: string;
  readonly queue: string | null;
  readonly tenant: string | null;
  readonly next_run: Date | string | null;
  readonly last_run: Date | string | null;
  readonly locked_until: Date | string | null;
  readonly created_at: Date | string | null;
}

const instantOrNull = (value: Date | string | null): Temporal.Instant | null =>
  value === null ? null : toInstant(value);

interface ScheduleRow {
  readonly job_name: string;
  readonly schedule: string;
  readonly timezone: string;
  readonly queue: string;
  readonly payload: unknown;
  readonly next_run: Date | string | null;
  readonly first_after?: Date | string | null;
}

/** Schedule times are stored to the millisecond, the precision `Date` reads back. */
export const millis = (instant: Temporal.Instant): Temporal.Instant =>
  instant.round({ smallestUnit: "millisecond", roundingMode: "floor" });

/** The first run of a schedule written without one, or undefined for a cron the drain can't read. */
function firstRun(row: ScheduleRow): Temporal.Instant | undefined {
  try {
    return millis(
      nextCronRun(
        row.schedule,
        row.timezone,
        row.first_after ? toInstant(row.first_after) : nowInstant(),
      ),
    );
  } catch {
    return undefined;
  }
}

/**
 * The `jobs` SQL module over a service SQL connection. The same
 * functions back both `sql.modules.jobs.options.backend` values (pgmq and table)
 * and both schedulers.
 */
export function sqlQueueBackend(sql: SqlClient): QueueBackend {
  return {
    apiVersion: 1,
    name: "sql",
    leases: true,
    async send(queue, payload, delay, maxAttempts, dedupeKey, dedupe) {
      const [row] = await sql.queryRaw<{ id: string | number }>(
        "select better_supabase.enqueue_job($1, $2, $3, $4, $5, $6) as id",
        [
          queue,
          JSON.stringify(payload ?? {}),
          delay,
          maxAttempts,
          dedupeKey ?? null,
          dedupe !== "waiting",
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
    async stats(queue) {
      const [row] = await sql.queryRaw<{
        ready: string | number;
        in_flight: string | number;
        delayed: string | number;
        dead: string | number;
        oldest_age_seconds: string | number | null;
      }>("select * from better_supabase.job_queue_stats($1)", [queue]);
      return {
        ready: Number(row?.ready ?? 0),
        inFlight: Number(row?.in_flight ?? 0),
        delayed: Number(row?.delayed ?? 0),
        dead: Number(row?.dead ?? 0),
        oldestAgeSeconds:
          row?.oldest_age_seconds === null ||
          row?.oldest_age_seconds === undefined
            ? null
            : Number(row.oldest_age_seconds),
      };
    },
    listDead: (queue, limit, before) =>
      sql.queryRaw<DeadJobRow>(
        "select * from better_supabase.list_dead_jobs($1, $2, $3)",
        [queue, limit, before ?? null],
      ),
    async retryDead(queue, ids, limit) {
      const [row] = await sql.queryRaw<{ retried: number }>(
        "select better_supabase.retry_dead_jobs($1, $2, $3) as retried",
        [queue, ids === undefined ? null : [...ids], limit],
      );
      return row?.retried ?? 0;
    },
    async schedule(name, cron, queue, payload, timeZone, nextRun, tenant) {
      await sql.queryRaw(
        "select better_supabase.schedule_job($1, $2, $3, $4, $5, $6, $7)",
        [
          name,
          cron,
          queue,
          JSON.stringify(payload ?? {}),
          timeZone,
          nextRun.toString(),
          tenant ?? null,
        ],
      );
    },
    async listSchedules(filter) {
      const rows = await sql.queryRaw<ScheduleListRow>(
        "select * from better_supabase.list_schedules($1, $2)",
        [filter.prefix ?? null, filter.tenant ?? null],
      );
      return rows.map((row) => ({
        name: row.job_name,
        cron: row.schedule,
        timeZone: row.timezone,
        queue: row.queue,
        tenant: row.tenant,
        nextRun: instantOrNull(row.next_run),
        lastRun: instantOrNull(row.last_run),
        leasedUntil: instantOrNull(row.locked_until),
        createdAt: instantOrNull(row.created_at),
      }));
    },
    async unscheduleTenant(tenant) {
      const [row] = await sql.queryRaw<{ removed: number }>(
        "select better_supabase.unschedule_tenant($1) as removed",
        [tenant],
      );
      return row?.removed ?? 0;
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
      const due: DueSchedule[] = [];
      for (const row of rows) {
        const schedule = {
          name: row.job_name,
          cron: row.schedule,
          timeZone: row.timezone,
          queue: row.queue,
          payload: row.payload,
        };
        if (row.next_run !== null) {
          due.push({ ...schedule, nextRun: toInstant(row.next_run) });
          continue;
        }
        const first = firstRun(row);
        if (first === undefined) continue;
        if (temporal().Instant.compare(first, nowInstant()) <= 0) {
          due.push({ ...schedule, nextRun: first });
        } else {
          await sql.queryRaw(
            "select better_supabase.advance_schedule($1, null, $2)",
            [row.job_name, first.toString()],
          );
        }
      }
      return due;
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

/** Throws for a feature the transport doesn't support. */
export function sqlOnly(feature: string): never {
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
  // Method parameters are bivariant, so the never parameters widen back.
  const untyped: UntypedQueueClient = client;
  const call = async <T>(
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): Promise<T> => {
    const { data, error } = await untyped.schema("pgmq_public").rpc(fn, args);
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
