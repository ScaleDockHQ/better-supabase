import type { BlockOf } from "../define-block.ts";
import type { WarehouseEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { warehouseEvents } from "./events.ts";
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
});
