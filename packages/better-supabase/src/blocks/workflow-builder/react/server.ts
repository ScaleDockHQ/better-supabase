import type {
  UseWorkflowBuilderOptions,
  UseWorkflowCanvasRunOptions,
  WorkflowBuilderState,
  WorkflowCanvasRunState,
} from "./index.ts";

export type {
  UseWorkflowBuilderOptions,
  UseWorkflowCanvasRunOptions,
  WorkflowBuilderState,
  WorkflowCanvasRunState,
} from "./index.ts";

/** The `react-server` build of `useWorkflowBuilder`: call `builder.definitions.list()` instead. */
export const useWorkflowBuilder: (
  options?: UseWorkflowBuilderOptions,
) => WorkflowBuilderState = () => {
  throw new Error(
    "better-supabase: useWorkflowBuilder() runs in Client Components only. In Server Components call `builder.definitions.list()` instead.",
  );
};

/** The `react-server` build of `useWorkflowCanvasRun`: call `builder.nodeRuns.list()` instead. */
export const useWorkflowCanvasRun: (
  run: string | null,
  options?: UseWorkflowCanvasRunOptions,
) => WorkflowCanvasRunState = () => {
  throw new Error(
    "better-supabase: useWorkflowCanvasRun() runs in Client Components only. In Server Components call `builder.nodeRuns.list()` instead.",
  );
};
