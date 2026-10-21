import type { WorkflowStartCall } from "better-supabase/blocks/workflows";
import type { WorkflowRunAs } from "better-supabase/workflow-sdk";

import { workflowStarter } from "better-supabase/workflow-sdk";

import { serviceBuilder } from "@/features/workflows/builder/builder-server";
import { scheduledWorkflows } from "@/features/workflows/workflow-definitions";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/**
 * The publisher a schedule runs as: its organization's owner, never the member
 * who created it. The sample steps check no permission keys.
 */
async function runAs(call: WorkflowStartCall): Promise<WorkflowRunAs | null> {
  if (call.tenant === undefined) {
    return null;
  }

  const owner = await bs
    .admin()
    .memberships.findFirst({
      select: ["userId"],
      where: { organizationId: call.tenant, role: "owner" },
    })
    .orThrow();

  return owner === null ? null : { publisher: owner.userId, permissions: [] };
}

/**
 * Starts due schedules (the sample workflows and builder graphs) and queued
 * admission requests. Call it every minute from a cron (Vercel Cron sends
 * `Authorization: Bearer $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  const secret = process.env["CRON_SECRET"];

  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const builder = serviceBuilder().triggers;

  const scheduled = builder.starter(
    workflowStarter(scheduledWorkflows, {
      runAs,
      args: (call, context) => {
        const rest: readonly unknown[] = Array.isArray(call.input)
          ? call.input
          : [];

        return [context, ...rest];
      },
    }),
  );

  const admitted = builder.starter(workflowStarter(scheduledWorkflows));
  const workflows = blocks(bs.admin().$client).workflows;

  const [schedules, admission] = await Promise.all([
    workflows.schedules.tick({ start: scheduled }).orThrow(),
    workflows.admission.tick({ start: admitted }).orThrow(),
  ]);

  return Response.json({ schedules, admission });
}
