import { problemResponse } from "better-supabase";
import { vercelScheduleBridgeRoute } from "better-supabase/blocks/queue";

import { env } from "@/env";
import { requirePostgres } from "@/features/developer/postgres";
import { jobsOn, vercelQueue } from "@/features/jobs/jobs-server";

/** Acknowledges a run without enqueuing it. */
const skip = vercelQueue.handleCallback(() => undefined);

/**
 * The bridge from Vercel Schedules to Supabase Queues. The block timers in the
 * `schedules` of `vercel.json` publish to the `bsb_schedules` topic, and with
 * `JOBS_SCHEDULER=vercel` and `JOBS_BACKEND=sql` this route enqueues each run
 * on `block_ticks` once, for the drain. With the other pairs it acknowledges
 * the run and drops it, since Supabase Cron is the scheduler.
 */
export async function POST(request: Request): Promise<Response> {
  if (env.JOBS_SCHEDULER !== "vercel" || env.JOBS_BACKEND !== "sql") {
    return skip(request);
  }

  const connection = requirePostgres();

  if (!connection.ok) {
    return problemResponse(connection.error);
  }

  const bridge = vercelScheduleBridgeRoute(jobsOn(connection.data), {
    client: vercelQueue,
    onError: (error, run) => {
      console.error(`bsb_schedules ${run.name}: ${error.message}`);
    },
  });

  return bridge(request);
}
