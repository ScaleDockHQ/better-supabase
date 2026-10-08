import { workflowStarter } from "better-supabase/workflow-sdk";

import { serviceBuilder } from "@/features/workflows/builder/builder-server";
import { scheduledWorkflows } from "@/features/workflows/workflow-definitions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/**
 * Starts due schedules (the sample workflows and builder graphs) and queued
 * admission requests. Call it every minute
 * from a cron (Vercel Cron sends `Authorization: Bearer $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  const secret = process.env["CRON_SECRET"];
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }
  const start = serviceBuilder().triggers.starter(
    workflowStarter(scheduledWorkflows),
  );
  const workflows = blocks(bs.admin().$client).workflows;
  const [schedules, admission] = await Promise.all([
    workflows.schedules.tick({ start }).orThrow(),
    workflows.admission.tick({ start }).orThrow(),
  ]);
  return Response.json({ schedules, admission });
}
