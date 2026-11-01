import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type {
  Comment,
  Comments,
  ListCommentsOptions,
  NewComment,
} from "./comments.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";
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

/** The writes of the comments binding. */
export type CommentsWrites = {
  /** Adds a comment to the record's thread. */
  readonly add: RecordBindingWrite<Comments, NewComment, Comment>;
  /** Removes one comment; its author or a moderator. */
  readonly remove: RecordBindingWrite<Comments, RecordRowInput, boolean>;
};

/**
 * A record's comment thread, oldest first. The messaging events make it stale:
 * a record conversation's messages carry `conversationKind: "subject"`.
 */
export const commentsBinding: RecordBinding<
  Comments,
  readonly Comment[],
  ListCommentsOptions,
  CommentsOptimisticAction,
  CommentsWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "create" },
  load: (client: Comments, subject, options?: ListCommentsOptions) =>
    client.list({ subject, ...options }),
  count: (client: Comments, subjects) => client.counts(subjects),
  timeline: (comments) =>
    comments.flatMap((comment) =>
      comment.sentAt === undefined
        ? []
        : [
            {
              id: comment.id,
              kind: "comment",
              at: comment.sentAt,
              ...(comment.authorId === undefined
                ? {}
                : { actor: comment.authorId }),
              row: comment,
            },
          ],
    ),
  events: [
    "message.sent",
    "message.edited",
    "message.deleted",
    "message.pinned",
    "message.resolved",
  ],
  optimistic: commentsOptimistic,
  writes: {
    add: {
      input: commentInputSchema,
      run: (client: Comments, subject, input: NewComment) =>
        client.create({ subject, comment: input }),
    },
    remove: {
      input: recordRowInput,
      run: (client: Comments, _subject, { id }: RecordRowInput) =>
        client.remove(id),
    },
  },
});
