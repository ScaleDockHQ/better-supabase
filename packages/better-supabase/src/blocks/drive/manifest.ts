import type { BlockOf } from "../define-block.ts";
import type { DriveEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createDrive } from "./drive.ts";
import { driveEvents } from "./events.ts";

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
    drive: optionKeys([
      "roles",
      "writeRole",
      "shareRole",
      "memberRole",
      "subjectType",
      "conflict",
      "extraColumns",
    ]),
  },
  events: driveEvents,
  consumes: { attachments: "optional" },
  create: createDrive,
  category: "content",
});
