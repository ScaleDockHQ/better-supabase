import type {
  AiDocument,
  AiDocumentKind,
  AiDocumentVersion,
  AiFile,
  AiFileSource,
  AiFileStatus,
  AiProviderFile,
  AiSuggestion,
} from "./types.ts";

import {
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  textOf,
  toInstant,
} from "../shared.ts";

const FILE_STATUSES: readonly AiFileStatus[] = ["pending", "ready", "failed"];
const FILE_SOURCES: readonly AiFileSource[] = [
  "upload",
  "generated",
  "provider",
];
const DOCUMENT_KINDS: readonly AiDocumentKind[] = [
  "text",
  "code",
  "sheet",
  "image",
];

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

export function fileOf(value: unknown): AiFile {
  const row = recordOf(value, "ai_files");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: textOf(row["owner_id"]),
    chatId: optionalText(row["chat_id"]),
    projectId: optionalText(row["project_id"]),
    bucket: textOf(row["bucket"]),
    path: textOf(row["path"]),
    mediaType: textOf(row["media_type"]),
    filename: textOf(row["filename"]),
    size: Number(row["byte_size"] ?? 0),
    sha256: optionalText(row["sha256"]),
    status: oneOf(textOf(row["status"]), FILE_STATUSES, "failed"),
    source: oneOf(textOf(row["source"]), FILE_SOURCES, "upload"),
    createdAt: instant(row["created_at"]),
    uploadedAt: optionalInstant(row["uploaded_at"]),
    expiresAt: optionalInstant(row["expires_at"]),
  };
}

export function providerFileOf(value: unknown): AiProviderFile {
  const row = recordOf(value, "ai_provider_files");
  return {
    fileId: textOf(row["file_id"]),
    provider: textOf(row["provider"]),
    reference: textOf(row["reference"]),
    expiresAt: optionalInstant(row["expires_at"]),
  };
}

export function documentOf(value: unknown): AiDocument {
  const row = recordOf(value, "ai_documents");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: textOf(row["owner_id"]),
    chatId: optionalText(row["chat_id"]),
    kind: oneOf(textOf(row["kind"]), DOCUMENT_KINDS, "text"),
    title: textOf(row["title"]),
    version: Number(row["current_version"] ?? 1),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

export function versionOf(value: unknown): AiDocumentVersion {
  const row = recordOf(value, "ai_document_versions");
  return {
    documentId: textOf(row["document_id"]),
    version: Number(row["version"]),
    content: optionalText(row["content"]),
    storagePath: optionalText(row["storage_path"]),
    messageId: optionalText(row["created_by_message_id"]),
    createdBy: optionalText(row["created_by"]),
    createdAt: instant(row["created_at"]),
  };
}

export function suggestionOf(value: unknown): AiSuggestion {
  const row = recordOf(value, "ai_suggestions");
  const accepted = row["accepted"];
  return {
    id: textOf(row["id"]),
    documentId: textOf(row["document_id"]),
    version: Number(row["version"]),
    originalText: textOf(row["original_text"]),
    suggestedText: textOf(row["suggested_text"]),
    description: optionalText(row["description"]),
    createdBy: optionalText(row["created_by"]),
    createdAt: instant(row["created_at"]),
    resolvedAt: optionalInstant(row["resolved_at"]),
    accepted: typeof accepted === "boolean" ? accepted : undefined,
  };
}
