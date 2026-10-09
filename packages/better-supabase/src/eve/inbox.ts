import type { Inbox } from "../blocks/inbox/inbox.ts";
import type { EveSessionAuth } from "./types.ts";

/** The parts of a Chat SDK thread `routeInbox` reads. */
export interface EveChatThread {
  readonly id: string;
  subscribe(): Promise<void>;
}

/** The parts of a Chat SDK message `routeInbox` reads. */
export interface EveChatMessage {
  readonly text: string;
}

/**
 * The parts of eve's `chatSdkChannel()` result `routeInbox` uses. `T` is the
 * Chat SDK thread, so `send` gets back the thread the handler received.
 */
export interface EveChatSdkBridge<T extends EveChatThread = EveChatThread> {
  readonly bot: {
    onNewMention(
      handler: (thread: T, message: EveChatMessage) => Promise<void>,
    ): void;
    onSubscribedMessage(
      handler: (thread: T, message: EveChatMessage) => Promise<void>,
    ): void;
  };
  send(
    message: string,
    options: {
      readonly thread: NoInfer<T>;
      readonly auth: EveSessionAuth | null;
      readonly title?: string;
    },
  ): Promise<unknown>;
}

export interface RouteInboxOptions {
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /** The session title for a new conversation. Defaults to the conversation's subject. */
  readonly title?: string;
}

const INBOX_PREFIX = "inbox:";

/**
 * Hands inbox conversations to eve through a `chatSdkChannel` built over
 * `inboxAdapter`. A message reaches eve only while the conversation's
 * `bot_mode` is `bot`, so an agent's handoff pauses the bot. The turn's
 * principal is the contact, never a user, so contacts get no user-scoped
 * connections.
 */
export function routeInbox<T extends EveChatThread>(
  bridge: EveChatSdkBridge<T>,
  options: RouteInboxOptions,
): void {
  const handle = async (thread: T, message: EveChatMessage): Promise<void> => {
    if (!thread.id.startsWith(INBOX_PREFIX)) return;
    const conversation = await options.inbox.conversations
      .get(thread.id.slice(INBOX_PREFIX.length))
      .orThrow();
    if (conversation?.botMode !== "bot") return;
    const title = options.title ?? conversation.subject ?? undefined;
    await bridge.send(message.text, {
      thread,
      auth: {
        authenticator: "inbox",
        principalType: "contact",
        principalId: conversation.contactId,
        attributes: {
          tenantId: conversation.tenant,
          conversationId: conversation.id,
        },
      },
      ...(title === undefined ? {} : { title }),
    });
  };
  bridge.bot.onNewMention(async (thread, message) => {
    await thread.subscribe();
    await handle(thread, message);
  });
  bridge.bot.onSubscribedMessage(handle);
}
