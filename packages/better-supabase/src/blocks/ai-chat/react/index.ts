"use client";

import { useMemo } from "react";

import type { AiChat, AiChatQuery } from "../ai-chat.ts";
import type {
  AiChatsActions,
  AiChatsSnapshot,
  AiChatTreeActions,
  AiChatTreeSnapshot,
  AiModelsActions,
  AiModelsSnapshot,
  AiShareActions,
  AiShareSnapshot,
} from "../client.ts";

import { rpcTransport } from "../../../core/block-transport.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv } from "../../react-env.ts";
import { createAiChat } from "../ai-chat.ts";
import {
  createAiChatsController,
  createAiChatTreeController,
  createAiModelsController,
  createAiShareController,
} from "../client.ts";

interface ClientOptions {
  /** The schema the calls go to: the module schema (default `better_supabase`), or the API schema from `blocks["ai-chat"].api`. */
  readonly schema?: string;
}

function useAiChatClient(schema: string | undefined): AiChat {
  const { supabase } = useBlockEnv();
  return useMemo(
    () =>
      createAiChat({
        transport: rpcTransport(supabase),
        ...(schema === undefined ? {} : { schema }),
      }),
    [supabase, schema],
  );
}

export interface UseAiChatsOptions
  extends ClientOptions, Omit<AiChatQuery, "cursor"> {
  /** The prefix of the list topic (`blocks["ai-chat"].options.listTopic`); `null` loads once. */
  readonly topic?: string | null;
}

export interface AiChatsState extends AiChatsSnapshot, AiChatsActions {}

/**
 * The signed-in user's chats in a tenant, newest first, loaded again when
 * any of their chats changes.
 *
 * ```tsx
 * const { items, loadMore, create } = useAiChats({ organizationId });
 * ```
 */
export function useAiChats(options: UseAiChatsOptions = {}): AiChatsState {
  const { auth, ports } = useBlockEnv();
  const client = useAiChatClient(options.schema);
  const { topic, organizationId, search, projectId, pinned, archived, limit } =
    options;
  return useController(
    () =>
      createAiChatsController({
        client,
        auth,
        ports,
        query: {
          organizationId: organizationId ?? null,
          ...(search === undefined ? {} : { search }),
          ...(projectId === undefined ? {} : { projectId }),
          ...(pinned === undefined ? {} : { pinned }),
          ...(archived === undefined ? {} : { archived }),
          ...(limit === undefined ? {} : { limit }),
        },
        ...(topic === undefined ? {} : { topic }),
      }),
    [
      client,
      auth,
      ports,
      topic,
      organizationId,
      search,
      projectId,
      pinned,
      archived,
      limit,
    ],
  ).view;
}

export interface UseAiChatTreeOptions extends ClientOptions {
  /** The prefix of the chat topic (`blocks["ai-chat"].options.topic`); `null` loads once. */
  readonly topic?: string | null;
}

export interface AiChatTreeState
  extends AiChatTreeSnapshot, AiChatTreeActions {}

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
  const { ports } = useBlockEnv();
  const client = useAiChatClient(options.schema);
  const { topic } = options;
  return useController(
    () =>
      createAiChatTreeController({
        client,
        ports,
        chatId,
        ...(topic === undefined ? {} : { topic }),
      }),
    [client, ports, chatId, topic],
  ).view;
}

export interface AiModelsState extends AiModelsSnapshot, AiModelsActions {}

/** The models the tenant's plans allow, for a model picker. */
export function useAiModels(
  organizationId?: string | null,
  options: ClientOptions = {},
): AiModelsState {
  const client = useAiChatClient(options.schema);
  const tenant = organizationId ?? null;
  return useController(
    () => createAiModelsController({ client, organizationId: tenant }),
    [client, tenant],
  ).view;
}

export interface AiShareState extends AiShareSnapshot, AiShareActions {}

/** Share links for one chat the user owns. */
export function useAiShare(
  chatId: string | null | undefined,
  options: ClientOptions = {},
): AiShareState {
  const client = useAiChatClient(options.schema);
  return useController(
    () => createAiShareController({ client, chatId }),
    [client, chatId],
  ).view;
}
