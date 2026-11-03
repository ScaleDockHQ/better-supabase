import type { AdapterPostableMessage, EmojiValue } from "chat";

import { defaultEmojiResolver } from "chat";

import type { InboxMessage } from "../blocks/inbox/types.ts";

import { randomToken } from "../core/block-helpers.ts";
import { nowInstant } from "../core/temporal.ts";

/** A file the bot posts, as `InboxAdapterOptions.upload` gets it. */
export interface InboxOutgoingFile {
  readonly name: string;
  readonly mimeType: string | undefined;
  readonly data: Blob | ArrayBuffer | Buffer;
}

export function aiGeneratedOf(message: AdapterPostableMessage): boolean {
  return (
    typeof message === "object" &&
    "aiGenerated" in message &&
    message.aiGenerated
  );
}

/** The files and attachments a postable message carries, with their bytes. */
export async function outgoingFilesOf(
  message: AdapterPostableMessage,
): Promise<InboxOutgoingFile[]> {
  if (typeof message !== "object") {
    return [];
  }

  const out: InboxOutgoingFile[] = [];

  if ("files" in message) {
    for (const file of message.files) {
      out.push({
        name: file.filename,
        mimeType: file.mimeType,
        data: file.data,
      });
    }
  }

  if ("attachments" in message) {
    for (const attachment of message.attachments) {
      const data = attachment.data ?? (await attachment.fetchData?.());

      if (data !== undefined) {
        out.push({
          name: attachment.name ?? "file",
          mimeType: attachment.mimeType,
          data,
        });
      }
    }
  }

  return out;
}

export const byteLength = (data: Blob | ArrayBuffer | Buffer): number =>
  data instanceof Blob ? data.size : data.byteLength;

const SHORT_EMOJI_NAME = /^[\w+-]+$/;

export const emojiFromRaw = (emoji: string): EmojiValue =>
  SHORT_EMOJI_NAME.test(emoji)
    ? defaultEmojiResolver.fromSlack(emoji)
    : defaultEmojiResolver.fromGChat(emoji);

/** What `stream` answers for an empty stream: nothing was posted. */
export function emptyMessage(
  conversationId: string,
  inboxId: string,
): InboxMessage {
  const now = nowInstant();

  return {
    id: `empty:${randomToken(9)}`,
    organizationId: "",
    conversationId,
    parentId: undefined,
    threadId: undefined,
    authorId: undefined,
    author: undefined,
    kind: "message",
    body: "",
    document: undefined,
    anchor: undefined,
    mentionIds: [],
    mentionScope: undefined,
    broadcast: false,
    replyCount: 0,
    lastReplyAt: undefined,
    replyUserIds: [],
    pinnedAt: undefined,
    pinnedBy: undefined,
    resolvedAt: undefined,
    resolvedBy: undefined,
    scheduledFor: undefined,
    sentAt: undefined,
    editedAt: undefined,
    deletedAt: undefined,
    createdAt: now,
    attachments: [],
    reactions: [],
    fields: {},
    direction: "outbound",
    authorType: "bot",
    format: "text",
    externalId: null,
    replyTo: null,
    metadata: { empty: true, inbox_id: inboxId },
  };
}

/** The person behind an action or a reaction. */
export interface InboxActor {
  readonly id: string;
  readonly name?: string;
}

/** A button the contact pressed in a card the bot posted. */
export interface InboxActionEvent {
  readonly conversation_id: string;
  readonly message_id: string;
  readonly action_id: string;
  readonly value?: string;
  readonly inbox_id?: string;
  readonly user?: InboxActor;
}

/** A reaction the contact added to or removed from a message. */
export interface InboxReactionEvent {
  readonly conversation_id: string;
  readonly message_id: string;
  /** A unicode emoji or a short name such as `+1`. */
  readonly emoji: string;
  readonly added: boolean;
  readonly inbox_id?: string;
  readonly user?: InboxActor;
}
