"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import type { DbError } from "../../../core/errors.ts";
import type { AsyncResult, Result } from "../../../core/result.ts";
import type { SubscriptionStatus } from "../../../realtime/index.ts";
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
} from "../ai-chat.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { ok } from "../../../core/result.ts";
import { useAuth, useSupabase } from "../../../react/hooks.ts";
import { watchTopic } from "../../react-topic.ts";
import { aiChatListTopic, aiChatTopic, createAiChat } from "../ai-chat.ts";

interface ClientOptions {
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `sql.modules["ai-chat"].api`. */
  readonly schema?: string;
}

function useAiChatClient(schema: string | undefined): AiChat {
  const supabase = useSupabase();
  return useMemo(
    () =>
      createAiChat({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
}

/** Keeps a result's data, or its error next to the last good data. */
function useResultState<T>(): {
  readonly data: T | undefined;
  readonly error: DbError | undefined;
  readonly apply: (result: Result<T>) => void;
  readonly fail: (error: DbError) => void;
  readonly set: (update: (current: T | undefined) => T | undefined) => void;
} {
  const [data, setData] = useState<T | undefined>(undefined);
  const [error, setError] = useState<DbError | undefined>(undefined);
  const apply = useCallback((result: Result<T>) => {
    if (result.ok) {
      setData(result.data);
      setError(undefined);
    } else {
      setError(result.error);
    }
  }, []);
  return { data, error, apply, fail: setError, set: setData };
}

/** Runs a write and returns its data, or records the error and returns `undefined`. */
async function attempt<T>(
  write: AsyncResult<T>,
  fail: (error: DbError) => void,
): Promise<T | undefined> {
  const result = await write;
  if (result.ok) return result.data;
  fail(result.error);
  return undefined;
}

export interface UseAiChatsOptions
  extends ClientOptions, Omit<AiChatQuery, "after"> {
  /** The prefix of the list topic (`sql.modules["ai-chat"].options.listTopic`); `null` loads once. */
  readonly topic?: string | null;
}

export interface AiChatsState {
  /** `undefined` until the first load. */
  readonly items: readonly AiChatRecord[] | undefined;
  /** Whether `loadMore` has another page. */
  readonly hasMore: boolean;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
  readonly loadMore: () => Promise<void>;
  readonly refresh: () => Promise<void>;
  readonly create: (input?: AiChatInput) => Promise<AiChatRecord | undefined>;
  readonly update: (
    chatId: string,
    patch: AiChatPatch,
  ) => Promise<AiChatRecord | undefined>;
  readonly remove: (chatId: string) => Promise<void>;
}

/**
 * The signed-in user's chats in a tenant, newest first, loaded again when
 * any of their chats changes.
 *
 * ```tsx
 * const { items, loadMore, create } = useAiChats({ organizationId });
 * ```
 */
export function useAiChats(options: UseAiChatsOptions = {}): AiChatsState {
  const supabase = useSupabase();
  const auth = useAuth();
  const client = useAiChatClient(options.schema);
  const state = useResultState<readonly AiChatRecord[]>();
  const [next, setNext] = useState<string | undefined>(undefined);
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const userId = auth.user?.id ?? null;
  const prefix = options.topic === undefined ? "ai-chats" : options.topic;
  const { organizationId, search, projectId, pinned, archived, size } = options;
  const query = useMemo(
    (): AiChatQuery => ({
      organizationId: organizationId ?? null,
      ...(search === undefined ? {} : { search }),
      ...(projectId === undefined ? {} : { projectId }),
      ...(pinned === undefined ? {} : { pinned }),
      ...(archived === undefined ? {} : { archived }),
      ...(size === undefined ? {} : { size }),
    }),
    [organizationId, search, projectId, pinned, archived, size],
  );
  const { apply, fail, set } = state;

  const applyPage = useCallback(
    (result: Result<AiChatPage>) => {
      if (result.ok) setNext(result.data.next);
      apply(result.ok ? ok(result.data.items) : result);
    },
    [apply],
  );

  const load = useCallback(async () => {
    applyPage(await client.chats.list(query));
  }, [client, query, applyPage]);

  const loadMore = useCallback(async () => {
    if (next === undefined) return;
    const page = await attempt(
      client.chats.list({ ...query, after: next }),
      fail,
    );
    if (!page) return;
    set((current) => [...(current ?? []), ...page.items]);
    setNext(page.next);
  }, [client, query, next, fail, set]);

  const create = useCallback(
    async (input?: AiChatInput) => {
      if (!organizationId) return;
      const chat = await attempt(
        client.chats.create(organizationId, input),
        fail,
      );
      if (chat && !chat.temporary) {
        set((current) => [
          chat,
          ...(current ?? []).filter((item) => item.id !== chat.id),
        ]);
      }
      return chat;
    },
    [client, organizationId, fail, set],
  );

  const update = useCallback(
    async (chatId: string, patch: AiChatPatch) => {
      const chat = await attempt(client.chats.update(chatId, patch), fail);
      if (chat) {
        set((current) =>
          current?.map((item) => (item.id === chat.id ? chat : item)),
        );
      }
      return chat;
    },
    [client, fail, set],
  );

  const remove = useCallback(
    async (chatId: string) => {
      const removed = await attempt(client.chats.remove(chatId), fail);
      if (removed) {
        set((current) => current?.filter((item) => item.id !== chatId));
      }
    },
    [client, fail, set],
  );

  useEffect(() => {
    if (userId === null) return;
    let active = true;
    const reload = () =>
      void client.chats.list(query).then((result) => {
        if (active) applyPage(result);
      });
    reload();
    const leave = prefix
      ? watchTopic(supabase, aiChatListTopic(userId, prefix), {
          onMessage: reload,
          onRejoin: reload,
          onStatus: setStatus,
        })
      : undefined;
    return () => {
      active = false;
      leave?.();
    };
  }, [client, supabase, prefix, query, userId, applyPage]);

  return {
    items: state.data,
    hasMore: next !== undefined,
    status,
    error: state.error,
    loadMore,
    refresh: load,
    create,
    update,
    remove,
  };
}

export interface UseAiChatTreeOptions extends ClientOptions {
  /** The prefix of the chat topic (`sql.modules["ai-chat"].options.topic`); `null` loads once. */
  readonly topic?: string | null;
}

export interface AiChatTreeState {
  /** The active branch, root first; `undefined` until the first load. */
  readonly path: readonly AiStoredMessage[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
  readonly refresh: () => Promise<void>;
  /** Shows the branch through `messageId`. */
  readonly switchBranch: (messageId: string) => Promise<void>;
  /** Shows the sibling `offset` places from `messageId` (`-1` older, `1` newer). */
  readonly step: (messageId: string, offset: number) => Promise<void>;
}

/**
 * One chat's active branch, loaded again when a message is saved or the
 * branch changes, in this tab or another.
 *
 * ```tsx
 * const { path, step } = useAiChatTree(chatId);
 * ```
 */
export function useAiChatTree(
  chatId: string | null | undefined,
  options: UseAiChatTreeOptions = {},
): AiChatTreeState {
  const supabase = useSupabase();
  const client = useAiChatClient(options.schema);
  const state = useResultState<readonly AiStoredMessage[]>();
  const [status, setStatus] = useState<SubscriptionStatus>("closed");
  const prefix = options.topic === undefined ? "ai-chat" : options.topic;
  const { apply, fail } = state;
  const path = state.data;

  const refresh = useCallback(async () => {
    if (!chatId) return;
    apply(await client.messages.path(chatId));
  }, [client, chatId, apply]);

  const switchBranch = useCallback(
    async (messageId: string) => {
      if (!chatId) return;
      const leaf = await attempt(
        client.messages.switchBranch(chatId, messageId),
        fail,
      );
      if (leaf !== undefined) {
        apply(await client.messages.path(chatId, { leafId: leaf }));
      }
    },
    [client, chatId, apply, fail],
  );

  const step = useCallback(
    async (messageId: string, offset: number) => {
      if (!chatId) return;
      const siblings = await attempt(
        client.messages.siblings(chatId, messageId),
        fail,
      );
      if (!siblings) return;
      const index = siblings.findIndex((item) => item.id === messageId);
      const target = siblings[index + offset];
      if (index >= 0 && target) await switchBranch(target.id);
    },
    [client, chatId, fail, switchBranch],
  );

  useEffect(() => {
    if (!chatId) return;
    let active = true;
    const reload = () =>
      void client.messages.path(chatId).then((result) => {
        if (active) apply(result);
      });
    reload();
    const leave = prefix
      ? watchTopic(supabase, aiChatTopic(chatId, prefix), {
          onMessage: (event) => {
            if (event === "message.saved" || event === "leaf.changed") {
              reload();
            }
          },
          onRejoin: reload,
          onStatus: setStatus,
        })
      : undefined;
    return () => {
      active = false;
      leave?.();
    };
  }, [client, supabase, prefix, chatId, apply]);

  return { path, status, error: state.error, refresh, switchBranch, step };
}

export interface AiModelsState {
  /** `undefined` until loaded. */
  readonly models: readonly AiModel[] | undefined;
  readonly error: DbError | undefined;
  readonly refresh: () => Promise<void>;
}

/** The models the tenant's plans allow, for a model picker. */
export function useAiModels(
  organizationId?: string | null,
  options: ClientOptions = {},
): AiModelsState {
  const client = useAiChatClient(options.schema);
  const state = useResultState<readonly AiModel[]>();
  const tenant = organizationId ?? null;
  const { apply } = state;

  const refresh = useCallback(async () => {
    apply(await client.models.allowed(tenant));
  }, [client, tenant, apply]);

  useEffect(() => {
    let active = true;
    void client.models.allowed(tenant).then((result) => {
      if (active) apply(result);
    });
    return () => {
      active = false;
    };
  }, [client, tenant, apply]);

  return { models: state.data, error: state.error, refresh };
}

export interface AiShareState {
  /** The chat's share links, newest first; `undefined` until loaded. */
  readonly shares: readonly AiChatShare[] | undefined;
  readonly error: DbError | undefined;
  /** Makes a link to the active branch, or to `leafId`; the token is in the result only. */
  readonly create: (leafId?: string) => Promise<AiShareLink | undefined>;
  readonly revoke: (shareId: string) => Promise<void>;
}

/** Share links for one chat the user owns. */
export function useAiShare(
  chatId: string | null | undefined,
  options: ClientOptions = {},
): AiShareState {
  const client = useAiChatClient(options.schema);
  const state = useResultState<readonly AiChatShare[]>();
  const { apply, fail } = state;

  const reload = useCallback(async () => {
    if (chatId) apply(await client.shares.list(chatId));
  }, [client, chatId, apply]);

  const create = useCallback(
    async (leafId?: string) => {
      if (!chatId) return;
      const link = await attempt(client.shares.create(chatId, leafId), fail);
      if (link) await reload();
      return link;
    },
    [client, chatId, fail, reload],
  );

  const revoke = useCallback(
    async (shareId: string) => {
      if (await attempt(client.shares.revoke(shareId), fail)) await reload();
    },
    [client, fail, reload],
  );

  useEffect(() => {
    if (!chatId) return;
    let active = true;
    void client.shares.list(chatId).then((result) => {
      if (active) apply(result);
    });
    return () => {
      active = false;
    };
  }, [client, chatId, apply]);

  return { shares: state.data, error: state.error, create, revoke };
}
