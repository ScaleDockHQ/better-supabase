import { BLOCK_TICKS_QUEUE } from "better-supabase/blocks/queue";
import { connection } from "next/server";

import { env } from "@/env";
import { requirePostgres } from "@/features/developer/postgres";
import { blockTicks } from "@/features/jobs/block-ticks";
import { jobsOn } from "@/features/jobs/jobs-server";

/**
 * Runs the block timers waiting on Supabase Queues. The `jobs-drain` schedule
 * in `vercel.json` calls it every minute with `Authorization: Bearer
 * $CRON_SECRET`. With `JOBS_BACKEND=vercel` the timers are pushed to
 * `app/api/queues/block-ticks` instead, so there is nothing to drain.
 */
export async function GET(request: Request): Promise<Response> {
  // Without a request-time API, Next.js runs this handler at build time.
  await connection();
  const postgres = requirePostgres();

  if (env.JOBS_BACKEND !== "sql" || !postgres.ok) {
    return new Response(null, { status: 204 });
  }

  const drain = jobsOn(postgres.data).drainRoute({
    secret: env.CRON_SECRET,
    handlers: { [BLOCK_TICKS_QUEUE]: blockTicks },
    onError: (error, job) => {
      console.error(`drain ${String(job?.id ?? "")}: ${error.message}`);
    },
  });

  return drain(request);
}
