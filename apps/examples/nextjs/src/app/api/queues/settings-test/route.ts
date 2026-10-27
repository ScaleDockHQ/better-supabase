import { vercelQueueRoute } from "better-supabase/blocks/queue";

import { pushJobs, TEST_QUEUE, vercelQueue } from "@/features/jobs/jobs-server";

/**
 * Vercel Queues pushes each `settings_test` message here (the trigger is in
 * `vercel.json`). A failed run comes back after 30 seconds; the fifth failure
 * is acknowledged and dropped.
 */
export const POST = vercelQueueRoute(pushJobs, {
  client: vercelQueue,
  handlers: {
    [TEST_QUEUE]: (payload, job) => {
      console.info(`settings_test job ${String(job.id)}: ${payload.message}`);
    },
  },
  onError: (error, delivery) => {
    console.error(`settings_test ${delivery.messageId}: ${error.message}`);
  },
});
