import type { BlockOf } from "../define-block.ts";
import type { WorkItemsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { workItemsEvents } from "./events.ts";
import { workItemsSqlOptions } from "./options.ts";
import {
  workItemChangeSchema,
  workItemInputSchema,
  workItemListFilterSchema,
} from "./schemas.ts";
import { createWorkItems } from "./work-items.ts";

/** The `work-items` block's manifest (ADR 0029). */
export const workItemsBlock: BlockOf<
  "work-items",
  typeof createWorkItems,
  WorkItemsEvents
> = defineBlock({
  name: "work-items",
  sql: ["work-items"],
  options: { "work-items": workItemsSqlOptions },
  events: workItemsEvents,
  create: createWorkItems,
  category: "work",
  recipes: ["work-item-board", "work-item-grid"],
  schemas: {
    work_item: {
      input: workItemInputSchema,
      change: workItemChangeSchema,
      listFilter: workItemListFilterSchema,
    },
  },
});
