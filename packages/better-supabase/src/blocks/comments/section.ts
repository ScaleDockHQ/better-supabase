import type { Section } from "../sections.ts";
import type { Comment, Comments, ListCommentsOptions } from "./comments.ts";

import { defineSection } from "../sections.ts";

/** A pending write to a thread, for `useOptimistic`. */
export type CommentsOptimisticAction =
  | { readonly type: "add"; readonly comment: Comment }
  | { readonly type: "edit"; readonly id: string; readonly body: string }
  | { readonly type: "remove"; readonly id: string };

/**
 * The thread with a pending write applied: `add` appends (or replaces the
 * comment with the same id), `edit` changes the body, `remove` takes it out.
 */
export function commentsOptimistic(
  state: readonly Comment[],
  action: CommentsOptimisticAction,
): readonly Comment[] {
  switch (action.type) {
    case "add": {
      return [
        ...state.filter((comment) => comment.id !== action.comment.id),
        action.comment,
      ];
    }

    case "edit": {
      return state.map((comment) =>
        comment.id === action.id ? { ...comment, body: action.body } : comment,
      );
    }

    case "remove": {
      return state.filter((comment) => comment.id !== action.id);
    }

    default: {
      const never: never = action;

      return never;
    }
  }
}

/** A record's comment thread, oldest first. */
export const commentsSection: Section<
  Comments,
  readonly Comment[],
  ListCommentsOptions,
  CommentsOptimisticAction
> = defineSection({
  permissions: { read: "read", write: "create" },
  load: (client: Comments, subject, options?: ListCommentsOptions) =>
    client.list(subject, options),
  count: (client: Comments, subjects) => client.counts(subjects),
  events: ["comment.created", "comment.deleted"],
  optimistic: commentsOptimistic,
});
