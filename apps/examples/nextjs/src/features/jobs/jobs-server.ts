import "server-only";
import type { BetterPostgres } from "better-supabase/postgres";

import { QueueClient } from "@vercel/queue";
import {
  BLOCK_TICKS_QUEUE,
  blockTickSchema,
  createQueue,
  vercelQueueProvider,
} from "better-supabase/blocks/queue";
import * as v from "valibot";

import { env } from "@/env";

/** The queue the settings page's "Enqueue a test job" writes to. */
export const TEST_QUEUE = "settings_test";

/** The queue the audit page's export job for large ranges runs on. */
export const AUDIT_EXPORT_QUEUE = "audit_export";

/** What an audit export job needs; the filters keep the URL's text form. */
export const auditExportSchema = v.object({
  job: v.pipe(v.string(), v.uuid()),
  tenant: v.string(),
  userId: v.string(),
  from: v.nullable(v.string()),
  to: v.nullable(v.string()),
  actor: v.nullable(v.string()),
  type: v.nullable(v.string()),
  q: v.nullable(v.string()),
});

const queues = {
  [AUDIT_EXPORT_QUEUE]: auditExportSchema,
  [TEST_QUEUE]: v.object({ message: v.string() }),
  [BLOCK_TICKS_QUEUE]: blockTickSchema,
};

/** The Vercel Queues topic Vercel Schedules publishes block timers to. */
export const SCHEDULES_BRIDGE = "bsb_schedules";

/**
 * Jobs over a direct connection, as the queue and scheduler pair that
 * `JOBS_BACKEND` and `JOBS_SCHEDULER` pick. The block is installed with `{ api:
 * false }`, so its functions are service-role only and not on the Data API.
 *
 * - `sql` with `supabase`: Supabase Queues with Supabase Cron, the defaults.
 * - `sql` with `vercel`: the static schedules in `vercel.json` publish each block
 *   timer to `SCHEDULES_BRIDGE`, and `app/api/queues/schedules` enqueues it
 *   here for `app/api/jobs/drain`.
 * - `vercel`: Vercel Queues, and the route under `app/api/queues` runs each job;
 *   the runs table then stays empty, since it reads pgmq.
 */
export function jobsOn(connection: BetterPostgres) {
  return env.JOBS_BACKEND === "vercel"
    ? pushJobs
    : createQueue({ sql: connection.admin, queues });
}

/** Authenticates through the deployment's OIDC token, or `vercel env pull`. */
export const vercelQueue = new QueueClient();

/** Jobs on Vercel Queues; the route under `app/api/queues` runs them. */
export const pushJobs = createQueue({
  backend: vercelQueueProvider(vercelQueue),
  queues,
});

/** Pgmq queue names, which also name their tables (`pgmq.q_<name>`). */
export const QUEUE_NAME = /^[a-z0-9_]{1,47}$/;

/** Reading job runs is an audit task: the queues hold every member's work. */
export const JOBS_PERMISSION = "audit.read";
