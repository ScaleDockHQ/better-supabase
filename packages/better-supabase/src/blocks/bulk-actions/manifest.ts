import type { BlockOf } from "../define-block.ts";
import type { BulkActionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBulkActions } from "./bulk-actions.ts";
import { bulkActionsEvents } from "./events.ts";
import { bulkActionsSqlOptions } from "./options.ts";

/** The `bulk-actions` block's manifest (ADR 0029). */
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
  entities: { bulk_run: { mutability: "state-machine" } },
  description:
    "One action over many rows: up to a limit in one call with a result per row, and larger sets as a background run on the jobs queue that runs as the user who started it.",
  recipes: ["bulk-action-bar"],
});
