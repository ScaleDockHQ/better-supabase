import type { BlockTransport } from "../../core/block-transport.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { Job, ScheduleFilter, ScheduleInfo } from "./types.ts";

import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
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
  /**
   * Sends once per `dedupeKey`, counting archived messages too; `duplicate`
   * when one existed. Absent when the backend can't.
   */
  sendOnce?(
    queue: string,
    payload: unknown,
    delay: number,
    maxAttempts: number,
    dedupeKey: string,
  ): Promise<{ readonly id: number; readonly duplicate: boolean }>;
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
  /**
   * Deletes up to `batch` archived messages of `queue`; an unset option keeps
   * the SQL default. Returns how many. Absent when the backend can't.
   */
  purge?(queue: string, options: QueuePurgeArgs): Promise<number>;
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
function firstRun(
  row: ScheduleRow,
  now: () => Temporal.Instant,
): Temporal.Instant | undefined {
  try {
    return millis(
      nextCronRun(
        row.schedule,
        row.timezone,
        row.first_after ? toInstant(row.first_after) : now(),
      ),
    );
  } catch {
    return undefined;
  }
}

/**
 * The due schedules among claimed rows. A row written in SQL without a next
 * run gets its first run here; one not due yet is moved to it with `advance`.
 */
async function dueOf(
  rows: readonly ScheduleRow[],
  now: () => Temporal.Instant,
  advance: (name: string, first: Temporal.Instant) => Promise<void>,
): Promise<DueSchedule[]> {
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
    const first = firstRun(row, now);
    if (first === undefined) {
      continue;
    }
    if (temporal().Instant.compare(first, now()) <= 0) {
      due.push({ ...schedule, nextRun: first });
    } else {
      await advance(row.job_name, first);
    }
  }
  return due;
}

const scheduleInfo = (row: ScheduleListRow): ScheduleInfo => ({
  name: row.job_name,
  cron: row.schedule,
  timeZone: row.timezone,
  queue: row.queue,
  tenant: row.tenant,
  nextRun: instantOrNull(row.next_run),
  lastRun: instantOrNull(row.last_run),
  leasedUntil: instantOrNull(row.locked_until),
  createdAt: instantOrNull(row.created_at),
});

interface StatsRow {
  readonly ready: string | number;
  readonly in_flight: string | number;
  readonly delayed: string | number;
  readonly dead: string | number;
  readonly oldest_age_seconds: string | number | null;
}

const statsOf = (row: StatsRow | undefined): QueueStats => ({
  ready: Number(row?.ready ?? 0),
  inFlight: Number(row?.in_flight ?? 0),
  delayed: Number(row?.delayed ?? 0),
  dead: Number(row?.dead ?? 0),
  oldestAgeSeconds:
    row?.oldest_age_seconds === null || row?.oldest_age_seconds === undefined
      ? null
      : Number(row.oldest_age_seconds),
});

interface OnceRow {
  readonly id: string | number;
  readonly duplicate: boolean;
}

const onceOf = (
  row: OnceRow | undefined,
): { readonly id: number; readonly duplicate: boolean } => {
  if (!row) {
    throw new TypeError("enqueue_job_once returned no row");
  }
  return { id: Number(row.id), duplicate: row.duplicate };
};

/**
 * The `jobs` SQL module over a service SQL connection. The same
 * functions back both `blocks.jobs.options.backend` values (pgmq and table)
 * and both schedulers. `now` dates a schedule's first run.
 */
