import type { BlockOf } from "../define-block.ts";
import type { InventoryEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { inventoryEvents } from "./events.ts";
import { createInventory } from "./inventory.ts";
import { inventorySqlOptions } from "./options.ts";

/** The `inventory` block's manifest (ADR 0029). */
export const inventoryBlock: BlockOf<
  "inventory",
  typeof createInventory,
  InventoryEvents
> = defineBlock({
  name: "inventory",
  sql: ["inventory"],
  options: { inventory: inventorySqlOptions },
  events: inventoryEvents,
  create: createInventory,
  category: "commerce",
  recipes: ["inventory-table"],
});
