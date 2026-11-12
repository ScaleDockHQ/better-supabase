import type { BlockOf } from "../define-block.ts";
import type { TrashEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { trashEvents } from "./events.ts";
import { trashSqlOptions } from "./options.ts";
import { createTrash } from "./trash.ts";

/** The `trash` block's manifest (ADR 0029). */
export const trashBlock: BlockOf<"trash", typeof createTrash, TrashEvents> =
  defineBlock({
    name: "trash",
    sql: ["trash"],
    options: { trash: trashSqlOptions },
    events: trashEvents,
    create: createTrash,
    category: "database",
    entities: { subject: { mutability: "state-machine" } },
    description:
      "Soft delete through each subject's deletedAt column: trash with children in one batch, restore with unique checks, a list per organization, and purge after a retention period, skipped for subjects under a legal hold.",
    recipes: ["undo-toast", "trash-bin"],
    extension: "trashExtension",
  });