export function sqlQueueBackend(
  sql: SqlClient,
  now: () => Temporal.Instant = nowInstant,
): QueueBackend {
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
    async sendOnce(queue, payload, delay, maxAttempts, dedupeKey) {
      const [row] = await sql.queryRaw<OnceRow>(
        "select * from better_supabase.enqueue_job_once($1, $2, $3, $4, $5)",
        [queue, JSON.stringify(payload ?? {}), dedupeKey, delay, maxAttempts],
      );
      return onceOf(row);
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
      const [row] = await sql.queryRaw<StatsRow>(
        "select * from better_supabase.job_queue_stats($1)",
        [queue],
      );
      return statsOf(row);
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
    async purge(queue, args) {
      const named = Object.entries({
        older_than: args.olderThan,
        batch: args.batch,
        dead_older_than: args.deadOlderThan,
      }).filter(([, value]) => value !== undefined);
      const [row] = await sql.queryRaw<{ purged: number }>(
        `select better_supabase.purge_job_archive(${["queue => $1", ...named.map(([name], index) => `${name} => $${String(index + 2)}`)].join(", ")}) as purged`,
        [queue, ...named.map(([, value]) => value)],
      );
      return row?.purged ?? 0;
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
      return rows.map(scheduleInfo);
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
      return dueOf(rows, now, async (name, first) => {
        await sql.queryRaw(
          "select better_supabase.advance_schedule($1, null, $2)",
          [name, first.toString()],
        );
      });
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

/** The named arguments of each `jobs` function, in call order. */
const PARAMS = {
  enqueue_job: [
    "queue",
    "payload",
    "delay",
    "max_attempts",
    "dedupe_key",
    "dedupe_running",
  ],
  enqueue_job_once: ["queue", "payload", "dedupe_key", "delay", "max_attempts"],
  claim_jobs: ["queue", "lease", "batch"],
  complete_job: ["queue", "job_id", "attempt"],
  fail_job: ["queue", "job_id", "attempt", "error", "retry_in"],
  extend_job_lease: ["queue", "job_id", "attempt", "lease"],
  replay_dead_job: ["queue", "job_id"],
  job_queue_stats: ["queue"],
  list_dead_jobs: ["queue", "max_rows", "before_id"],
  retry_dead_jobs: ["queue", "ids", "batch"],
  schedule_job: [
    "job_name",
    "schedule",
    "queue",
    "payload",
    "timezone",
    "next_run",
    "tenant",
  ],
  unschedule_job: ["job_name"],
  list_schedules: ["name_prefix", "for_tenant"],
  unschedule_tenant: ["tenant"],
  claim_due_schedules: ["lease", "batch"],
  advance_schedule: ["job_name", "ran", "next_run"],
  purge_job_archive: ["queue", "older_than", "batch", "dead_older_than"],
} as const satisfies Readonly<Record<string, readonly string[]>>;

/** A `jobs` SQL module function `transportQueueBackend` calls. */
type JobsFunction = keyof typeof PARAMS;

/** Options for `transportQueueBackend`. */
export interface TransportQueueBackendOptions {
  /** The schema the functions live in. Defaults to `better_supabase`. */
  readonly schema?: string;
  /** Dates a schedule's first run. */
  readonly now?: () => Temporal.Instant;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * The rows a set-returning function answered with. PostgREST and `dbTransport`
 * return an array; a single object is one row.
 */
export function transportRows<T>(fn: string, value: unknown): readonly T[] {
  if (value === null || value === undefined) {
    return [];
  }
  if (Array.isArray(value)) {
    // SAFETY: T is the row type the caller declares for this function's result.
    return value as T[];
  }
  if (isRecord(value)) {
    // SAFETY: T is the row type the caller declares for this function's result.
    return [value as T];
  }
  throw new TypeError(
    `${fn} returned ${typeof value}, not rows: pass a SqlClient instead of sqlTransport for set-returning functions`,
  );
}

/** The intervals are Postgres intervals such as `"7 days"`. */
export interface QueuePurgeArgs {
  readonly olderThan?: string | undefined;
  readonly deadOlderThan?: string | undefined;
  readonly batch?: number | undefined;
}

/**
 * The `jobs` SQL module over a `BlockTransport`, with named arguments: a
 * service-role `rpcTransport(supabase, { schema: "api" })` reaches the
 * wrappers `blocks.jobs.api` writes, so stats, dead letters, replays
 * and schedules work without a direct Postgres connection. Over Postgres,
 * pass the `SqlClient` to `createJobs` instead.
 */
export function transportQueueBackend(
  transport: BlockTransport,
  options: TransportQueueBackendOptions = {},
): QueueBackend {
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const now = options.now ?? nowInstant;
  const call = (fn: JobsFunction, ...args: unknown[]): Promise<unknown> =>
    transport.call(
      schema,
      fn,
      Object.fromEntries(
        PARAMS[fn].flatMap((name, index) =>
          index < args.length ? [[name, args[index]]] : [],
        ),
      ),
    );
  const rows = async <T>(fn: JobsFunction, ...args: unknown[]) =>
    transportRows<T>(fn, await call(fn, ...args));
  const bool = async (fn: JobsFunction, ...args: unknown[]) =>
    (await call(fn, ...args)) === true;
  const count = async (fn: JobsFunction, ...args: unknown[]) =>
    Number((await call(fn, ...args)) ?? 0);
  const id = (value: unknown): number | null =>
    value === null || value === undefined ? null : Number(value);
  return {
    apiVersion: 1,
    name: "transport",
    leases: true,
    async send(queue, payload, delay, maxAttempts, dedupeKey, dedupe) {
      const sent = id(
        await call(
          "enqueue_job",
          queue,
          payload ?? {},
          delay,
          maxAttempts,
          dedupeKey ?? null,
          dedupe !== "waiting",
        ),
      );
      if (sent === null) {
        throw new TypeError("enqueue_job returned no id");
      }
      return sent;
    },
    sendOnce: async (queue, payload, delay, maxAttempts, dedupeKey) =>
      onceOf(
        (
          await rows<OnceRow>(
            "enqueue_job_once",
            queue,
            payload ?? {},
            dedupeKey,
            delay,
            maxAttempts,
          )
        )[0],
      ),
    read: (queue, lease, batch) =>
      rows<QueueMessageRow>("claim_jobs", queue, lease, batch),
    complete: (job) => bool("complete_job", job.queue, job.id, job.attempts),
    async fail(job, error, retryIn) {
      const status = await call(
        "fail_job",
        job.queue,
        job.id,
        job.attempts,
        error,
        retryIn ?? null,
      );
      return status === "queued" || status === "dead" ? status : null;
    },
    extend: (job, lease) =>
      bool("extend_job_lease", job.queue, job.id, job.attempts, lease),
    replay: async (queue, jobId) =>
      id(await call("replay_dead_job", queue, jobId)),
    stats: async (queue) =>
      statsOf((await rows<StatsRow>("job_queue_stats", queue))[0]),
    listDead: (queue, limit, before) =>
      rows<DeadJobRow>("list_dead_jobs", queue, limit, before ?? null),
    retryDead: (queue, ids, limit) =>
      count(
        "retry_dead_jobs",
        queue,
        ids === undefined ? null : [...ids],
        limit,
      ),
    purge: (queue, args) =>
      count(
        "purge_job_archive",
        queue,
        args.olderThan,
        args.batch,
        args.deadOlderThan,
      ),
    async schedule(name, cron, queue, payload, timeZone, nextRun, tenant) {
      await call(
        "schedule_job",
        name,
        cron,
        queue,
        payload ?? {},
        timeZone,
        nextRun.toString(),
        tenant ?? null,
      );
    },
    unschedule: (name) => bool("unschedule_job", name),
    listSchedules: async (filter) =>
      (
        await rows<ScheduleListRow>(
          "list_schedules",
          filter.prefix ?? null,
          filter.tenant ?? null,
        )
      ).map(scheduleInfo),
    unscheduleTenant: (tenant) => count("unschedule_tenant", tenant),
    dueSchedules: async (lease, batch) =>
      dueOf(
        await rows<ScheduleRow>("claim_due_schedules", lease, batch),
        now,
        async (name, first) => {
          await call("advance_schedule", name, null, first.toString());
        },
      ),
    advanceSchedule: (name, ran, next) =>
      bool("advance_schedule", name, ran.toString(), next.toString()),
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
      if (dedupeKey !== undefined) {
        sqlOnly("dedupeKey");
      }
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
        } else {
          live.push(row);
        }
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
      if (job.attempts < job.maxAttempts) {
        return "queued";
      }
      await archive(job);
      return "dead";
    },
    extend: () => Promise.resolve(false),
    schedule: () => sqlOnly("schedule"),
    unschedule: () => sqlOnly("unschedule"),
  };
}
