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
  entities: {
    inventory_location: { mutability: "read-only" },
    purchase_order: { mutability: "editable", emits: { update: false } },
    purchase_requisition: {
      mutability: "state-machine",
      emits: { create: true },
    },
    inventory_receipt: { mutability: "append-only", emits: { create: true } },
  },
  description:
    "Stock per catalog variant and location in a unit with decimals: movements posted to the ledger block, lots, serial numbers, expiry, bins, weighted average cost, reservations with expiry, allocations with backorders, transfers, purchase requisitions with approval, and purchase orders with partial receiving into goods receipts.",
  recipes: ["inventory-table"],
});
