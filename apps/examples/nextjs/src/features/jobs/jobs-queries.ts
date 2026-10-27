import "server-only";
import { tenantOf } from "better-supabase/next";
import * as v from "valibot";

import { postgres } from "@/features/developer/postgres";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsb } from "@/lib/supabase/server";

import { JOBS_PERMISSION, QUEUE_NAME } from "./jobs-server";

export const JobRunStatus = v.picklist([
  "queued",
  "scheduled",
  "running",
  "retrying",
  "succeeded",
  "dead",
]);

export type JobRunStatus = v.InferOutput<typeof JobRunStatus>;

export interface JobRunRow {
  readonly queue: string;
  readonly id: number;
  readonly status: JobRunStatus;
  readonly attempts: number;
  readonly lastError: string | null;
  readonly enqueuedAt: string;
  readonly finishedAt: string | null;
}

interface JobRunRecord {
  readonly queue: string;
  readonly id: string;
  readonly status: string;
  readonly attempts: number;
  readonly last_error: string | null;
  readonly enqueued_at: Date;
  readonly finished_at: Date | null;
}

const LIMIT = 50;

/**
 * One queue's live messages and archive, limited to jobs whose recorded context
 * names the tenant (`createQueue` writes it at enqueue). The queue name is
 * checked against `QUEUE_NAME` before it reaches the SQL.
 */
function queueRuns(queue: string, param: string): string {
  const tenant = `message #>> '{payload,context,tenant}' = ${param}`;

  return `(select '${queue}' as queue, msg_id as id,
      case
        when vt <= clock_timestamp() then 'queued'
        when read_ct = 0 then 'scheduled'
        when message ? 'last_error' then 'retrying'
        else 'running'
      end as status,
      read_ct as attempts, message ->> 'last_error' as last_error,
      enqueued_at, null::timestamptz as finished_at
    from pgmq."q_${queue}" where ${tenant} order by msg_id desc limit ${String(LIMIT)})
    union all
    (select '${queue}', msg_id,
      case when message ? 'dead' then 'dead' else 'succeeded' end,
      read_ct, message ->> 'last_error', enqueued_at, archived_at
    from pgmq."a_${queue}" where ${tenant} order by msg_id desc limit ${String(LIMIT)})`;
}

/**
 * The organization's 50 latest job runs across every queue. pgmq grants its
 * tables to the service role only, so this reads as the database owner after
 * checking `audit.read`. A failed read throws, so it is never cached and Retry
 * reads again. `null` without an organization or the permission.
 */
export async function loadJobRuns(): Promise<readonly JobRunRow[] | null> {
  "use cache: private";

  const [{ session }, permissions] = await Promise.all([
    bsb.cached(),
    getPermissions(),
  ]);

  const tenant = tenantOf(session);

  if (!tenant || !can(permissions, JOBS_PERMISSION)) {
    return null;
  }

  const connection = postgres();

  if (!connection) {
    throw new Error("The jobs page needs a database URL");
  }

  const queues = await connection.admin.queryRaw<{ queue_name: string }>(
    "select queue_name from pgmq.list_queues() order by queue_name",
  );

  const names = queues
    .map((row) => row.queue_name)
    .filter((name) => QUEUE_NAME.test(name));

  if (names.length === 0) {
    return [];
  }

  const rows = await connection.admin.queryRaw<JobRunRecord>(
    `select * from (${names.map((name) => queueRuns(name, "$1")).join(" union all ")}) runs
     order by coalesce(finished_at, enqueued_at) desc
     limit ${String(LIMIT)}`,
    [tenant],
  );

  return rows.map((row) => ({
    queue: row.queue,
    id: Number(row.id),
    status: v.parse(JobRunStatus, row.status),
    attempts: row.attempts,
    lastError: row.last_error,
    enqueuedAt: row.enqueued_at.toISOString(),
    finishedAt: row.finished_at?.toISOString() ?? null,
  }));
}
