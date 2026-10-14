import type { ReactionsState, UseReactionsOptions } from "./index.ts";

export type { ReactionsState, UseReactionsOptions } from "./index.ts";

/** The `react-server` build of `useReactions`: call `reactions.summary()` instead. */
export const useReactions: (
  options: UseReactionsOptions,
) => ReactionsState = () => {
  throw new Error(
    "better-supabase: useReactions() runs in Client Components only. In Server Components call `reactions.summary()` instead.",
  );
};
