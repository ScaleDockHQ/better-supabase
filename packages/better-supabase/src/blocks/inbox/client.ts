import type { StoragePort } from "../../client/ports.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";

import { defineController, whileSignedIn } from "../controller.ts";

/** Loads one list, e.g. a server action that calls `inbox.conversations.list()`. */
export type InboxSource<T> = () => Promise<readonly T[]>;

export interface InboxListSnapshot<T> {
  /** `undefined` until the first load. */
  readonly items: readonly T[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: unknown;
}

export interface InboxListActions {
  readonly refresh: () => Promise<void>;
}

interface Ports {
  readonly topic: TopicPort;
}

export interface InboxControllerOptions<T> {
  readonly auth: AuthPort;
  readonly ports: Ports;
  /** The organization; the controller joins `inbox:org:<id>`. `null` waits. */
  readonly organizationId: string | null;
  readonly load: InboxSource<T>;
  /**
   * `blockConfig.inbox.options.topic` from `blocks.generated.ts`. Defaults to
   * `inbox`.
   */
  readonly topic?: string;
  /** Runs for each broadcast, e.g. to show a toast for `message`. */
  readonly onMessage?: (event: string, payload: unknown) => void;
}

export type InboxController<T> = Controller<
  InboxListSnapshot<T>,
  InboxListActions
>;

function loader<T>(
  load: InboxSource<T>,
  state: { readonly set: (patch: Partial<InboxListSnapshot<T>>) => void },
): () => Promise<void> {
  return async () => {
    try {
      state.set({ items: await load(), error: undefined });
    } catch (cause) {
      state.set({ error: cause });
    }
  };
}

/**
 * The staff view of an organization's conversations, kept current: loads, then
 * loads again after each ping on `inbox:org:<id>` and on rejoin.
 */
export function createInboxController<T>(
  options: InboxControllerOptions<T>,
): InboxController<T> {
  const topic =
    options.organizationId === null
      ? null
      : `${options.topic ?? "inbox"}:org:${options.organizationId}`;

  return defineController<InboxListSnapshot<T>, InboxListActions>(
    { items: undefined, status: "closed", error: undefined },
    (state) => {
      const refresh = loader(options.load, state);

      return {
        actions: { refresh },
        start: () => {
          if (topic === null) {
            return;
          }

          return whileSignedIn(options.auth, () => {
            void refresh();

            return options.ports.topic(topic, {
              onMessage: (event, payload) => {
                options.onMessage?.(event, payload);
                void refresh();
              },
              onRejoin: () => void refresh(),
              onStatus: (status) => {
                state.set({ status });
              },
            }).leave;
          });
        },
      };
    },
  );
}

export interface ConversationSnapshot<T> extends InboxListSnapshot<T> {
  /** User ids typing now, the caller left out. */
  readonly typing: readonly string[];
}

export interface ConversationActions extends InboxListActions {
  /** Tells the others the caller is typing; call it on input, throttled. */
  readonly setTyping: (typing: boolean) => void;
}

export interface ConversationControllerOptions<T extends Identified> {
  readonly auth: AuthPort;
  readonly ports: Ports;
  /** `null` waits, e.g. before the widget opens a conversation. */
  readonly conversationId: string | null;
  /** The messages, oldest first: on start and after a rejoin. */
  readonly load: InboxSource<T>;
  /**
   * One message after a ping, e.g. a server action that calls
   * `inbox.messages.get(id)`; `null` when the caller cannot read it.
   */
  readonly get: (messageId: string) => Promise<T | null>;
  /**
   * `blockConfig.messaging.options.topic` from `blocks.generated.ts`. Defaults
   * to `messages`.
   */
  readonly topic?: string;
  /** Runs for the other pings, such as `conversation` and `read`. */
  readonly onEvent?: (event: string, payload: unknown) => void;
  /** How long a typing ping counts. Defaults to 5000 ms. */
  readonly typingMs?: number;
}

/** What the conversation controller needs of a message. */
export interface Identified {
  readonly id: string;
}

export type ConversationController<T extends Identified> = Controller<
  ConversationSnapshot<T>,
  ConversationActions
>;

const NO_TYPERS: readonly string[] = [];

const textOf = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

/** `items` with `message` replaced in place, or added last. */
function upsert<T extends Identified>(
  items: readonly T[],
  message: T,
): readonly T[] {
  const at = items.findIndex((item) => item.id === message.id);

  return at === -1 ? [...items, message] : items.with(at, message);
}

/**
 * One conversation's messages, kept current over the messaging topic
 * `messages:<id>`: each ping fetches the one message it names, so the thread
 * never reloads on a change. Typing pings go both ways between staff and the
 * contact; notes stay out for the contact because `get` returns `null`.
 */
export function createConversationController<T extends Identified>(
  options: ConversationControllerOptions<T>,
): ConversationController<T> {
  const typingMs = options.typingMs ?? 5000;

  const topic =
    options.conversationId === null
      ? null
      : `${options.topic ?? "messages"}:${options.conversationId}`;

  let joined:
    | { readonly userId: string; readonly send: (on: boolean) => void }
    | undefined;

  return defineController<ConversationSnapshot<T>, ConversationActions>(
    { items: undefined, status: "closed", error: undefined, typing: NO_TYPERS },
    (state) => {
      const refresh = loader(options.load, state);

      const fetchOne = async (messageId: string): Promise<void> => {
        try {
          const message = await options.get(messageId);

          if (message !== null) {
            state.set((current) => ({
              items: upsert(current.items ?? [], message),
            }));
          }
        } catch (cause) {
          state.set({ error: cause });
        }
      };

      const join = (name: string, userId: string): (() => void) => {
        const seen = new Map<string, ReturnType<typeof setTimeout>>();

        const typer = (who: string, on: boolean): void => {
          const timer = seen.get(who);

          if (timer !== undefined) {
            clearTimeout(timer);
          }

          if (on) {
            seen.set(
              who,
              setTimeout(() => {
                typer(who, false);
              }, typingMs),
            );
          } else {
            seen.delete(who);
          }

          state.set({ typing: [...seen.keys()] });
        };

        const handle = options.ports.topic(name, {
          onMessage: (event, payload) => {
            const data: Record<string, unknown> =
              typeof payload === "object" && payload !== null
                ? { ...payload }
                : {};

            if (event === "typing") {
              const who = textOf(data["userId"]);

              if (who !== undefined && who !== userId) {
                typer(who, data["typing"] !== false);
              }

              return;
            }

            const messageId = textOf(data["messageId"]);

            if (messageId === undefined) {
              options.onEvent?.(event, payload);

              return;
            }

            void fetchOne(messageId);
          },
          onRejoin: () => void refresh(),
          onStatus: (status) => {
            state.set({ status });
          },
        });

        joined = {
          userId,
          send: (on) => {
            handle.send("typing", {
              conversationId: options.conversationId,
              userId,
              typing: on,
            });
          },
        };

        return () => {
          for (const timer of seen.values()) {
            clearTimeout(timer);
          }

          joined = undefined;
          handle.leave();
          state.set({ typing: NO_TYPERS });
        };
      };

      return {
        actions: {
          refresh,
          setTyping: (on) => {
            joined?.send(on);
          },
        },
        start: () => {
          if (topic === null) {
            return;
          }

          return whileSignedIn(options.auth, (userId) => {
            void refresh();

            return join(topic, userId);
          });
        },
      };
    },
  );
}

export interface InboxWidgetControllerOptions<T extends Identified> {
  readonly auth: AuthPort;
  readonly ports: Ports & { readonly storage?: StoragePort };
  /**
   * Opens the visitor's conversation, e.g. a server action that calls
   * `inbox.conversations.open(inboxId, { message })` with the visitor's
   * transport. Returns its id.
   */
  readonly open: (message: string) => Promise<string>;
  /** Sends into the open conversation. */
  readonly send: (conversationId: string, message: string) => Promise<void>;
  readonly load: (conversationId: string) => Promise<readonly T[]>;
  /** One message after a ping; `null` when the visitor cannot read it. */
  readonly get: (messageId: string) => Promise<T | null>;
  /**
   * Remembers the conversation across reloads in the storage port. Defaults to
   * `better-supabase:inbox-widget`; `null` forgets it.
   */
  readonly storageKey?: string | null;
  readonly topic?: string;
}

export interface InboxWidgetSnapshot<T> extends ConversationSnapshot<T> {
  readonly conversationId: string | null;
}

export interface InboxWidgetActions extends ConversationActions {
  /** Opens the conversation with the first message, or sends into it. */
  readonly submit: (message: string) => Promise<void>;
  /** Forgets the conversation, so the next message opens a new one. */
  readonly reset: () => void;
}

export type InboxWidgetController<T extends Identified> = Controller<
  InboxWidgetSnapshot<T>,
  InboxWidgetActions
>;

/**
 * The visitor side of an in-app inbox: the first message opens the
 * conversation, later ones go into it, and the messages and typing pings stay
 * current. Visitors without an account sign in anonymously first.
 */
export function createInboxWidgetController<T extends Identified>(
  options: InboxWidgetControllerOptions<T>,
): InboxWidgetController<T> {
  const key =
    options.storageKey === undefined
      ? "better-supabase:inbox-widget"
      : options.storageKey;

  const storage = key === null ? undefined : options.ports.storage;
  let conversationId: string | null = null;
  let restored = storage === undefined;
  let active = false;
  let inner: ConversationController<T> | undefined;
  let leaveInner: (() => void) | undefined;

  return defineController<InboxWidgetSnapshot<T>, InboxWidgetActions>(
    {
      items: undefined,
      status: "closed",
      error: undefined,
      typing: NO_TYPERS,
      conversationId: null,
    },
    (state) => {
      let show = (): void => undefined;

      const attach = (): void => {
        leaveInner?.();
        leaveInner = active ? inner?.subscribe(show) : undefined;
      };

      const follow = (): void => {
        const id = conversationId;

        const current = createConversationController<T>({
          auth: options.auth,
          ports: options.ports,
          conversationId: id,
          load: () => (id === null ? Promise.resolve([]) : options.load(id)),
          get: options.get,
          ...(options.topic === undefined ? {} : { topic: options.topic }),
        });

        inner = current;
        show = () => {
          state.set({ ...current.getSnapshot(), conversationId: id });
        };

        show();
        attach();
      };

      const choose = (id: string | null): void => {
        if (id === conversationId) {
          return;
        }

        conversationId = id;
        follow();
      };

      follow();

      return {
        actions: {
          refresh: () => inner?.actions.refresh() ?? Promise.resolve(),
          setTyping: (on) => {
            inner?.actions.setTyping(on);
          },
          submit: async (message) => {
            if (conversationId === null) {
              const id = await options.open(message);

              if (key !== null) {
                await storage?.set(key, id);
              }

              choose(id);

              return;
            }

            await options.send(conversationId, message);
          },
          reset: () => {
            if (key !== null) {
              void storage?.remove(key);
            }

            choose(null);
          },
        },
        start: () => {
          active = true;
          attach();

          if (!restored && key !== null && storage) {
            restored = true;
            void storage.get(key).then((stored) => {
              if (stored !== null && conversationId === null) {
                choose(stored);
              }

              return stored;
            });
          }

          return () => {
            active = false;
            leaveInner?.();
            leaveInner = undefined;
          };
        },
      };
    },
  );
}
