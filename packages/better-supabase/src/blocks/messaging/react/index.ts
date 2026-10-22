"use client";

import type { BlockEnv } from "../../block-env.ts";
import type {
  MessagesActions,
  MessagesSnapshot,
  ConversationsActions,
  ConversationsSnapshot,
} from "../client.ts";
import type { ConversationKind } from "../messaging.ts";

import { envBlockOptions, envBlockSettings } from "../../block-env-options.ts";
import { useController } from "../../react-controller.ts";
import { useBlockEnv, useBlockTenant } from "../../react-env.ts";
import {
  createMessagesController,
  createConversationsController,
} from "../client.ts";
import { createMessaging } from "../messaging.ts";

export type { MessageDraft } from "../client.ts";

/** `blocks.messaging.options.topic` from the client's config. */
function topicOf(env: BlockEnv): string {
  const topic = envBlockSettings(env, "messaging")["topic"];

  return typeof topic === "string" ? topic : "messages";
}

export interface UseMessagesOptions {
  /** The conversation or channel to show; the view waits without one. */
  readonly conversationId: string | null | undefined;
  /** A thread's root message, to show its replies instead. */
  readonly threadId?: string | null;
  /** Messages per page, default 50. */
  readonly limit?: number;
  /** Moves the read marker as messages arrive; default true. */
  readonly markRead?: boolean;
}

export interface MessagesState extends MessagesSnapshot, MessagesActions {}

/**
 * One conversation or thread through the browser client: the latest page, kept
 * current from Realtime, who is typing, and the read marker. It acts in the
 * client's tenant with the schema and topic in the client's `blocks` config.
 * The same hook runs in React DOM and React Native.
 *
 * ```tsx
 * const { messages, send, setTyping } = useMessages({ conversationId });
 * ```
 */
export function useMessages(options: UseMessagesOptions): MessagesState {
  const env = useBlockEnv();
  const tenant = useBlockTenant(env);
  const { conversationId, threadId, limit, markRead } = options;

  return useController(
    () =>
      createMessagesController({
        client: createMessaging({
          ...envBlockOptions(env, "messaging"),
          ...(tenant === undefined ? {} : { tenant }),
        }),
        auth: env.auth,
        ports: env.ports,
        conversationId:
          tenant === undefined || conversationId === undefined
            ? null
            : conversationId,
        topic: topicOf(env),
        ...(threadId === undefined ? {} : { threadId }),
        ...(limit === undefined ? {} : { limit }),
        ...(markRead === undefined ? {} : { markRead }),
      }),
    [env, tenant, conversationId, threadId, limit, markRead],
  ).view;
}

export interface UseConversationsOptions {
  /** Only these kinds, such as `["channel"]`. */
  readonly kinds?: readonly ConversationKind[];
  readonly limit?: number;
}

export interface ConversationsState
  extends ConversationsSnapshot, ConversationsActions {}

/**
 * The caller's conversations with unread and mention counts, loaded again when
 * a message arrives in one of them: a channel sidebar or a direct message
 * list.
 */
export function useConversations(
  options: UseConversationsOptions = {},
): ConversationsState {
  const env = useBlockEnv();
  const tenant = useBlockTenant(env);
  const { limit } = options;
  const kinds = options.kinds?.join(",");

  return useController(() => {
    // SAFETY: `kinds` is the caller's ConversationKind list, joined for the deps.
    const kindList = kinds?.split(",") as ConversationKind[] | undefined;

    return createConversationsController({
      client: createMessaging({
        ...envBlockOptions(env, "messaging"),
        ...(tenant === undefined ? {} : { tenant }),
      }),
      auth: env.auth,
      ports: env.ports,
      enabled: tenant !== undefined,
      topic: topicOf(env),
      ...(kindList === undefined ? {} : { kinds: kindList }),
      ...(limit === undefined ? {} : { limit }),
    });
  }, [env, tenant, kinds, limit]).view;
}
