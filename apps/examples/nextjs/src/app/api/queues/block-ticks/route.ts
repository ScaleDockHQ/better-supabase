import {
  BLOCK_TICKS_QUEUE,
  vercelQueueRoute,
} from "better-supabase/blocks/queue";

import { blockTicks } from "@/features/jobs/block-ticks";
import { pushJobs, vercelQueue } from "@/features/jobs/jobs-server";

/**
 * Vercel Queues pushes each block timer here (the trigger is in `vercel.json`).
 * Every handler runs as the service role, and a failed run is retried.
 */
export const POST = vercelQueueRoute(pushJobs, {
  client: vercelQueue,
  handlers: { [BLOCK_TICKS_QUEUE]: blockTicks },
  onError: (error, delivery) => {
    console.error(`block_ticks ${delivery.messageId}: ${error.message}`);
  },
});
