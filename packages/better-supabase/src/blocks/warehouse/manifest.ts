import type { BlockOf } from "../define-block.ts";
import type { WarehouseEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { warehouseEvents } from "./events.ts";
import { pickListListSurface } from "./lists.ts";
import {
  countPlanInputSchema,
  pickListInputSchema,
  pickRecordSchema,
  pickWaveInputSchema,
} from "./schemas.ts";
import { createWarehouse } from "./warehouse.ts";

/** The `warehouse` block's manifest (ADR 0029). */
export const warehouseBlock: BlockOf<
  "warehouse",
  typeof createWarehouse,
  WarehouseEvents
> = defineBlock({
  name: "warehouse",
  sql: ["warehouse"],
  events: warehouseEvents,
  schemas: {
    pick_wave: { input: pickWaveInputSchema },
    pick_list: { input: pickListInputSchema },
    pick_line: { input: pickRecordSchema },
    count_plan: { input: countPlanInputSchema },
  },
  create: createWarehouse,
  recipes: [],
  category: "commerce",
  entities: {
    pick_list: {
      ...pickListListSurface,
      mutability: "state-machine",
      emits: { create: true },
    },
    pick_wave: { mutability: "state-machine", emits: { create: true } },
    pick_line: { mutability: "read-only" },
    count_plan: { mutability: "state-machine", emits: { create: true } },
    putaway_rule: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
    bin_slot: { mutability: "editable", emits: { update: false } },
    variant_size: { mutability: "editable", emits: { update: false } },
  },
  description:
    "Warehouse work over inventory: pick waves and pick lists made from stock allocations, picking tasks as work items, confirmed bins, lots and serials, and cycle count plans that hold large variances for review.",
});
