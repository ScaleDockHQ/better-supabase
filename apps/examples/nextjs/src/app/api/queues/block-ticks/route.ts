import {
  BLOCK_TICKS_QUEUE,
  blockTickHandler,
  vercelQueueRoute,
} from "better-supabase/blocks/queue";

import { pushJobs, vercelQueue } from "@/features/jobs/jobs-server";
import {
  tickAdmission,
  tickSchedules,
} from "@/features/workflows/workflow-ticks";
import { bsb } from "@/lib/supabase/server";

let cachedAdmin: ReturnType<typeof bsb.admin> | undefined;

// The admin client needs SUPABASE_SECRET_KEY, which the release build doesn't
// have, so it is created on the first tick instead of when the module loads.
function getAdmin(): ReturnType<typeof bsb.admin> {
  cachedAdmin ??= bsb.admin();

  return cachedAdmin;
}

/**
 * Vercel Queues pushes each block timer here (the trigger is in `vercel.json`).
 * Every handler runs as the service role, and a failed run is retried.
 */
const ticks = blockTickHandler({
  "sequences.runDue": () => getAdmin().$blocks.sequences.runDue(),
  "workflows.schedules.tick": () => tickSchedules(),
  "workflows.admission.tick": () => tickAdmission(),
  "ai-schedules.tick": () => getAdmin().$blocks.aiSchedules.tick(),
  "sla.check": () => getAdmin().$blocks.sla.check(),
  "invoices.runDunning": () => getAdmin().$blocks.invoices.runDunning(),
  "risks.notifyDueReviews": () => getAdmin().$blocks.risks.notifyDueReviews(),
  "cases.notifyDueEffectiveness": () =>
    getAdmin().$blocks.cases.notifyDueEffectiveness(),
  "inspections.notifyOverdue": () =>
    getAdmin().$blocks.inspections.notifyOverdue(),
  "consents.expire": () => getAdmin().$blocks.consents.expire(),
  "care-plans.dueReviews": () => getAdmin().$blocks.carePlans.dueReviews(),
  "reminders.schedule": () => getAdmin().$blocks.reminders.schedule(),
  "content.publishDue": () => getAdmin().$blocks.content.publishDue(),
  "templates.recurring.schedule": () =>
    getAdmin().$blocks.templates.recurring.schedule(),
});

export const POST = vercelQueueRoute(pushJobs, {
  client: vercelQueue,
  handlers: { [BLOCK_TICKS_QUEUE]: ticks },
  onError: (error, delivery) => {
    console.error(`block_ticks ${delivery.messageId}: ${error.message}`);
  },
});
