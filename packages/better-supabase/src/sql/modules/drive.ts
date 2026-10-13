import type { ModuleContext, ModuleContractFunction } from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { driveCoreSql } from "./drive-core.ts";
import { driveFilesSql } from "./drive-files.ts";
import { FILE_EVENTS, NAMES, driveKit, driveSubjectType } from "./drive-kit.ts";

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "drive_role", args: ["uuid"], returns: "text" },
    { name: "drive_can", args: ["uuid", "text"], returns: "boolean" },
    {
      name: "drive_create_folder",
      args: ["{id}", "uuid", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "drive_get", args: ["uuid"], returns: "jsonb" },
    {
      name: "drive_list",
      args: ["{id}", "uuid", "integer", "integer"],
      returns: "jsonb",
    },
    {
      name: "drive_move",
      args: ["uuid", "uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "drive_rename", args: ["uuid", "text", "text"], returns: "jsonb" },
    {
      name: "drive_share",
      args: ["uuid", "text", "text", "text", "timestamptz"],
      returns: "jsonb",
    },
  ];
}

function fileContract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  if (!ctx.installed("drive") || !ctx.installed("attachments")) return [];
  if (!ctx.of("drive").has("nodes", "attachment")) return [];
  return [
    {
      name: "drive_create_file",
      args: ["{id}", "uuid", "text", "text", "bigint", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "drive_commit", args: ["uuid", "uuid"], returns: "jsonb" },
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
 * subjects (comments, attachments, versions, trash), so `drive_node` can be
 * one of them; `drive-files` adds what needs those modules.
 */
export const DRIVE: ModuleDefinition = {
  name: "drive",
  title: "Drive",
  description:
    "Folders and files on the attachments module: access granted to users, teams or roles and inherited down the tree, enforced by storage policies too; moves and renames with a name-conflict policy; revisions through versions, a bin through trash, starred and recent items through share-links' user state, and folder share links.",
  requires: ["tenant", "access", "drive-files"],
  integrates: [...INTEGRATES],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  adoptOptional: (ctx) => ({
    grants: ctx.has("grants", "principalType")
      ? ["user", "team"]
      : ["principalType", "principalId"],
  }),
  contract,
  build: (ctx) =>
    ctx.mode === "custom" ? "" : driveCoreSql(driveKit(ctx, ctx)),
};

/** Installed with `drive`: its files, revisions, bin, stars and links. */
export const DRIVE_FILES: ModuleDefinition = {
  name: "drive-files",
  title: "Drive files",
  description:
    "The part of the drive module that needs attachments, versions, trash and share-links: file uploads and revisions, storage policies, the bin, starred and recent items, folder share links and the purge event. Installed with drive.",
  requires: ["attachments"],
  dependencies: (layout) =>
    layout.modules?.["drive"]?.columns?.["nodes"]?.["attachment"] === null
      ? []
      : ["attachments"],
  integrates: ["drive", ...INTEGRATES],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: { tables: {}, events: FILE_EVENTS },
  contract: fileContract,
  build: (ctx) => {
    if (ctx.mode === "custom" || !ctx.installed("drive")) return "";
    const drive = ctx.of("drive");
    return drive.mode === "custom" ? "" : driveFilesSql(driveKit(drive, ctx));
  },
};

export { driveSubjectType };
