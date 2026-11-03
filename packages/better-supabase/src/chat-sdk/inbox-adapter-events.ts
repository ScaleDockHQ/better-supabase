import type { Adapter, Author, ChatInstance, WebhookOptions } from "chat";

import { ChatError } from "chat";

import type {
  InboxActionEvent,
  InboxActor,
  InboxReactionEvent,
} from "./inbox-adapter-parts.ts";

import { emojiFromRaw } from "./inbox-adapter-parts.ts";

export interface EventDispatcherDeps {
  readonly chat: () => ChatInstance | undefined;
  readonly adapter: () => Adapter;
  /** The thread id of a conversation, or `undefined` when it is unknown. */
  readonly threadFor: (
    conversationId: string,
    inboxId: string | undefined,
  ) => Promise<string | undefined>;
  readonly remember: (threadId: string) => unknown;
  readonly stopActionId: string;
}

/** The actions and reactions `inboxAdapter` hands to the Chat SDK. */
export function eventDispatchers(deps: EventDispatcherDeps): {
  dispatchAction: (
    event: InboxActionEvent,
    webhook?: WebhookOptions,
  ) => Promise<void>;
  dispatchReaction: (
    event: InboxReactionEvent,
    webhook?: WebhookOptions,
  ) => Promise<void>;
} {
  const { remember, stopActionId } = deps;
  const threadIdFor = deps.threadFor;
  const adapterOf = deps.adapter;

  const actorOf = (actor: InboxActor | undefined): Author => {
    const name = actor?.name ?? "visitor";

    return {
      userId: actor?.id ?? "visitor",
      userName: name,
      fullName: name,
      isBot: false,
      isMe: false,
    };
  };

  const settle = (
    instance: ChatInstance,
    work: (options: WebhookOptions) => Promise<void>,
    webhook: WebhookOptions,
    what: string,
  ): Promise<void> => {
    const { waitUntil, ...rest } = webhook;
    const task = work(rest);

    if (waitUntil === undefined) {
      return task;
    }

    waitUntil(
      rest.propagateHandlerErrors === true
        ? task
        : task.catch((error: unknown) => {
            instance
              .getLogger("inbox")
              .error(`inbox ${what} failed`, { error });
          }),
    );

    return Promise.resolve();
  };

  const dispatchAction = (
    event: InboxActionEvent,
    webhook: WebhookOptions = {},
  ): Promise<void> => {
    const chat = deps.chat();

    if (!chat) {
      return Promise.reject(
        new ChatError("inboxAdapter: initialize() has not run", "NOT_READY"),
      );
    }

    const instance = chat;

    const task = async (handlerOptions: WebhookOptions): Promise<void> => {
      const threadId = await threadIdFor(event.conversation_id, event.inbox_id);

      if (threadId === undefined) {
        return;
      }

      remember(threadId);

      if (event.action_id === stopActionId) {
        await instance.abortTurn(threadId);

        return;
      }

      await instance.processAction(
        {
          adapter: adapterOf(),
          actionId: event.action_id,
          messageId: event.message_id,
          threadId,
          raw: event,
          user: actorOf(event.user),
          ...(event.value === undefined ? {} : { value: event.value }),
        },
        handlerOptions,
      );
    };

    return settle(instance, task, webhook, "action");
  };

  const dispatchReaction = (
    event: InboxReactionEvent,
    webhook: WebhookOptions = {},
  ): Promise<void> => {
    const chat = deps.chat();

    if (!chat) {
      return Promise.reject(
        new ChatError("inboxAdapter: initialize() has not run", "NOT_READY"),
      );
    }

    const instance = chat;

    const task = async (handlerOptions: WebhookOptions): Promise<void> => {
      const threadId = await threadIdFor(event.conversation_id, event.inbox_id);

      if (threadId === undefined) {
        return;
      }

      remember(threadId);

      await instance.processReaction(
        {
          adapter: adapterOf(),
          added: event.added,
          emoji: emojiFromRaw(event.emoji),
          rawEmoji: event.emoji,
          messageId: event.message_id,
          threadId,
          raw: event,
          user: actorOf(event.user),
        },
        handlerOptions,
      );
    };

    return settle(instance, task, webhook, "reaction");
  };

  return { dispatchAction, dispatchReaction };
}
