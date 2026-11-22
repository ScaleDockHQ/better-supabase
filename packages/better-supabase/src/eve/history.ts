import type { AiChat } from "../blocks/ai-chat/ai-chat.ts";
import type { AiMessagePart } from "../blocks/ai-chat/message.ts";

import { sessionChatId } from "./sync.ts";

/**
 * One message of eve's `delivery.consumed.history`: a conversation eve did not
 * run, such as the transcript of an earlier session.
 */
export interface EveHistoryMessage {
  readonly id: string;
  readonly role: "user" | "assistant";
  readonly text: string;
}

export interface SessionHistoryOptions {
  /** The leaf to read up to. Defaults to the chat's current leaf. */
  readonly leafId?: string;
  /** Keeps the last `limit` messages. Default: all of them. */
  readonly limit?: number;
}

const textOf = (parts: readonly AiMessagePart[]): string =>
  parts.flatMap((part) => (part.type === "text" ? [part.text] : [])).join("\n");

/**
 * The text messages of a synced eve session, in eve's `history` shape, to seed
 * a new session with what the old one said: pass it as the first message's
 * `history` when you hand a conversation to a session on a newer eve version.
 * An unknown session reads as no history.
 */
export async function sessionHistory(
  chats: Pick<AiChat, "messages">,
  sessionId: string,
  options: SessionHistoryOptions = {},
): Promise<readonly EveHistoryMessage[]> {
  const chatId = await sessionChatId(sessionId);

  const path = await chats.messages.path({
    chatId,
    ...(options.leafId === undefined ? {} : { leafId: options.leafId }),
  });

  if (!path.ok) {
    if (path.error.kind === "not_found") {
      return [];
    }

    throw new Error(`eve session history: ${path.error.message}`);
  }

  const messages = path.data.flatMap((message) => {
    const text = textOf(message.parts);

    return (message.role === "user" || message.role === "assistant") &&
      text.length > 0
      ? [{ id: message.id, role: message.role, text }]
      : [];
  });

  return options.limit === undefined
    ? messages
    : messages.slice(-options.limit);
}
