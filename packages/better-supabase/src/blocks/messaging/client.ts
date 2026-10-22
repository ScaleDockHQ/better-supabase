import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicHandle, TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  ConversationKind,
  ConversationSummary,
  Message,
  MessageEdition,
  Messaging,
  NewMessage,
} from "./messaging.ts";

import { dbError } from "../../core/errors.ts";
import { err } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";
import { isRecord } from "../shared.ts";
import { conversationTopic } from "./rows.ts";

const TYPING_EVENT = "typing";

/** How often a held `setTyping(true)` broadcasts again. */
const TYPING_RESEND_MS = 3000;

export interface MessagesControllerOptions {
  readonly client: Pick<
    Messaging,
    | "list"
    | "replies"
    | "get"
    | "send"
    | "edit"
    | "remove"
    | "pin"
    | "resolve"
    | "markRead"
  >;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The conversation (or channel) to follow; the view waits without one. */
  readonly conversationId: string | null;
  /**
   * A thread's root message: the view shows its replies instead of the
   * conversation's top-level messages.
   */
  readonly threadId?: string | null;
  /** `blocks.messaging.options.topic`, default `messages`. */
  readonly topic?: string;
  /** Messages per page, default 50. */
  readonly limit?: number;
  /**
   * Moves the caller's read marker on load and on each new message; default
   * true.
   */
  readonly markRead?: boolean;
  /** How long a typing indicator lasts without a new broadcast, default 6000 ms. */
  readonly typingTimeout?: number;
}

