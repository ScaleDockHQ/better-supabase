import type {
  Message,
  MessageEdit,
  MessageFile,
  MessageReaction,
} from "./messaging.ts";

import { authorOf } from "../../core/block-authors.ts";
import {
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** The private Realtime topic of a conversation's message pings. */
export function conversationTopic(
  conversationId: string,
  topic = "messages",
): string {
  return `${topic}:${conversationId}`;
}

export const num = (value: unknown): number => {
  const n = typeof value === "string" ? Number(value) : value;

  return typeof n === "number" && Number.isFinite(n) ? n : 0;
};

function filesOf(value: unknown): readonly MessageFile[] {
  return Array.isArray(value)
    ? value
        .filter(isRecord)
        .map((file) => ({
          id: textOf(file["id"]),
          name: textOf(file["name"]),
          mimeType: optionalText(file["mimeType"]),
          size: file["size"] === null ? undefined : num(file["size"]),
          status: textOf(file["status"]),
        }))
    : [];
}

export function reactionsOf(value: unknown): readonly MessageReaction[] {
  return Array.isArray(value)
    ? value
        .filter(isRecord)
        .map((reaction) => ({
          emoji: textOf(reaction["emoji"]),
          count: num(reaction["count"]),
          reacted: reaction["reacted"] === true,
          actors: stringsOf(reaction["actors"]),
        }))
    : [];
}

/** A message row from the messaging functions. */
export function messageOf(value: unknown): Message {
  const row = recordOf(value, "message");
  const scope = optionalText(row["mention_scope"]);
  const extra = isRecord(row["fields"]) ? row["fields"] : {};

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    conversationId: textOf(row["conversation_id"]),
    parentId: optionalText(row["parent_id"]),
    threadId: optionalText(row["thread_id"]),
    authorId: optionalText(row["author_id"]),
    author: authorOf(row["author"]),
    kind: row["kind"] === "note" ? "note" : "message",
    body: textOf(row["body"] ?? ""),
    document: row["document"] ?? undefined,
    anchor: row["anchor"] ?? undefined,
    mentionIds: stringsOf(row["mentions"]),
    mentionScope:
      scope === undefined
        ? undefined
        : enumOrThrow(scope, ["channel", "here"] as const, "mention scope"),
    broadcast: row["broadcast"] === true,
    replyCount: num(row["reply_count"]),
    lastReplyAt: optionalInstant(row["last_reply_at"]),
    replyUserIds: stringsOf(row["reply_user_ids"]),
    pinnedAt: optionalInstant(row["pinned_at"]),
    pinnedBy: optionalText(row["pinned_by"]),
    resolvedAt: optionalInstant(row["resolved_at"]),
    resolvedBy: optionalText(row["resolved_by"]),
    scheduledFor: optionalInstant(row["scheduled_for"]),
    sentAt: optionalInstant(row["sent_at"]),
    editedAt: optionalInstant(row["edited_at"]),
    deletedAt: optionalInstant(row["deleted_at"]),
    createdAt: requiredInstant(row["created_at"], "createdAt"),
    attachments: filesOf(row["attachments"]),
    reactions: reactionsOf(row["reactions"]),
    fields: extra,
  };
}

/** An earlier version from `list_message_edits`. */
export function editOf(value: unknown): MessageEdit {
  const row = recordOf(value, "message edit");

  return {
    id: textOf(row["id"]),
    messageId: textOf(row["message_id"]),
    body: textOf(row["body"]),
    document: row["document"] ?? undefined,
    editedBy: optionalText(row["edited_by"]),
    editedAt: requiredInstant(row["edited_at"], "editedAt"),
  };
}
