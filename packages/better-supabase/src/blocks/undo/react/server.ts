import type { UndoStack, UseUndoStackOptions } from "./index.ts";

export type { UndoEntry, UndoStack, UseUndoStackOptions } from "./index.ts";

/**
 * The `react-server` build of `useUndoStack`: apply a token with `createUndo()`
 * instead.
 */
export const useUndoStack: (options: UseUndoStackOptions) => UndoStack = () => {
  throw new Error(
    "better-supabase: useUndoStack() runs in Client Components only. In Server Components apply a token with `createUndo().apply(token)` instead.",
  );
};
