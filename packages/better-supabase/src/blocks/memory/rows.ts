import type {
  MemoryDocument,
  MemoryHit,
  MemoryRecord,
  MemoryScope,
  MemoryView,
  RecalledMessage,
} from "./types.ts";

import {
  isRecord,
  oneOf,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";

const SCOPES: readonly MemoryScope[] = [
  "user",
  "agent",
  "chat",
  "organization",
];

const scopeOf = (value: unknown): MemoryScope =>
  oneOf(textOf(value), SCOPES, "user");

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

export function memoryOf(value: unknown): MemoryRecord {
  const row = recordOf(value, "memories");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: optionalText(row["owner_id"]),
    scope: scopeOf(row["scope"]),
    agentId: optionalText(row["agent_id"]),
    chatId: optionalText(row["chat_id"]),
    kind: row["kind"] === "core" ? "core" : "archival",
    path: optionalText(row["path"]),
    content: textOf(row["content"]),
    version: Number(row["version"] ?? 1),
    embeddingModel: optionalText(row["embedding_model"]),
    sourceMessageId: optionalText(row["source_message_id"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

export function hitOf(value: unknown): MemoryHit {
  const row = recordOf(value, "memory_search");
  const similarity = row["similarity"];
  return {
    ...memoryOf(row),
    score: Number(row["score"]),
    similarity: typeof similarity === "number" ? similarity : undefined,
  };
}

export function viewOf(value: unknown): MemoryView | undefined {
  if (!isRecord(value)) return undefined;
  if (value["type"] === "file") {
    return {
      type: "file",
      path: textOf(value["path"]),
      content: textOf(value["content"]),
      version: Number(value["version"]),
    };
  }
  return {
    type: "directory",
    path: textOf(value["path"]),
    entries: recordsOf(value["entries"], "memory_view").map((entry) => ({
      path: textOf(entry["path"]),
      size: Number(entry["size"]),
    })),
  };
}

export function documentOf(value: unknown): MemoryDocument {
  const row = recordOf(value, "memory_document");
  return { content: textOf(row["content"]), version: textOf(row["version"]) };
}

export function recalledOf(value: unknown): readonly RecalledMessage[] {
  return recordsOf(value, "recall_ai_messages").map((row) => ({
    chatId: textOf(row["chat_id"]),
    messageId: textOf(row["message_id"]),
    similarity: Number(row["similarity"]),
  }));
}
