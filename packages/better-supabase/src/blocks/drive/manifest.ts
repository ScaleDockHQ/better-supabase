import type { BlockOf } from "../define-block.ts";
import type { DriveEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDrive } from "./drive.ts";
import { driveEvents } from "./events.ts";
import { driveSqlOptions } from "./options.ts";
import { driveBinding } from "./record-binding.ts";

/** The `drive` block's manifest (ADR 0029). */
export const driveBlock: BlockOf<
  "drive",
  typeof createDrive,
  DriveEvents,
  { readonly attachments: "optional"; readonly recordAccess: "optional" },
  never,
  typeof driveBinding
> = defineBlock({
  name: "drive",
  sql: ["drive", "drive-files"],
  options: { drive: driveSqlOptions },
  events: driveEvents,
  consumes: { attachments: "optional", recordAccess: "optional" },
  record: driveBinding,
  create: createDrive,
  category: "content",
  entities: {
    drive_node: { mutability: "state-machine", emits: { create: true } },
  },
  description:
    "Folders and files on the attachments module: access granted to users, teams or roles and inherited down the tree, enforced by storage policies too; moves and renames with a name-conflict policy; revisions through versions, a bin through trash, starred and recent items through share-links' user state, and folder share links.",
  recipes: [
    "grants-editor",
    "drive-explorer",
    "file-request-upload",
    "document-register",
  ],
});
