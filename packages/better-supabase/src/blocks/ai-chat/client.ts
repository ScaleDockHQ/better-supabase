import type { DbError } from "../../core/errors.ts";
import type { AsyncResult, Result } from "../../core/result.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type {
  AiChat,
  AiChatInput,
  AiChatPage,
  AiChatPatch,
  AiChatQuery,
  AiChatRecord,
  AiChatShare,
  AiModel,
  AiShareLink,
  AiStoredMessage,
} from "./ai-chat.ts";

import { defineController, whileSignedIn } from "../controller.ts";
import { aiChatListTopic, aiChatTopic } from "./ai-chat.ts";

interface Ports {
  readonly topic: TopicPort;
}

/** Runs a write and returns its data, or records the error and returns `undefined`. */
async function attempt<T>(
  write: AsyncResult<T>,
  fail: (error: DbError) => void,
): Promise<T | undefined> {
  const result = await write;
  if (result.ok) return result.data;
  fail(result.error);
  return;
}

export interface AiChatsControllerOptions {
  readonly client: Pick<AiChat, "chats">;
  readonly auth: AuthPort;
  readonly ports: Ports;
  /** The list's filters and page size. */
  readonly query?: Omit<AiChatQuery, "cursor">;
  /** The prefix of the list topic (`blockConfig["ai-chat"].options.listTopic` from `blocks.generated.ts`); `null` loads once. */
  readonly topic?: string | null;
}

