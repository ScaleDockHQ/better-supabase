import "server-only";
import type { WorkflowStartCall } from "better-supabase/blocks/workflows";
import type { WorkflowRunAs } from "better-supabase/workflow-sdk";

import { workflowStarter } from "better-supabase/workflow-sdk";

import { serviceBuilder } from "@/features/workflows/builder/builder-server";
import { scheduledWorkflows } from "@/features/workflows/workflow-definitions";
import { bsb } from "@/lib/supabase/server";

/**
 * The publisher a schedule runs as: its organization's owner, never the member
 * who created it. The sample steps check no permission keys.
 */
async function runAs(call: WorkflowStartCall): Promise<WorkflowRunAs | null> {
  if (call.tenant === undefined) {
    return null;
  }

  const members = await bsb
    .admin()
    .$rpc("organization_members", { organization: call.tenant })
    .orThrow();

  const owner = members.find((member) => member.role === "owner")?.userId;

  return owner ? { publisher: owner, permissions: [] } : null;
}

/** Starts the due schedules: the sample workflows and the builder graphs. */
export function tickSchedules() {
  const start = serviceBuilder().triggers.starter(
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

  return bsb.admin().workflows.schedules.tick({ start });
}

/** Starts the queued admission requests whose key has room. */
export function tickAdmission() {
  const start = serviceBuilder().triggers.starter(
    workflowStarter(scheduledWorkflows),
  );

  return bsb.admin().workflows.admission.tick({ start });
}
