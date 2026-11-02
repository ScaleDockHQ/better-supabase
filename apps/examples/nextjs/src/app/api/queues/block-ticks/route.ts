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

const admin = bsb.admin();

/**
 * Vercel Queues pushes each block timer here (the trigger is in `vercel.json`).
 * Every handler runs as the service role, and a failed run is retried.
 */
const ticks = blockTickHandler({
  "sequences.runDue": () => admin.$blocks.sequences.runDue(),
  "workflows.schedules.tick": () => tickSchedules(),
  "workflows.admission.tick": () => tickAdmission(),
  "ai-schedules.tick": () => admin.$blocks.aiSchedules.tick(),
  "sla.check": () => admin.$blocks.sla.check(),
  "invoices.runDunning": () => admin.$blocks.invoices.runDunning(),
  "risks.notifyDueReviews": () => admin.$blocks.risks.notifyDueReviews(),
  "cases.notifyDueEffectiveness": () =>
    admin.$blocks.cases.notifyDueEffectiveness(),
  "inspections.notifyOverdue": () => admin.$blocks.inspections.notifyOverdue(),
  "consents.expire": () => admin.$blocks.consents.expire(),
  "care-plans.dueReviews": () => admin.$blocks.carePlans.dueReviews(),
  "reminders.schedule": () => admin.$blocks.reminders.schedule(),
  "content.publishDue": () => admin.$blocks.content.publishDue(),
  "templates.recurring.schedule": () =>
    admin.$blocks.templates.recurring.schedule(),
});

export const POST = vercelQueueRoute(pushJobs, {
  client: vercelQueue,
  handlers: { [BLOCK_TICKS_QUEUE]: ticks },
  onError: (error, delivery) => {
    console.error(`block_ticks ${delivery.messageId}: ${error.message}`);
  },
});
