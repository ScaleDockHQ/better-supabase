import type { BlockOf } from "../define-block.ts";
import type { DriveEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDrive } from "./drive.ts";
import { driveEvents } from "./events.ts";
import { driveSqlOptions } from "./options.ts";

/** The `drive` block's manifest (ADR 0029). */
export const driveBlock: BlockOf<
  "drive",
  typeof createDrive,
  DriveEvents,
  { readonly attachments: "optional" }
> = defineBlock({
  name: "drive",
  sql: ["drive", "drive-files"],
  options: {
    drive: driveSqlOptions,
  },
  events: driveEvents,
  consumes: { attachments: "optional" },
  create: createDrive,
  category: "content",
});
