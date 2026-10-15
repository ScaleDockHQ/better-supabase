import type { BlockOf } from "../define-block.ts";
import type { SlaEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { slaEvents } from "./events.ts";
import { createSla } from "./sla.ts";

/** The `sla` block's manifest (ADR 0029). */
export const slaBlock: BlockOf<"sla", typeof createSla, SlaEvents> =
  defineBlock({
    name: "sla",
    sql: ["sla"],
    options: {
      sla: optionKeys(["businessHours", "subjects"]),
    },
    events: slaEvents,
    create: createSla,
    category: "work",
  });
