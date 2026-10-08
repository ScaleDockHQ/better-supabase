import type { WorkflowRunStatus } from "better-supabase/blocks/workflows";

/**
 * The function name in a Workflow SDK definition such as
 * `workflow//./src/features/workflows/workflow-definitions//onboardingDrip`.
 */
export function workflowName(definition: string): string {
  return definition.split("//").at(-1) ?? definition;
}

export function isExpenseApproval(definition: string): boolean {
  return workflowName(definition) === "expenseApproval";
}

export function isFinished(status: WorkflowRunStatus): boolean {
  switch (status) {
    case "completed":
    case "failed":
    case "cancelled":
      return true;
    case "queued":
    case "running":
    case "waiting":
      return false;
    default: {
      const unknown: never = status;
      return unknown;
    }
  }
}

export function statusVariant(
  status: WorkflowRunStatus,
): "default" | "secondary" | "destructive" | "outline" {
  switch (status) {
    case "completed":
      return "default";
    case "failed":
      return "destructive";
    case "cancelled":
      return "outline";
    case "queued":
    case "running":
    case "waiting":
      return "secondary";
    default: {
      const unknown: never = status;
      return unknown;
    }
  }
}
