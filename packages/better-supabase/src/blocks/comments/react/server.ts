import type { CommentsState, UseCommentsOptions } from "./index.ts";

export type {
  CommentDraft,
  CommentsState,
  UseCommentsOptions,
} from "./index.ts";

/** The `react-server` build of `useComments`: call `comments.list()` instead. */
export const useComments: (
  options: UseCommentsOptions,
) => CommentsState = () => {
  throw new Error(
    "better-supabase: useComments() runs in Client Components only. In Server Components call `comments.list()` instead.",
  );
};