export interface AiChatsSnapshot {
  /** `undefined` until the first load. */
  readonly items: readonly AiChatRecord[] | undefined;
  /** Whether `loadMore` has another page. */
  readonly hasMore: boolean;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

export interface AiChatsActions {
  readonly loadMore: () => Promise<void>;
  readonly refresh: () => Promise<void>;
  readonly create: (input?: AiChatInput) => Promise<AiChatRecord | undefined>;
  readonly update: (
    chatId: string,
    patch: AiChatPatch,
  ) => Promise<AiChatRecord | undefined>;
  readonly remove: (chatId: string) => Promise<void>;
}

export type AiChatsController = Controller<AiChatsSnapshot, AiChatsActions>;

/**
 * The signed-in user's chats in a tenant, newest first, loaded again when
 * any of their chats changes. Pages loaded with `loadMore` load again too.
 */
export function createAiChatsController(
  options: AiChatsControllerOptions,
): AiChatsController {
  const { chats } = options.client;
  const query: AiChatQuery = {
    ...options.query,
    organizationId: options.query?.organizationId ?? null,
  };
  const prefix = options.topic === undefined ? "ai-chats" : options.topic;
  return defineController<AiChatsSnapshot, AiChatsActions>(
    { items: undefined, hasMore: false, status: "closed", error: undefined },
    (state) => {
      let user: string | null = null;
      // Writes for an earlier user are dropped.
      let generation = 0;
      // Every list request takes a ticket; only the latest one is applied.
      let ticket = 0;
      // How many pages are shown, so a reload fetches all of them again.
      let pages = 1;
      let next: string | undefined;
      const fail = (error: DbError): void => {
        state.set({ error });
      };
      const showPage = (
        items: readonly AiChatRecord[],
        cursor: string | undefined,
      ): void => {
        next = cursor;
        state.set({ items, hasMore: cursor !== undefined, error: undefined });
      };
      const loadWindow = async (): Promise<void> => {
        if (user === null) return;
        const run = ++ticket;
        const items: AiChatRecord[] = [];
        let page: AiChatPage | undefined;
        for (let loaded = 0; loaded < pages; loaded += 1) {
          const result: Result<AiChatPage> = await chats.list(
            page?.next === undefined ? query : { ...query, cursor: page.next },
          );
          if (run !== ticket) return;
          if (!result.ok) {
            fail(result.error);
            return;
          }
          page = result.data;
          items.push(...page.items);
          if (page.next === undefined) break;
        }
        showPage(items, page?.next);
      };
      const edit = (
        at: number,
        change: (items: readonly AiChatRecord[]) => readonly AiChatRecord[],
      ): void => {
        if (at !== generation) return;
        state.set((current) =>
          current.items === undefined ? {} : { items: change(current.items) },
        );
      };
      return {
        actions: {
          refresh: loadWindow,
          loadMore: async () => {
            if (next === undefined || user === null) return;
            const run = ++ticket;
            pages += 1;
            const result = await chats.list({ ...query, cursor: next });
            if (run !== ticket) return;
            if (!result.ok) {
              pages -= 1;
              fail(result.error);
              return;
            }
            const page = result.data;
            showPage([...(state.get().items ?? []), ...page.items], page.next);
          },
          create: async (input) => {
            const organizationId = query.organizationId;
            if (!organizationId) return;
            const at = generation;
            const chat = await attempt(
              chats.create(organizationId, input),
              fail,
            );
            if (chat && !chat.temporary)
              edit(at, (items) => [
                chat,
                ...items.filter((item) => item.id !== chat.id),
              ]);
            return chat;
          },
          update: async (chatId, patch) => {
            const at = generation;
            const chat = await attempt(chats.update(chatId, patch), fail);
            if (chat)
              edit(at, (items) =>
                items.map((item) => (item.id === chat.id ? chat : item)),
              );
            return chat;
          },
          remove: async (chatId) => {
            const at = generation;
            if (await attempt(chats.remove(chatId), fail))
              edit(at, (items) => items.filter((item) => item.id !== chatId));
          },
        },
        start: () =>
          whileSignedIn(options.auth, (userId) => {
            user = userId;
            generation += 1;
            pages = 1;
            next = undefined;
            state.set({ items: undefined, hasMore: false, error: undefined });
            void loadWindow();
            const leave = prefix
              ? options.ports.topic(aiChatListTopic(userId, prefix), {
                  onMessage: () => void loadWindow(),
                  onRejoin: () => void loadWindow(),
                  onStatus: (status) => {
                    state.set({ status });
                  },
                }).leave
              : undefined;
            return () => {
              user = null;
              generation += 1;
              ticket += 1;
              leave?.();
              next = undefined;
              state.set({ items: undefined, hasMore: false, error: undefined });
            };
          }),
      };
    },
  );
}

export interface AiChatTreeControllerOptions {
  readonly client: {
    readonly messages: Pick<
      AiChat["messages"],
      "path" | "switchBranch" | "siblings"
    >;
  };
  readonly ports: Ports;
  /** `null` or `undefined` waits. */
  readonly chatId: string | null | undefined;
  /** The prefix of the chat topic (`blockConfig["ai-chat"].options.topic` from `blocks.generated.ts`); `null` loads once. */
  readonly topic?: string | null;
}

export interface AiChatTreeSnapshot {
  /** The active branch, root first; `undefined` until the first load. */
  readonly path: readonly AiStoredMessage[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

export interface AiChatTreeActions {
  readonly refresh: () => Promise<void>;
  /** Shows the branch through `messageId`. */
  readonly switchBranch: (messageId: string) => Promise<void>;
  /** Shows the sibling `offset` places from `messageId` (`-1` older, `1` newer). */
  readonly step: (messageId: string, offset: number) => Promise<void>;
}

export type AiChatTreeController = Controller<
  AiChatTreeSnapshot,
  AiChatTreeActions
>;

/**
 * One chat's active branch, loaded again when a message is saved or the
 * branch changes, in this tab or another.
 */
export function createAiChatTreeController(
  options: AiChatTreeControllerOptions,
): AiChatTreeController {
  const { messages } = options.client;
  const { chatId } = options;
  const prefix = options.topic === undefined ? "ai-chat" : options.topic;
  return defineController<AiChatTreeSnapshot, AiChatTreeActions>(
    { path: undefined, status: "closed", error: undefined },
    (state) => {
      let ticket = 0;
      const apply = (result: Result<readonly AiStoredMessage[]>): void => {
        state.set(
          result.ok
            ? { path: result.data, error: undefined }
            : { error: result.error },
        );
      };
      const loadPath = async (leafId?: string): Promise<void> => {
        if (!chatId) return;
        const run = ++ticket;
        const result = await messages.path(
          chatId,
          leafId === undefined ? undefined : { leafId },
        );
        if (run === ticket) apply(result);
      };
      const switchBranch = async (messageId: string): Promise<void> => {
        if (!chatId) return;
        const run = state.run();
        const result = await messages.switchBranch(chatId, messageId);
        if (run !== state.run()) return;
        if (result.ok) await loadPath(result.data);
        else state.set({ error: result.error });
      };
      return {
        actions: {
          refresh: () => loadPath(),
          switchBranch,
          step: async (messageId, offset) => {
            if (!chatId) return;
            const run = state.run();
            const result = await messages.siblings(chatId, messageId);
            if (run !== state.run()) return;
            if (!result.ok) {
              state.set({ error: result.error });
              return;
            }
            const siblings = result.data;
            const index = siblings.findIndex((item) => item.id === messageId);
            const target = siblings[index + offset];
            if (index !== -1 && target) await switchBranch(target.id);
          },
        },
        start: () => {
          void loadPath();
          const leave =
            chatId && prefix
              ? options.ports.topic(aiChatTopic(chatId, prefix), {
                  onMessage: (event) => {
                    if (event === "message.saved" || event === "leaf.changed")
                      void loadPath();
                  },
                  onRejoin: () => void loadPath(),
                  onStatus: (status) => {
                    state.set({ status });
                  },
                }).leave
              : undefined;
          return () => {
            ticket += 1;
            leave?.();
          };
        },
      };
    },
  );
}

export interface AiModelsControllerOptions {
  readonly client: { readonly models: Pick<AiChat["models"], "allowed"> };
  readonly organizationId?: string | null;
}

export interface AiModelsSnapshot {
  /** `undefined` until loaded. */
  readonly models: readonly AiModel[] | undefined;
  readonly error: DbError | undefined;
}

export interface AiModelsActions {
  readonly refresh: () => Promise<void>;
}

export type AiModelsController = Controller<AiModelsSnapshot, AiModelsActions>;

/** The models the tenant's plans allow, for a model picker. */
export function createAiModelsController(
  options: AiModelsControllerOptions,
): AiModelsController {
  const tenant = options.organizationId ?? null;
  return defineController<AiModelsSnapshot, AiModelsActions>(
    { models: undefined, error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        const run = state.run();
        const result = await options.client.models.allowed(tenant);
        if (run !== state.run()) return;
        state.set(
          result.ok
            ? { models: result.data, error: undefined }
            : { error: result.error },
        );
      };
      return {
        actions: { refresh },
        start: () => {
          void refresh();
          return;
        },
      };
    },
  );
}

export interface AiShareControllerOptions {
  readonly client: {
    readonly shares: Pick<AiChat["shares"], "list" | "create" | "revoke">;
  };
  /** `null` or `undefined` waits. */
  readonly chatId: string | null | undefined;
}

export interface AiShareSnapshot {
  /** The chat's share links, newest first; `undefined` until loaded. */
  readonly shares: readonly AiChatShare[] | undefined;
  readonly error: DbError | undefined;
}

export interface AiShareActions {
  /** Makes a link to the active branch, or to `leafId`; the token is in the result only. */
  readonly create: (leafId?: string) => Promise<AiShareLink | undefined>;
  readonly revoke: (shareId: string) => Promise<void>;
}

export type AiShareController = Controller<AiShareSnapshot, AiShareActions>;

/** Share links for one chat the user owns. */
export function createAiShareController(
  options: AiShareControllerOptions,
): AiShareController {
  const { shares } = options.client;
  const { chatId } = options;
  return defineController<AiShareSnapshot, AiShareActions>(
    { shares: undefined, error: undefined },
    (state) => {
      const fail = (error: DbError): void => {
        state.set({ error });
      };
      const reload = async (): Promise<void> => {
        if (!chatId) return;
        const run = state.run();
        const result = await shares.list(chatId);
        if (run !== state.run()) return;
        state.set(
          result.ok
            ? { shares: result.data, error: undefined }
            : { error: result.error },
        );
      };
      return {
        actions: {
          create: async (leafId) => {
            if (!chatId) return;
            const link = await attempt(shares.create(chatId, leafId), fail);
            if (link) await reload();
            return link;
          },
          revoke: async (shareId) => {
            if (await attempt(shares.revoke(shareId), fail)) await reload();
          },
        },
        start: () => {
          void reload();
          return;
        },
      };
    },
  );
}
