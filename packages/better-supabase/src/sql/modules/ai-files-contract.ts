import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { extraFieldsArg } from "../shared.ts";

/** The keys a file read returns, which no extra column may shadow. */
export const FILE_KEYS: readonly string[] = [
  "id",
  "organization_id",
  "owner_id",
  "chat_id",
  "project_id",
  "bucket",
  "path",
  "media_type",
  "filename",
  "byte_size",
  "sha256",
  "status",
  "source",
  "created_at",
  "uploaded_at",
  "expires_at",
  "fields",
];

/** The functions ai-files exposes, with the extra column arguments. */
export function contract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("files", FILE_KEYS)).contract;

  return [
    {
      name: "reserve_ai_file",
      args: ["{id}", "text", "text", "bigint", "uuid", "uuid", ...extra],
      returns: "jsonb",
    },
    { name: "confirm_ai_file", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_ai_file", args: ["uuid"], returns: "jsonb" },
    { name: "get_ai_file_by_path", args: ["text", "text"], returns: "jsonb" },
    { name: "list_ai_files", args: ["uuid"], returns: "jsonb" },
    { name: "delete_ai_file", args: ["uuid"], returns: "jsonb" },
    {
      name: "store_ai_file",
      args: [
        "{id}",
        "uuid",
        "text",
        "text",
        "bigint",
        "uuid",
        "text",
        "text",
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "set_ai_provider_file",
      args: ["uuid", "text", "text", "timestamptz"],
      returns: "boolean",
    },
    { name: "get_ai_provider_file", args: ["uuid", "text"], returns: "jsonb" },
    {
      name: "expiring_ai_provider_files",
      args: ["interval", "integer"],
      returns: "jsonb",
    },
    { name: "purge_ai_files", args: ["interval", "integer"], returns: "jsonb" },
    {
      name: "create_ai_document",
      args: ["{id}", "text", "text", "text", "uuid", "text", "uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "update_ai_document",
      args: ["uuid", "text", "text", "text", "integer", "text"],
      returns: "jsonb",
    },
    {
      name: "rollback_ai_document",
      args: ["uuid", "integer"],
      returns: "jsonb",
    },
    { name: "get_ai_document", args: ["uuid"], returns: "jsonb" },
    { name: "list_ai_document_versions", args: ["uuid"], returns: "jsonb" },
    {
      name: "suggest_ai_document_edit",
      args: ["uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "list_ai_suggestions",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "resolve_ai_suggestion",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    { name: "delete_ai_document", args: ["uuid"], returns: "boolean" },
  ];
}