export interface MessagesSnapshot {
  /** Oldest first; `undefined` until the first load. */
  readonly messages: readonly Message[] | undefined;
  /** Whether `loadOlder` may find more. */
  readonly hasOlder: boolean;
  /** The other people typing now, by user id. */
  readonly typing: readonly string[];
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

/** A reply, a rich-text document, mentions or files for `send`. */
export type MessageDraft = Omit<NewMessage, "body">;

export interface MessagesActions {
  /**
   * Sends a message, or a reply in the thread view; a failure is also kept in
   * `error`.
   */
  readonly send: (
    body: string,
    draft?: MessageDraft,
  ) => Promise<Result<Message>>;
  readonly edit: (
    id: string,
    edition: MessageEdition,
  ) => Promise<Result<Message>>;
  /** Deletes a message; it stays as a placeholder. */
  readonly remove: (id: string) => Promise<Result<boolean>>;
  readonly pin: (id: string, pinned?: boolean) => Promise<Result<Message>>;
  readonly resolve: (
    id: string,
    resolved?: boolean,
  ) => Promise<Result<Message>>;
  /** Loads the page before the oldest message shown. */
  readonly loadOlder: () => Promise<void>;
  /** Tells the others the caller is typing, or stopped. */
  readonly setTyping: (typing: boolean) => void;
  readonly markRead: () => Promise<void>;
  readonly refresh: () => Promise<void>;
}

export type MessagesController = Controller<MessagesSnapshot, MessagesActions>;

const order = (a: Message, b: Message): number => {
  const left = (a.sentAt ?? a.createdAt).epochMilliseconds;
  const right = (b.sentAt ?? b.createdAt).epochMilliseconds;

  if (left !== right) {
    return left - right;
  }

  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
};

/** `messages` with `incoming` added or replaced, oldest first. */
function merge(
  messages: readonly Message[],
  incoming: readonly Message[],
): readonly Message[] {
  const byId = new Map(messages.map((message) => [message.id, message]));

  for (const message of incoming) {
    byId.set(message.id, message);
  }

  return [...byId.values()].toSorted(order);
}

const text = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

/**
 * One conversation, or one thread, for the signed-in user: loads the latest
 * page, keeps it current from the conversation's Realtime pings, tracks who is
 * typing, and moves the read marker as messages arrive.
 */
export function createMessagesController(
  options: MessagesControllerOptions,
): MessagesController {
  const { client, conversationId } = options;
  const threadId = options.threadId ?? null;
  const limit = options.limit ?? 50;
  const autoRead = options.markRead ?? true;
  const typingTimeout = options.typingTimeout ?? 6000;

  return defineController<MessagesSnapshot, MessagesActions>(
    {
      messages: undefined,
      hasOlder: false,
      typing: [],
      status: "closed",
      error: undefined,
    },
    (state) => {
      let ticket = 0;
      let handle: TopicHandle | undefined;
      let me: string | undefined;
      let typingSentAt = 0;
      const typers = new Map<string, ReturnType<typeof setTimeout>>();

      const shows = (message: Message): boolean =>
        message.conversationId === conversationId &&
        (threadId === null
          ? message.threadId === undefined || message.broadcast
          : message.threadId === threadId);

      const page = (before?: Message) =>
        threadId === null
          ? client.list(conversationId ?? "", {
              limit,
              ...(before?.sentAt === undefined
                ? {}
                : { before: { sentAt: before.sentAt, id: before.id } }),
            })
          : client.replies(threadId, { limit });

      const markRead = async (): Promise<void> => {
        if (conversationId === null) {
          return;
        }

        await client.markRead(
          conversationId,
          threadId === null ? {} : { threadId },
        );
      };

      const put = (incoming: readonly Message[]): void => {
        state.set((current) => ({
          error: undefined,
          messages: merge(current.messages ?? [], incoming.filter(shows)),
        }));
      };

      const refresh = async (): Promise<void> => {
        if (conversationId === null) {
          return;
        }

        ticket += 1;
        const request = ticket;
        const result = await page();

        if (request !== ticket) {
          return;
        }

        if (!result.ok) {
          state.set({ error: result.error });

          return;
        }

        state.set({
          messages: merge([], result.data),
          hasOlder: threadId === null && result.data.length >= limit,
          error: undefined,
        });

        if (autoRead) {
          await markRead();
        }
      };

      const stopTyping = (userId: string): void => {
        clearTimeout(typers.get(userId));

        if (typers.delete(userId)) {
          state.set({ typing: [...typers.keys()] });
        }
      };

      const heard = (userId: string, typing: boolean): void => {
        if (userId === me) {
          return;
        }

        stopTyping(userId);

        if (typing) {
          typers.set(
            userId,
            setTimeout(() => {
              stopTyping(userId);
            }, typingTimeout),
          );
          state.set({ typing: [...typers.keys()] });
        }
      };

      const ping = async (event: string, payload: unknown): Promise<void> => {
        const data = isRecord(payload) ? payload : {};

        if (event === TYPING_EVENT) {
          const userId = text(data["userId"]);

          if (userId !== undefined) {
            heard(userId, data["typing"] !== false);
          }

          return;
        }

        const messageId = text(data["messageId"]);

        if (messageId === undefined) {
          return;
        }

        const result = await client.get(messageId);

        if (!result.ok || result.data === undefined) {
          return;
        }

        const message = result.data;

        if (message.authorId !== undefined) {
          stopTyping(message.authorId);
        }

        if (!shows(message)) {
          return;
        }

        put([message]);

        if (autoRead && event === "message" && message.authorId !== me) {
          await markRead();
        }
      };

      const written = (result: Result<Message>): Result<Message> => {
        if (result.ok) {
          // A load that started before the write would answer without it.
          ticket += 1;
          put([result.data]);
        } else {
          state.set({ error: result.error });
        }

        return result;
      };

      const actions: MessagesActions = {
        refresh,
        markRead,
        send: async (body, draft = {}) => {
          if (conversationId === null) {
            return err(dbError("invalid_input", "No conversation is open"));
          }

          typingSentAt = 0;
          handle?.send(TYPING_EVENT, {
            conversationId,
            userId: me,
            typing: false,
          });

          return written(
            await client.send(conversationId, {
              ...draft,
              ...(threadId === null || draft.parentId !== undefined
                ? {}
                : { parentId: threadId }),
              body,
            }),
          );
        },
        edit: async (id, edition) => written(await client.edit(id, edition)),
        remove: async (id) => {
          const result = await client.remove(id);

          if (result.ok) {
            const fresh = await client.get(id);

            if (fresh.ok && fresh.data !== undefined) {
              put([fresh.data]);
            }
          } else {
            state.set({ error: result.error });
          }

          return result;
        },
        pin: async (id, pinned = true) => written(await client.pin(id, pinned)),
        resolve: async (id, resolved = true) =>
          written(await client.resolve(id, resolved)),
        loadOlder: async () => {
          const oldest = state.get().messages?.[0];

          if (
            conversationId === null ||
            threadId !== null ||
            oldest === undefined
          ) {
            return;
          }

          const result = await page(oldest);

          if (!result.ok) {
            state.set({ error: result.error });

            return;
          }

          state.set((current) => ({
            messages: merge(current.messages ?? [], result.data),
            hasOlder: result.data.length >= limit,
          }));
        },
        setTyping: (typing) => {
          if (handle === undefined || me === undefined) {
            return;
          }

          const now = Date.now();

          if (typing && now - typingSentAt < TYPING_RESEND_MS) {
            return;
          }

          typingSentAt = typing ? now : 0;
          handle.send(TYPING_EVENT, { conversationId, userId: me, typing });
        },
      };

      return {
        actions,
        start: () =>
          conversationId === null
            ? undefined
            : whileSignedIn(options.auth, (userId) => {
                me = userId;
                void refresh();

                handle = options.ports.topic(
                  conversationTopic(conversationId, options.topic),
                  {
                    onMessage: (event, payload) => void ping(event, payload),
                    onRejoin: () => void refresh(),
                    onStatus: (status) => {
                      state.set({ status });
                    },
                  },
                );

                return () => {
                  handle?.leave();
                  handle = undefined;
                  me = undefined;

                  for (const timer of typers.values()) {
                    clearTimeout(timer);
                  }

                  typers.clear();
                  state.set({ typing: [] });
                };
              }),
      };
    },
  );
}

export interface ConversationsControllerOptions {
  readonly client: Pick<Messaging, "conversations">;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** Whether the caller acts in a tenant; the list waits without one. */
  readonly enabled: boolean;
  /** Only these kinds, such as `["channel"]`. */
  readonly kinds?: readonly ConversationKind[];
  readonly limit?: number;
  readonly topic?: string;
  /**
   * How many of the listed conversations to follow on Realtime for new
   * messages, default 50. Unread counts of the others change on `refresh`.
   */
  readonly watch?: number;
}

export interface ConversationsSnapshot {
  /** Latest message first, with unread counts; `undefined` until loaded. */
  readonly conversations: readonly ConversationSummary[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

export interface ConversationsActions {
  readonly refresh: () => Promise<void>;
}

export type ConversationsController = Controller<
  ConversationsSnapshot,
  ConversationsActions
>;

/**
 * The caller's conversations with their unread and mention counts, loaded again
 * when a message arrives in one of them.
 */
export function createConversationsController(
  options: ConversationsControllerOptions,
): ConversationsController {
  const watch = options.watch ?? 50;

  return defineController<ConversationsSnapshot, ConversationsActions>(
    { conversations: undefined, status: "closed", error: undefined },
    (state) => {
      let ticket = 0;
      const joined = new Map<string, TopicHandle>();

      const follow = (ids: readonly string[]): void => {
        const wanted = new Set(ids.slice(0, watch));

        for (const [id, handle] of joined) {
          if (!wanted.has(id)) {
            handle.leave();
            joined.delete(id);
          }
        }

        for (const id of wanted) {
          if (!joined.has(id)) {
            joined.set(
              id,
              options.ports.topic(conversationTopic(id, options.topic), {
                onMessage: (event) => {
                  if (event === "message") {
                    void refresh();
                  }
                },
                onRejoin: () => undefined,
                onStatus: (status) => {
                  state.set({ status });
                },
              }),
            );
          }
        }
      };

      const refresh = async (): Promise<void> => {
        if (!options.enabled) {
          return;
        }

        ticket += 1;
        const request = ticket;

        const result = await options.client.conversations({
          ...(options.kinds === undefined ? {} : { kinds: options.kinds }),
          ...(options.limit === undefined ? {} : { limit: options.limit }),
        });

        if (request !== ticket) {
          return;
        }

        if (result.ok) {
          state.set({ conversations: result.data, error: undefined });
          follow(result.data.map((conversation) => conversation.id));
        } else {
          state.set({ error: result.error });
        }
      };

      return {
        actions: { refresh },
        start: () =>
          options.enabled
            ? whileSignedIn(options.auth, () => {
                void refresh();

                return () => {
                  follow([]);
                };
              })
            : undefined,
      };
    },
  );
}
