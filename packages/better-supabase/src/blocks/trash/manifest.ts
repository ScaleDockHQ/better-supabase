import type { BlockOf } from "../define-block.ts";
import type { TrashEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { trashEvents } from "./events.ts";
import { createTrash } from "./trash.ts";

/** The `trash` block's manifest (ADR 0029). */
export const trashBlock: BlockOf<"trash", typeof createTrash, TrashEvents> =
  defineBlock({
    name: "trash",
    sql: ["trash"],
    options: {
      trash: optionKeys(["subjects", "retentionDays"]),
    },
    events: trashEvents,
    create: createTrash,
    category: "content",
  });
