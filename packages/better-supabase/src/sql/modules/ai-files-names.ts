import type { BlockSqlNames } from "../context.ts";

export const FILES = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  chat: "chat_id",
  project: "project_id",
  bucket: "bucket",
  path: "path",
  mediaType: "media_type",
  filename: "filename",
  size: "byte_size",
  sha256: "sha256",
  status: "status",
  source: "source",
  createdAt: "created_at",
  uploadedAt: "uploaded_at",
  expiresAt: "expires_at",
} as const;

export const PROVIDER_FILES = {
  file: "file_id",
  provider: "provider",
  reference: "reference",
  expiresAt: "expires_at",
  createdAt: "created_at",
} as const;

export const DOCUMENTS = {
  id: "id",
  tenant: "organization_id",
  owner: "owner_id",
  chat: "chat_id",
  kind: "kind",
  title: "title",
  version: "current_version",
  createdAt: "created_at",
  updatedAt: "updated_at",
} as const;

export const VERSIONS = {
  document: "document_id",
  version: "version",
  content: "content",
  storagePath: "storage_path",
  message: "created_by_message_id",
  createdBy: "created_by",
  createdAt: "created_at",
} as const;

export const SUGGESTIONS = {
  id: "id",
  document: "document_id",
  version: "version",
  original: "original_text",
  suggested: "suggested_text",
  description: "description",
  createdBy: "created_by",
  createdAt: "created_at",
  resolvedAt: "resolved_at",
  accepted: "accepted",
} as const;

export const NAMES: BlockSqlNames = {
  entities: {
    ai_document: { table: "documents", singular: "ai_document", primary: true },
  },
  options: [
    "bucket",
    "maxSize",
    "allowedMimeTypes",
    "pendingTtl",
    "extraColumns",
  ],
  tables: {
    files: {
      name: "ai_files",
      columns: FILES,
      lifecycle: { user: "owner", tenant: "tenant" },
      app: {},
      optional: ["project", "sha256", "source", "uploadedAt", "expiresAt"],
      typed: ["status", "source"],
    },
    providerFiles: {
      name: "ai_provider_files",
      columns: PROVIDER_FILES,
      app: {},
      optional: ["expiresAt", "createdAt"],
    },
    documents: {
      name: "ai_documents",
      columns: DOCUMENTS,
      lifecycle: { user: "owner", tenant: "tenant" },
      app: {},
      optional: ["createdAt", "updatedAt"],
      typed: ["kind"],
    },
    versions: {
      name: "ai_document_versions",
      columns: VERSIONS,
      lifecycle: { user: "createdBy" },
      app: {},
      optional: ["storagePath", "message", "createdBy", "createdAt"],
    },
    suggestions: {
      name: "ai_suggestions",
      columns: SUGGESTIONS,
      lifecycle: { user: "createdBy" },
      app: {},
      optional: ["description", "createdBy", "createdAt"],
    },
  },
};
