import { workflowStarter } from "better-supabase/workflow-sdk";

import { scheduledWorkflows } from "@/features/workflows/workflow-definitions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

const start = workflowStarter(scheduledWorkflows);

/**
 * Starts due schedules and queued admission requests. Call it every minute
 * from a cron (Vercel Cron sends `Authorization: Bearer $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  const secret = process.env["CRON_SECRET"];
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }
  const workflows = blocks(bs.admin().$client).workflows;
  const [schedules, admission] = await Promise.all([
    workflows.schedules.tick({ start }).orThrow(),
    workflows.admission.tick({ start }).orThrow(),
  ]);
  return Response.json({ schedules, admission });
}
