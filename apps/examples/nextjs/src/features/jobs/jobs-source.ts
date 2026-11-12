import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import { postgres } from "@/features/developer/postgres";

import type { JobRow } from "./jobs-list";

import { QUEUE_NAME } from "./jobs-server";

interface JobRaw extends AdminListRaw {
  readonly queue: string;
  readonly message_id: string;
  readonly status: string;
  readonly attempts: number;
  readonly last_error: string | null;
  readonly enqueued_at: string;
  readonly finished_at: string | null;
}

/**
 * One queue's live messages and archive, limited to jobs whose recorded context
 * names the tenant (`$1`). `queue` was checked against `QUEUE_NAME`.
 */
const queueRuns = (queue: string): string => `
  select '${queue}' as queue, msg_id as message_id,
    case
      when vt <= clock_timestamp() then 'queued'
      when read_ct = 0 then 'scheduled'
      when message ? 'last_error' then 'retrying'
      else 'running'
    end as status,
    read_ct as attempts, message ->> 'last_error' as last_error,
    enqueued_at, null::timestamptz as finished_at
  from pgmq."q_${queue}" where message #>> '{payload,context,tenant}' = $1
  union all
  select '${queue}', msg_id,
    case when message ? 'dead' then 'dead' else 'succeeded' end,
    read_ct, message ->> 'last_error', enqueued_at, archived_at
  from pgmq."a_${queue}" where message #>> '{payload,context,tenant}' = $1`;

/** The pgmq queue names the page may read. */
export async function queueNames(): Promise<readonly string[]> {
  const connection = postgres();

  if (!connection) {
    throw new Error("The jobs page needs a database URL");
  }

  const queues = await connection.admin.queryRaw<{ queue_name: string }>(
    "select queue_name from pgmq.list_queues() order by queue_name",
  );

  return queues
    .map((row) => row.queue_name)
    .filter((name) => QUEUE_NAME.test(name));
}

/**
 * The runs of every queue as one source. pgmq grants its tables to the service
 * role only, so the page reads as the database owner after checking
 * `audit.read`; the `$1` condition inside each queue keeps it to the tenant.
 */
export function jobSource(
  queues: readonly string[],
): AdminListSource<JobRaw, JobRow> {
  const runs =
    queues.length === 0
      ? `select null::text as queue, null::bigint as message_id, null::text as status,
           null::int as attempts, null::text as last_error,
           null::timestamptz as enqueued_at, null::timestamptz as finished_at
         where false`
      : queues.map(queueRuns).join(" union all ");

  return {
    from: `(${runs}) r`,
    idColumn: "(r.queue || ':' || r.message_id::text)",
    idType: "text",
    timeColumn: "r.enqueued_at",
    scope: "$1::text is not null",
    search: ["r.queue", "coalesce(r.last_error, '')"],
    facetSql: { status: "r.status", queue: "r.queue" },
    select: `r.queue, r.message_id::text as message_id, r.status, r.attempts,
      r.last_error, r.enqueued_at::text as enqueued_at, r.finished_at::text as finished_at`,
    map: (raw) => ({
      id: raw.id,
      queue: raw.queue,
      messageId: Number(raw.message_id),
      status: raw.status,
      attempts: raw.attempts,
      lastError: raw.last_error,
      enqueuedAt: raw.enqueued_at,
      finishedAt: raw.finished_at,
    }),
  };
}

interface JobDetailRaw {
  readonly queue: string;
  readonly message_id: string;
  readonly status: string;
  readonly attempts: number;
  readonly last_error: string | null;
  readonly enqueued_at: Date;
  readonly finished_at: Date | null;
  readonly payload: unknown;
}

/**
 * One run with its payload; `null` when the queue or message isn't the
 * tenant's.
 */
export async function getJobRun(tenant: string, queue: string, id: number) {
  if (!QUEUE_NAME.test(queue)) {
    return null;
  }

  const connection = postgres();

  if (!connection) {
    throw new Error("The jobs page needs a database URL");
  }

  const known = await queueNames();

  if (!known.includes(queue)) {
    return null;
  }

  const [row] = await connection.admin.queryRaw<JobDetailRaw>(
    `select r.*, m.message #> '{payload}' as payload from (${queueRuns(queue)}) r
     join (
       select msg_id, message from pgmq."q_${queue}"
       union all select msg_id, message from pgmq."a_${queue}"
     ) m on m.msg_id = r.message_id
     where r.message_id = $2`,
    [tenant, id],
  );

  return row ?? null;
}
