import type { ModuleContext, ModuleContractFunction } from "../context.ts";

/**
 * The attachments functions the module exposes; extra is the contract of
 * create_attachment's `fields` argument.
 */
export function attachmentsContract(
  ctx: ModuleContext,
  extra: readonly string[],
): readonly ModuleContractFunction[] {
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
    ...(ctx.installed("profiles")
      ? [{ name: "attachment_authors", args: ["uuid[]"], returns: "jsonb" }]
      : []),
  ];
}
