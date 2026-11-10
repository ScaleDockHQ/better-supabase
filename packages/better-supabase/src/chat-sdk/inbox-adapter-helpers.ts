import type {
  AdapterPostableMessage,
  Attachment,
  EmojiValue,
  Root,
  StreamChunk,
} from "chat";

import {
  BaseFormatConverter,
  ChatError,
  defaultEmojiResolver,
  NotImplementedError,
  parseMarkdown,
  RateLimitError,
  stringifyMarkdown,
} from "chat";

import type { Conversation, InboxMessage } from "../blocks/inbox/types.ts";
import type { MessageFile } from "../blocks/messaging/messaging.ts";
import type { DbError, DbErrorKind } from "../core/errors.ts";
import type { AsyncResult } from "../core/result.ts";

import { isRecord, toInstant } from "../core/block-helpers.ts";

export const PREFIX = "inbox:";

class MarkdownConverter extends BaseFormatConverter {
  fromAst(ast: Root): string {
    return stringifyMarkdown(ast).trimEnd();
  }
  toAst(text: string): Root {
    return parseMarkdown(text);
  }
}

export const converter: BaseFormatConverter = new MarkdownConverter();

const CHAT_ERROR_CODES: Readonly<Record<DbErrorKind, string>> = {
  not_found: "NOT_FOUND",
  unauthorized: "AUTH_FAILED",
  forbidden: "PERMISSION_DENIED",
  conflict: "CONFLICT",
  foreign_key: "VALIDATION_ERROR",
  check: "VALIDATION_ERROR",
  not_null: "VALIDATION_ERROR",
  exclusion: "CONFLICT",
  invalid_input: "VALIDATION_ERROR",
  invalid_value: "VALIDATION_ERROR",
  raised: "VALIDATION_ERROR",
  timeout: "NETWORK_ERROR",
  serialization: "CONFLICT",
  network: "NETWORK_ERROR",
  aborted: "ABORTED",
  invalid_request: "VALIDATION_ERROR",
  validation: "VALIDATION_ERROR",
  multiple_rows: "CONFLICT",
  stale: "CONFLICT",
  max_affected: "CONFLICT",
  rate_limited: "RATE_LIMITED",
  quota_exceeded: "RATE_LIMITED",
  truncated: "PAYLOAD_TOO_LARGE",
  unsupported: "NOT_IMPLEMENTED",
  unexpected: "UNEXPECTED",
};

/**
 * A `DbError` as the error Chat SDK adapters throw: `RateLimitError` with
 * `retryAfterMs` for `rate_limited` and `quota_exceeded`, `NotImplementedError`
 * for `unsupported`, and otherwise a `ChatError` whose code follows the adapter
 * codes (`NOT_FOUND`, `AUTH_FAILED`, `PERMISSION_DENIED`, `VALIDATION_ERROR`,
 * `NETWORK_ERROR`). The `DbError` is the `cause`.
 */
export function chatErrorOf(error: DbError): ChatError {
  if (error.kind === "rate_limited" || error.kind === "quota_exceeded") {
    return new RateLimitError(
      error.message,
      error.retryAfter === undefined ? undefined : error.retryAfter * 1000,
      error,
    );
  }

  if (error.kind === "unsupported") {
    return new NotImplementedError(error.message, error.table, error);
  }

  return new ChatError(error.message, CHAT_ERROR_CODES[error.kind], error);
}

export async function must<T>(result: AsyncResult<T>): Promise<T> {
  const settled = await result;

  if (!settled.ok) {
    throw chatErrorOf(settled.error);
  }

  return settled.data;
}

/** The card in a message, kept in `metadata.card` for a client to render. */
export function cardOf(message: AdapterPostableMessage): unknown {
  if (typeof message !== "object") {
    return undefined;
  }

  if ("card" in message) {
    return message.card;
  }

  return "type" in message ? message : undefined;
}

export function bodyOf(message: AdapterPostableMessage): {
  readonly body: string;
  readonly format: "text" | "markdown";
} {
  if (typeof message === "string") {
    return { body: message, format: "text" };
  }

  if ("raw" in message) {
    return { body: message.raw, format: "text" };
  }

  if ("markdown" in message) {
    return { body: message.markdown, format: "markdown" };
  }

  return { body: converter.renderPostable(message), format: "markdown" };
}

export function inboxIdOfChannel(channelId: string): string {
  const inboxId = channelId.startsWith(PREFIX)
    ? channelId.slice(PREFIX.length)
    : "";

  if (inboxId.length === 0 || inboxId.includes(":")) {
    throw new ChatError(
      `"${channelId}" is not an inbox channel id`,
      "INVALID_CHANNEL_ID",
    );
  }

  return inboxId;
}

export type ConversationCursor = Pick<Conversation, "id" | "lastMessageAt">;

export function encodeCursor(conversation: ConversationCursor): string {
  return JSON.stringify({
    id: conversation.id,
    lastMessageAt: conversation.lastMessageAt?.toString() ?? null,
  });
}

export function decodeCursor(cursor: string): ConversationCursor {
  let value: unknown;

  try {
    value = JSON.parse(cursor);
  } catch {
    value = undefined;
  }

  if (
    !isRecord(value) ||
    typeof value["id"] !== "string" ||
    (value["lastMessageAt"] !== null &&
      typeof value["lastMessageAt"] !== "string")
  ) {
    throw new ChatError("invalid listThreads cursor", "VALIDATION_ERROR");
  }

  return {
    id: value["id"],
    lastMessageAt:
      value["lastMessageAt"] === null
        ? null
        : toInstant(value["lastMessageAt"]),
  };
}

export const emojiOf = (value: EmojiValue | string): string =>
  defaultEmojiResolver.toDiscord(value);

export function attachmentsOf(
  message: InboxMessage,
  download: ((file: MessageFile) => Promise<ArrayBuffer>) | undefined,
): Attachment[] {
  return message.attachments.flatMap((file) => {
    if (file.status !== "clean") {
      return [];
    }

    const type = file.mimeType?.startsWith("image/")
      ? "image"
      : file.mimeType?.startsWith("video/")
        ? "video"
        : file.mimeType?.startsWith("audio/")
          ? "audio"
          : "file";

    return [
      {
        type,
        name: file.name,
        fetchMetadata: { attachmentId: file.id },
        ...(file.mimeType === undefined ? {} : { mimeType: file.mimeType }),
        ...(file.size === undefined ? {} : { size: file.size }),
        ...(download === undefined ? {} : { fetchData: () => download(file) }),
      },
    ];
  });
}

export async function* textOnly(
  source: AsyncIterable<string | StreamChunk>,
): AsyncIterable<string> {
  for await (const chunk of source) {
    if (typeof chunk === "string") {
      yield chunk;
    } else if (chunk.type === "markdown_text") {
      yield chunk.text;
    }
  }
}
