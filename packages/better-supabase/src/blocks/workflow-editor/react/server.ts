import type {
  UseWorkflowEditorOptions,
  UseWorkflowCanvasRunOptions,
  WorkflowEditorState,
  WorkflowCanvasRunState,
} from "./index.ts";

export type {
  UseWorkflowEditorOptions,
  UseWorkflowCanvasRunOptions,
  WorkflowEditorState,
  WorkflowCanvasRunState,
} from "./index.ts";

/**
 * The `react-server` build of `useWorkflowEditor`: call
 * `builder.definitions.list()` instead.
 */
export const useWorkflowEditor: (
  options?: UseWorkflowEditorOptions,
) => WorkflowEditorState = () => {
  throw new Error(
    "better-supabase: useWorkflowEditor() runs in Client Components only. In Server Components call `builder.definitions.list()` instead.",
  );
};

/**
 * The `react-server` build of `useWorkflowCanvasRun`: call
 * `builder.nodeRuns.list()` instead.
 */
export const useWorkflowCanvasRun: (
  run: string | null,
  options?: UseWorkflowCanvasRunOptions,
) => WorkflowCanvasRunState = () => {
  throw new Error(
    "better-supabase: useWorkflowCanvasRun() runs in Client Components only. In Server Components call `builder.nodeRuns.list()` instead.",
  );
};
