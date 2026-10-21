import type { Section, SectionRowInput, SectionWrite } from "../sections.ts";
import type {
  Comment,
  Comments,
  ListCommentsOptions,
  NewComment,
} from "./comments.ts";

import { defineSection, sectionRowInput } from "../sections.ts";
import { commentInputSchema } from "./schemas.ts";

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

/** The writes of the comments section. */
export type CommentsWrites = {
  /** Adds a comment to the record's thread. */
  readonly add: SectionWrite<Comments, NewComment, Comment>;
  /** Removes one comment; its author or a moderator. */
  readonly remove: SectionWrite<Comments, SectionRowInput, boolean>;
};

/** A record's comment thread, oldest first. */
export const commentsSection: Section<
  Comments,
  readonly Comment[],
  ListCommentsOptions,
  CommentsOptimisticAction,
  CommentsWrites
> = defineSection({
  permissions: { read: "read", write: "create" },
  load: (client: Comments, subject, options?: ListCommentsOptions) =>
    client.list(subject, options),
  count: (client: Comments, subjects) => client.counts(subjects),
  events: ["comment.created", "comment.deleted"],
  optimistic: commentsOptimistic,
  writes: {
    add: {
      input: commentInputSchema,
      run: (client: Comments, subject, input: NewComment) =>
        client.create(subject, input),
    },
    remove: {
      input: sectionRowInput,
      run: (client: Comments, _subject, { id }: SectionRowInput) =>
        client.remove(id),
    },
  },
});
