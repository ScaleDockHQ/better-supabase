import type {
  UseWorkflowRunOptions,
  UseWorkflowRunsOptions,
  WorkflowRunState,
  WorkflowRunsState,
} from "./index.ts";

export type {
  UseWorkflowRunOptions,
  UseWorkflowRunsOptions,
  WorkflowRunState,
  WorkflowRunsState,
} from "./index.ts";

/** The `react-server` build of `useWorkflowRuns`: call `workflows.runs.list()` instead. */
export const useWorkflowRuns: (
  options?: UseWorkflowRunsOptions,
) => WorkflowRunsState = () => {
  throw new Error(
    "better-supabase: useWorkflowRuns() runs in Client Components only. In Server Components call `workflows.runs.list()` instead.",
  );
};

/** The `react-server` build of `useWorkflowRun`: call `workflows.runs.get()` instead. */
export const useWorkflowRun: (
  run: string | null,
  options?: UseWorkflowRunOptions,
) => WorkflowRunState = () => {
  throw new Error(
    "better-supabase: useWorkflowRun() runs in Client Components only. In Server Components call `workflows.runs.get()` instead.",
  );
};
