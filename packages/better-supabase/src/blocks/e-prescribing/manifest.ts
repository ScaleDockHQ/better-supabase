import type { BlockOf } from "../define-block.ts";
import type { EPrescribingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createEPrescribing } from "./e-prescribing.ts";
import { ePrescribingEvents } from "./events.ts";

/** The `e-prescribing` block's manifest (ADR 0029). */
export const ePrescribingBlock: BlockOf<
  "e-prescribing",
  typeof createEPrescribing,
  EPrescribingEvents
> = defineBlock({
  name: "e-prescribing",
  sql: ["e-prescribing"],
  events: ePrescribingEvents,
  schemas: {},
  create: createEPrescribing,
  recipes: [],
  category: "people",
});
