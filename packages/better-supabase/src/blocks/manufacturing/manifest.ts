import type { BlockOf } from "../define-block.ts";
import type { ManufacturingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { manufacturingEvents } from "./events.ts";
import { createManufacturing } from "./manufacturing.ts";
import { manufacturingSqlOptions } from "./options.ts";
import {
  bomInputSchema,
  productionOrderInputSchema,
  workCenterInputSchema,
} from "./schemas.ts";

/** The `manufacturing` block's manifest (ADR 0029, ADR 0139). */
export const manufacturingBlock: BlockOf<
  "manufacturing",
  typeof createManufacturing,
  ManufacturingEvents
> = defineBlock({
  name: "manufacturing",
  sql: ["manufacturing"],
  options: { manufacturing: manufacturingSqlOptions },
  events: manufacturingEvents,
  schemas: {
    bom: { input: bomInputSchema },
    work_center: { input: workCenterInputSchema },
    production_order: { input: productionOrderInputSchema },
  },
  create: createManufacturing,
  recipes: ["production-order-board"],
  category: "commerce",
});
