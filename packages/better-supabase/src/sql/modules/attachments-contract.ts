import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";

import {
  attachmentImportTargets,
  documentsOn,
  typesOn,
} from "./attachments-documents.ts";

/**
 * The attachments functions the module exposes; extra is the contract of
 * create_attachment's `fields` argument.
 */
export function attachmentsContract(
  ctx: BlockSqlContext,
  extra: readonly string[],
): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "attachment_object_allowed",
      args: ["text", "text", "text"],
      returns: "boolean",
    },
    { name: "object_clean", args: ["text", "text"], returns: "boolean" },
    {
      name: "set_object_scan",
      args: ["text", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "create_attachment",
      args: [
        "{id}",
        "text",
        "text",
        "bigint",
        "text",
        "text",
        "jsonb",
        "integer",
        "integer",
        "integer",
        ...(documentsOn(ctx) ? ["text", "text", "text", "text"] : []),
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "confirm_attachment", args: ["uuid"], returns: "jsonb" },
    {
      name: "set_attachment_status",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "list_attachments",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    { name: "get_attachment", args: ["uuid"], returns: "jsonb" },
    { name: "delete_attachment", args: ["uuid"], returns: "boolean" },
    {
      name: "replace_attachment",
      args: ["uuid", "text", "text", "bigint", "integer", "integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "restore_attachment_version",
      args: ["uuid", "integer"],
      returns: "jsonb",
    },
    { name: "list_attachment_versions", args: ["uuid"], returns: "jsonb" },
    ...(documentsOn(ctx)
      ? [
          { name: "claim_attachment_upload", args: ["uuid"], returns: "jsonb" },
          { name: "mark_attachment_missing", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
    ...(typesOn(ctx)
      ? [
          { name: "attachment_schema_error", args: ["jsonb"], returns: "text" },
          {
            name: "attachment_fields_error",
            args: ["jsonb", "jsonb"],
            returns: "text",
          },
          {
            name: "define_attachment_document_type",
            args: ["{id}", "text", "text", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "list_attachment_document_types",
            args: ["{id}"],
            returns: "jsonb",
          },
          {
            name: "delete_attachment_document_type",
            args: ["{id}", "text"],
            returns: "boolean",
          },
        ]
      : []),
    ...(ctx.installed("profiles")
      ? [{ name: "attachment_authors", args: ["uuid[]"], returns: "jsonb" }]
      : []),
  ];
}

/** What attachments adds to the subject functions. */
export const ATTACHMENTS_CONTRIBUTES: BlockContributes = {
  imports: attachmentImportTargets,
  subjects: (own) => [
    {
      summary: {
        name: "attachments",
        from: `${own.table("attachments")} x`,
        subjectType: `x.${own.col("attachments", "subjectType")}`,
        subjectId: `x.${own.col("attachments", "subjectId")}`,
        latest: `x.${own.col("attachments", "uploadedAt")}`,
        live: `x.${own.col("attachments", "uploadedAt")} is not null and x.${own.col("attachments", "status")} <> 'infected'`,
      },
    },
  ],
};
