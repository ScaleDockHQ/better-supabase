import type { BlockOf } from "../define-block.ts";
import type { ManufacturingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { manufacturingEvents } from "./events.ts";
import { productionOrderListSurface } from "./lists.ts";
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
  entities: {
    production_order: {
      ...productionOrderListSurface,
      mutability: "state-machine",
      emits: { create: false },
    },
    bom: { mutability: "editable", emits: { update: false } },
    bom_component: { mutability: "read-only" },
    bom_operation: { mutability: "read-only" },
    work_center: { mutability: "editable", emits: { update: false } },
    production_order_operation: { mutability: "read-only" },
    production_consumption: {
      mutability: "append-only",
      emits: { create: false },
    },
    stock_lot_link: { mutability: "read-only" },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Versioned bills of materials with routings on work centers, production orders numbered MO-2026-0001 that allocate and consume components and receive the output at component plus work center cost through inventory, lot genealogy and recall, and material requirements that suggest purchase and production orders.",
});
