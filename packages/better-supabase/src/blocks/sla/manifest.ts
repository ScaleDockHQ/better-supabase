import type { BlockOf } from "../define-block.ts";
import type { SlaEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { slaEvents } from "./events.ts";
import { slaSqlOptions } from "./options.ts";
import { slaSection } from "./section.ts";
import { createSla } from "./sla.ts";

/** The `sla` block's manifest (ADR 0029). */
export const slaBlock: BlockOf<
  "sla",
  typeof createSla,
  SlaEvents,
  Record<never, never>,
  never,
  { readonly sla: typeof slaSection }
> = defineBlock({
  name: "sla",
  sql: ["sla"],
  options: { sla: slaSqlOptions },
  events: slaEvents,
  create: createSla,
  sections: { sla: slaSection },
  category: "work",
  recipes: ["sla-badges"],
});
