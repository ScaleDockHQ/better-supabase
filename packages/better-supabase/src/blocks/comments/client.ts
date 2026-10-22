import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { Comment, CommentEdit, Comments, NewComment } from "./comments.ts";

import { dbError } from "../../core/errors.ts";
import { err } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";
import { conversationTopic } from "../messaging/messaging.ts";
import { isRecord } from "../shared.ts";

const idOf = (payload: unknown, key: string): string | undefined => {
  const value = isRecord(payload) ? payload[key] : undefined;

  return typeof value === "string" && value !== "" ? value : undefined;
};

export interface CommentsControllerOptions {
  readonly client: Pick<
    Comments,
    | "list"
    | "get"
    | "create"
    | "edit"
    | "remove"
    | "resolve"
    | "pin"
    | "conversation"
  >;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The subject whose thread to follow; the thread waits without one. */
  readonly subject: SubjectRef | null;
  /**
   * `blocks.messaging.options.topic`, default `messages`: the thread joins the
   * record conversation's private topic and fetches the comment each ping
   * names, with its thread's root for the reply count. `null` turns Realtime
   * off, so the thread loads again after its own writes only.
   */
  readonly topic?: string | null;
  /** The most comments to load, default 100, at most 500. */
  readonly limit?: number;
}

export interface CommentsSnapshot {
  /**
   * The thread, oldest first, deleted comments as placeholders; `undefined`
   * until the first load.
   */
  readonly comments: readonly Comment[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

/** A reply, a rich-text document, an anchor, mentions or files for `add`. */
export type CommentDraft = Omit<NewComment, "body">;

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
  /** Resolves a thread by its root comment, or opens it again. */
  readonly resolve: (
    id: string,
    resolved?: boolean,
  ) => Promise<Result<Comment>>;
  readonly pin: (id: string, pinned?: boolean) => Promise<Result<Comment>>;
  readonly refresh: () => Promise<void>;
}

export type CommentsController = Controller<CommentsSnapshot, CommentsActions>;

/**
 * One subject's comment thread for the signed-in user: loads it, keeps it
 * current after its own writes, and fetches the one comment each ping on the
 * record conversation's topic names (joined once the record has a
 * conversation), so a busy thread never reloads whole.
 */
export function createCommentsController(
  options: CommentsControllerOptions,
): CommentsController {
  const { client, subject } = options;
  const topic = options.topic === undefined ? "messages" : options.topic;

  return defineController<CommentsSnapshot, CommentsActions>(
    { comments: undefined, status: "closed", error: undefined },
    (state) => {
      let ticket = 0;
      let leave: (() => void) | undefined;
      let watching = false;

      const refresh = async (): Promise<void> => {
        if (subject === null) {
          return;
        }

        ticket += 1;
        const request = ticket;

        const result = await client.list(
          subject,
          options.limit === undefined ? {} : { limit: options.limit },
        );

        if (request !== ticket) {
          return;
        }

        state.set(
          result.ok
            ? { comments: result.data, error: undefined }
            : { error: result.error },
        );
      };

      const merge = (comment: Comment): void => {
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

      const replace = (comment: Comment): void => {
        // A load that started before the write would answer without it.
        ticket += 1;
        merge(comment);
      };

      const fetch = async (id: string): Promise<void> => {
        const result = await client.get(id);

        // Before the first load answers, that load brings the comment.
        if (result.ok && state.get().comments !== undefined) {
          merge(result.data);
        }
      };

      const ping = async (payload: unknown): Promise<void> => {
        const messageId = idOf(payload, "messageId");

        if (messageId === undefined) {
          return;
        }

        const threadId = idOf(payload, "threadId");

        await Promise.all([
          fetch(messageId),
          ...(threadId === undefined || threadId === messageId
            ? []
            : [fetch(threadId)]),
        ]);
      };

      const join = (conversationId: string): void => {
        if (topic === null || !watching || leave !== undefined) {
          return;
        }

        leave = options.ports.topic(conversationTopic(conversationId, topic), {
          onMessage: (_event, payload) => void ping(payload),
          onRejoin: () => void refresh(),
          onStatus: (status) => {
            state.set({ status });
          },
        }).leave;
      };

      const watch = async (): Promise<void> => {
        if (subject === null || topic === null) {
          return;
        }

        const found = await client.conversation(subject);

        if (found.ok && found.data !== undefined) {
          join(found.data);
        }
      };

      const write = async (
        result: PromiseLike<Result<Comment>>,
      ): Promise<Result<Comment>> => {
        const settled = await result;

        if (settled.ok) {
          replace(settled.data);
          join(settled.data.conversationId);
        } else {
          state.set({ error: settled.error });
        }

        return settled;
      };

      return {
        actions: {
          refresh,
          add: (body, draft = {}) =>
            subject === null
              ? Promise.resolve(
                  err(dbError("invalid_input", "No subject is open")),
                )
              : write(client.create(subject, { ...draft, body })),
          edit: (id, edit) => write(client.edit(id, edit)),
          resolve: (id, resolved) => write(client.resolve(id, resolved)),
          pin: (id, pinned) => write(client.pin(id, pinned)),
          remove: async (id) => {
            const result = await client.remove(id);

            if (result.ok) {
              await fetch(id);
            } else {
              state.set({ error: result.error });
            }

            return result;
          },
        },
        start: () =>
          subject === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                watching = true;
                void refresh();
                void watch();

                return () => {
                  watching = false;
                  leave?.();
                  leave = undefined;
                };
              }),
      };
    },
  );
}
