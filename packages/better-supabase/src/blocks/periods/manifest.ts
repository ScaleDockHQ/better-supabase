import type { BlockOf } from "../define-block.ts";
import type { PeriodsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { periodsEvents } from "./events.ts";
import { createPeriods } from "./periods.ts";

/** The `periods` block's manifest (ADR 0197). */
export const periodsBlock: BlockOf<
  "periods",
  typeof createPeriods,
  PeriodsEvents
> = defineBlock({
  name: "periods",
  sql: ["periods"],
  events: periodsEvents,
  schemas: {},
  create: createPeriods,
  recipes: [],
  category: "commerce",
});
