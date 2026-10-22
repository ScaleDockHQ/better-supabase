import type { BlockOf } from "../define-block.ts";
import type { BulkActionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBulkActions } from "./bulk-actions.ts";
import { bulkActionsEvents } from "./events.ts";
import { bulkActionsSqlOptions } from "./options.ts";

/** The `bulk` block's manifest (ADR 0029). */
export const bulkActionsBlock: BlockOf<
  "bulk-actions",
  typeof createBulkActions,
  BulkActionsEvents
> = defineBlock({
  name: "bulk-actions",
  sql: ["bulk-actions"],
  options: { "bulk-actions": bulkActionsSqlOptions },
  events: bulkActionsEvents,
  create: createBulkActions,
  category: "work",
  recipes: ["bulk-action-bar"],
});
