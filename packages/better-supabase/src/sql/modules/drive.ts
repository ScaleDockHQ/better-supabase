import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { driveCoreSql } from "./drive-core.ts";
import { driveFilesSql } from "./drive-files.ts";
import {
  FILE_EVENTS,
  NAMES,
  driveKit,
  driveSubjectType,
  labelTags,
} from "./drive-kit.ts";
import { shareLinkRow } from "./share-links.ts";

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const drive = ctx.of("drive");
  const drives = drive.flag("drives", false);
  const hold = drive.has("nodes", "legalHoldUntil");

  return [
    { name: "drive_role", args: ["uuid"], returns: "text" },
    { name: "drive_can", args: ["uuid", "text"], returns: "boolean" },
    {
      name: "drive_create_folder",
      args: ["{id}", "uuid", "text", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "drive_get", args: ["uuid"], returns: "jsonb" },
    {
      name: "drive_list",
      args: ["{id}", "uuid", "integer", "integer", "uuid"],
      returns: "jsonb",
    },
    { name: "drive_shared", args: ["{id}", "integer"], returns: "jsonb" },
    { name: "drive_path", args: ["uuid"], returns: "jsonb" },
    {
      name: "drive_move",
      args: ["uuid", "uuid", "text", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "drive_rename", args: ["uuid", "text", "text"], returns: "jsonb" },
    { name: "drive_delete", args: ["uuid"], returns: "boolean" },
    {
      name: "drive_share",
      args: ["uuid", "text", "text", "text", "timestamptz"],
      returns: "jsonb",
    },
    {
      name: "drive_unshare",
      args: ["uuid", "text", "text"],
      returns: "boolean",
    },
    { name: "drive_grants", args: ["uuid"], returns: "jsonb" },
    { name: "drive_node_held", args: ["uuid"], returns: "boolean" },
    { name: "drive_node_readable", args: ["uuid"], returns: "boolean" },
    { name: "drive_node_writable", args: ["uuid"], returns: "boolean" },
    ...(hold
      ? [
          {
            name: "drive_hold",
            args: ["uuid", "timestamptz"],
            returns: "jsonb",
          },
          { name: "drive_release_hold", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
    ...(drives
      ? [
          { name: "drive_drive_role", args: ["uuid"], returns: "text" },
          {
            name: "drive_drive_can",
            args: ["uuid", "text"],
            returns: "boolean",
          },
          {
            name: "drive_create_drive",
            args: ["{id}", "text", "text", "uuid", "uuid"],
            returns: "jsonb",
          },
          { name: "drive_get_drive", args: ["uuid"], returns: "jsonb" },
          {
            name: "drive_list_drives",
            args: ["{id}", "integer", "integer"],
            returns: "jsonb",
          },
          {
            name: "drive_rename_drive",
            args: ["uuid", "text"],
            returns: "jsonb",
          },
          { name: "drive_delete_drive", args: ["uuid"], returns: "boolean" },
          {
            name: "drive_share_drive",
            args: ["uuid", "text", "text", "text", "timestamptz"],
            returns: "jsonb",
          },
          {
            name: "drive_unshare_drive",
            args: ["uuid", "text", "text"],
            returns: "boolean",
          },
          { name: "drive_grants_for_drive", args: ["uuid"], returns: "jsonb" },
          {
            name: "drive_connect",
            args: ["{id}", "text", "text"],
            returns: "jsonb",
          },
          { name: "drive_disconnect", args: ["uuid"], returns: "boolean" },
          {
            name: "drive_list_connections",
            args: ["{id}", "integer"],
            returns: "jsonb",
          },
          {
            name: "drive_sync_batch",
            args: ["uuid", "jsonb", "text", "text", "boolean", "text"],
            returns: "integer",
          },
        ]
      : []),
  ];
}

function fileContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!ctx.installed("drive") || !ctx.installed("attachments")) {
    return [];
  }

  if (!ctx.of("drive").has("nodes", "attachment")) {
    return [];
  }

  return [
    {
      name: "drive_create_file",
      args: ["{id}", "uuid", "text", "text", "bigint", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "drive_commit", args: ["uuid", "uuid"], returns: "jsonb" },
    ...(labelTags(ctx) === undefined
      ? []
      : [
          {
            name: "drive_label",
            args: ["uuid", "uuid", "boolean"],
            returns: "jsonb",
          },
          {
            name: "drive_labeled",
            args: ["{id}", "uuid", "integer"],
            returns: "jsonb",
          },
        ]),
    ...(ctx.installed("approvals") && ctx.of("approvals").mode !== "custom"
      ? [
          {
            name: "drive_request_approval",
            args: ["uuid", "uuid", "text"],
            returns: "jsonb",
          },
          { name: "drive_approvals", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
  ];
}

const INTEGRATES = [
  "outbox",
  "audit",
  "attachments",
  "versions",
  "trash",
  "teams",
  "share-links",
] as const;

/**
 * The tree, grants and sharing. It renders before the modules that read
 * subjects (comments, attachments, versions, trash), so `drive_node` can be one
 * of them; `drive-files` adds what needs those modules.
 */

const CONTRIBUTES: BlockContributes = {
  "share-links": (own) => [
    {
      subject: driveSubjectType(own),
      exists: (subject) => shareLinkRow(own, "nodes", subject),
    },
  ],
};

export const DRIVE: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "drive",
  scopes: ["tenant"],
  title: "Drive",
  description:
    "Folders and files on the attachments module: access granted to users, teams or roles and inherited down the tree, enforced by storage policies too; moves and renames with a name-conflict policy; revisions through versions, a bin through trash, starred and recent items through share-links' user state, and folder share links.",
  requires: ["memberships", "permissions", "drive-files"],
  dependencies: (layout) =>
    layout.modules?.["drive"]?.mode === "custom"
      ? ["memberships", "permissions"]
      : ["memberships", "permissions", "drive-files"],
  before: "comments",
  integrates: [...INTEGRATES],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build: (ctx) =>
    ctx.mode === "custom" ? "" : driveCoreSql(driveKit(ctx, ctx)),
};

/** Installed with `drive`: its files, revisions, bin, stars and links. */
export const DRIVE_FILES: BlockSqlDefinition = {
  name: "drive-files",
  scopes: ["tenant"],
  title: "Drive files",
  description:
    "The part of the drive module that needs attachments, versions, trash and share-links: file uploads and revisions, storage policies, the bin, starred and recent items, folder share links and the purge event. Installed with drive.",
  requires: ["attachments"],
  dependencies: (layout) =>
    layout.modules?.["drive"]?.columns?.["nodes"]?.["attachment"] === null
      ? []
      : ["attachments"],
  integrates: ["drive", ...INTEGRATES, "tags", "approvals"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: { tables: {}, events: FILE_EVENTS },
  contract: fileContract,
  build: (ctx) => {
    if (ctx.mode === "custom" || !ctx.installed("drive")) {
      return "";
    }

    const drive = ctx.of("drive");

    return drive.mode === "custom" ? "" : driveFilesSql(driveKit(drive, ctx));
  },
};
