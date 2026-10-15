import type { BlockOf } from "../define-block.ts";
import type { InventoryEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { inventoryEvents } from "./events.ts";
import { createInventory } from "./inventory.ts";

/** The `inventory` block's manifest (ADR 0029). */
export const inventoryBlock: BlockOf<
  "inventory",
  typeof createInventory,
  InventoryEvents
> = defineBlock({
  name: "inventory",
  sql: ["inventory"],
  events: inventoryEvents,
  create: createInventory,
  category: "commerce",
});
