import "server-only";
import { blockTickHandler } from "better-supabase/blocks/queue";

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
 * Runs each block timer by its manifest name (`<block>.<timer>`), as the
 * `block_ticks` handler of the Vercel Queues route and the drain. Every handler
 * runs as the service role, and a failed run is retried.
 */
export const blockTicks = blockTickHandler({
  "sequences.run-due": () => getAdmin().$blocks.sequences.runDue(),
  "workflows.tick": async () => {
    const fired = await tickSchedules();

    return fired.ok ? tickAdmission() : fired;
  },
  "ai-schedules.tick": () => getAdmin().$blocks.aiSchedules.tick(),
  "sla.check": () => getAdmin().$blocks.sla.check(),
  "invoices.dunning": () => getAdmin().$blocks.invoices.runDunning(),
  "risks.review-due": () => getAdmin().$blocks.risks.notifyDueReviews(),
  "cases.effectiveness-due": () =>
    getAdmin().$blocks.cases.notifyDueEffectiveness(),
  "inspections.overdue": () => getAdmin().$blocks.inspections.notifyOverdue(),
  "consents.expire": () => getAdmin().$blocks.consents.expire(),
  "care-plans.reviews": () => getAdmin().$blocks.carePlans.dueReviews(),
  "reminders.schedule": () => getAdmin().$blocks.reminders.schedule(),
  "content.publish": () => getAdmin().$blocks.content.publishDue(),
  "templates.recurring": () =>
    getAdmin().$blocks.templates.recurring.schedule(),
});
