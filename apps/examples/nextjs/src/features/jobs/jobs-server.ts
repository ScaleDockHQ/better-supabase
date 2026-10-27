import "server-only";
import type { BetterPostgres } from "better-supabase/postgres";

import { QueueClient } from "@vercel/queue";
import { createQueue, vercelQueueProvider } from "better-supabase/blocks/queue";
import * as v from "valibot";

import { env } from "@/env";

/** The queue the settings page's "Enqueue a test job" writes to. */
export const TEST_QUEUE = "settings_test";

const queues = { [TEST_QUEUE]: v.object({ message: v.string() }) };

/**
 * Jobs over a direct connection: the block is installed with `{ api: false }`,
 * so its functions are service-role only and not on the Data API. With
 * `JOBS_BACKEND=vercel` they go to Vercel Queues instead, and the route under
 * `app/api/queues` runs them; the runs table then stays empty, since it reads
 * pgmq.
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
