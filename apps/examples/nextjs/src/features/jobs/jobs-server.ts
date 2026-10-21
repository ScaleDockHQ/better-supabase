import "server-only";
import type { BetterPostgres } from "better-supabase/postgres";

import { createJobs } from "better-supabase/blocks/jobs";
import * as v from "valibot";

/** The queue the settings page's "Enqueue a test job" writes to. */
export const TEST_QUEUE = "settings_test";

const queues = { [TEST_QUEUE]: v.object({ message: v.string() }) };

/**
 * Jobs over a direct connection: the block is installed with `{ api: false }`,
 * so its functions are service-role only and not on the Data API.
 */
export function jobsOn(connection: BetterPostgres) {
  return createJobs({ sql: connection.admin, queues });
}

/** Pgmq queue names, which also name their tables (`pgmq.q_<name>`). */
export const QUEUE_NAME = /^[a-z0-9_]{1,47}$/;

/** Reading job runs is an audit task: the queues hold every member's work. */
export const JOBS_PERMISSION = "audit.read";
