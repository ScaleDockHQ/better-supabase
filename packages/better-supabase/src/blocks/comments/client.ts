import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { Comment, CommentEdit, Comments, NewComment } from "./comments.ts";

import { dbError } from "../../core/errors.ts";
import { err } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";

export interface CommentsControllerOptions {
  readonly client: Pick<Comments, "list" | "create" | "edit" | "remove">;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The organization; the thread waits without one. */
  readonly organizationId: string | null;
  readonly subjectType: string;
  readonly subjectId: string;
  /**
   * A private topic that hears of new comments on the subject, such as a
   * `realtime-tables` topic on the comments table. Each message loads the
   * thread again. Default `null`: the thread loads again after its own
   * writes only.
   */
  readonly topic?: string | null;
  /** The most comments to load, default 100, at most 500. */
  readonly limit?: number;
}

export interface CommentsSnapshot {
  /** The thread, oldest first, deleted comments as placeholders; `undefined` until the first load. */
  readonly comments: readonly Comment[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

/** A reply, a rich-text document or explicit mentions for `add`. */
export type CommentDraft = Pick<
  NewComment,
  "document" | "mentions" | "parentId"
>;

export interface CommentsActions {
  /** Posts a comment on the subject; a failure is also kept in `error`. */
  readonly add: (
    body: string,
    draft?: CommentDraft,
  ) => Promise<Result<Comment>>;
  /** Edits one of the caller's comments. */
  readonly edit: (id: string, edit: CommentEdit) => Promise<Result<Comment>>;
  /** Soft-deletes a comment: it stays in the thread as a placeholder. */
  readonly remove: (id: string) => Promise<Result<boolean>>;
  readonly refresh: () => Promise<void>;
}

export type CommentsController = Controller<CommentsSnapshot, CommentsActions>;

/**
 * One subject's comment thread for the signed-in user: loads it, keeps it
 * current after `add`, `edit` and `remove`, and loads it again for each
 * message on `topic`.
 */
export function createCommentsController(
  options: CommentsControllerOptions,
): CommentsController {
  const { client, organizationId, subjectType, subjectId } = options;
  const topic = options.topic ?? null;
  return defineController<CommentsSnapshot, CommentsActions>(
    { comments: undefined, status: "closed", error: undefined },
    (state) => {
      let ticket = 0;
      const refresh = async (): Promise<void> => {
        if (organizationId === null) return;
        const request = ++ticket;
        const result = await client.list(
          organizationId,
          subjectType,
          subjectId,
          options.limit === undefined ? {} : { limit: options.limit },
        );
        if (request !== ticket) return;
        state.set(
          result.ok
            ? { comments: result.data, error: undefined }
            : { error: result.error },
        );
      };
      const replace = (comment: Comment): void => {
        // A load that started before the write would answer without it.
        ticket += 1;
        state.set((current) => {
          const comments = current.comments ?? [];
          return {
            error: undefined,
            comments: comments.some((each) => each.id === comment.id)
              ? comments.map((each) =>
                  each.id === comment.id ? comment : each,
                )
              : [...comments, comment],
          };
        });
      };
      return {
        actions: {
          refresh,
          add: async (body, draft = {}) => {
            if (organizationId === null)
              return err(dbError("invalid_input", "No organization is active"));
            const result = await client.create({
              ...draft,
              organizationId,
              subjectType,
              subjectId,
              body,
            });
            if (result.ok) replace(result.data);
            else state.set({ error: result.error });
            return result;
          },
          edit: async (id, edit) => {
            const result = await client.edit(id, edit);
            if (result.ok) replace(result.data);
            else state.set({ error: result.error });
            return result;
          },
          remove: async (id) => {
            const result = await client.remove(id);
            if (result.ok) await refresh();
            else state.set({ error: result.error });
            return result;
          },
        },
        start: () =>
          organizationId === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                void refresh();
                if (topic === null) return;
                const { leave } = options.ports.topic(topic, {
                  onMessage: () => void refresh(),
                  onRejoin: () => void refresh(),
                  onStatus: (status) => {
                    state.set({ status });
                  },
                });
                return leave;
              }),
      };
    },
  );
}
