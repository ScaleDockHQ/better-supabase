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
    case "cancelled": {
      return true;
    }

    case "queued":
    case "running":
    case "waiting": {
      return false;
    }

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
    case "completed": {
      return "default";
    }

    case "failed": {
      return "destructive";
    }

    case "cancelled": {
      return "outline";
    }

    case "queued":
    case "running":
    case "waiting": {
      return "secondary";
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

/** The ReUI badge variant for a run's status. */
export function statusBadge(
  status: WorkflowRunStatus,
):
  | "success-light"
  | "destructive-light"
  | "info-light"
  | "warning-light"
  | "secondary" {
  switch (status) {
    case "completed": {
      return "success-light";
    }

    case "failed": {
      return "destructive-light";
    }

    case "running": {
      return "info-light";
    }

    case "waiting": {
      return "warning-light";
    }

    case "cancelled":
    case "queued": {
      return "secondary";
    }

    default: {
      const unknown: never = status;

      return unknown;
    }
  }
}

/** `1.2 s`, `3 min 5 s` or `120 ms` for a duration in milliseconds. */
export function formatDuration(ms: number): string {
  if (ms < 1000) {
    return `${Math.round(ms)} ms`;
  }

  const seconds = ms / 1000;

  if (seconds < 60) {
    return `${seconds.toFixed(seconds < 10 ? 1 : 0)} s`;
  }

  const minutes = Math.floor(seconds / 60);
  const rest = Math.round(seconds - minutes * 60);

  return `${minutes} min ${rest} s`;
}
