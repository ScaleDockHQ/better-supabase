import type { BlockOf } from "../define-block.ts";
import type { SlaEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { slaEvents } from "./events.ts";
import { slaSqlOptions } from "./options.ts";
import { createSla } from "./sla.ts";

/** The `sla` block's manifest (ADR 0029). */
export const slaBlock: BlockOf<"sla", typeof createSla, SlaEvents> =
  defineBlock({
    name: "sla",
    sql: ["sla"],
    options: { sla: slaSqlOptions },
    events: slaEvents,
    create: createSla,
    category: "work",
    recipes: ["sla-badges"],
  });
