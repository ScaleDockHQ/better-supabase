import { vercelQueueRoute } from "better-supabase/blocks/queue";

import { runAuditExport } from "@/features/audit/audit-export-job";
import {
  AUDIT_EXPORT_QUEUE,
  pushJobs,
  vercelQueue,
} from "@/features/jobs/jobs-server";

/**
 * Vercel Queues pushes each `audit_export` message here (the trigger is in
 * `vercel.json`). A failed export comes back and runs again from the start.
 */
export const POST = vercelQueueRoute(pushJobs, {
  client: vercelQueue,
  handlers: { [AUDIT_EXPORT_QUEUE]: (payload) => runAuditExport(payload) },
  onError: (error, delivery) => {
    console.error(`audit_export ${delivery.messageId}: ${error.message}`);
  },
});
