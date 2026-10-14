import type {
  SavedViewLike,
  SavedViewsState,
  UseSavedViewsOptions,
} from "./index.ts";

export type {
  SavedViewLike,
  SavedViewsState,
  UseSavedViewsOptions,
} from "./index.ts";

/** The `react-server` build of `useSavedViews`: call `savedViews.list()` instead. */
export const useSavedViews: <V extends SavedViewLike>(
  options: UseSavedViewsOptions<V>,
) => SavedViewsState<V> = () => {
  throw new Error(
    "better-supabase: useSavedViews() runs in Client Components only. In Server Components call `savedViews.list()` instead.",
  );
};
