import type { TagInputState, UseTagInputOptions } from "./index.ts";

export type { TagChange, TagInputState, UseTagInputOptions } from "./index.ts";

/** The `react-server` build of `useTagInput`: call `tags.list({ on })` instead. */
export const useTagInput: (
  options: UseTagInputOptions,
) => TagInputState = () => {
  throw new Error(
    "better-supabase: useTagInput() runs in Client Components only. In Server Components call `tags.list({ on })` instead.",
  );
};
