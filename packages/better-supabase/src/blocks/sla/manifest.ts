import type { BlockOf } from "../define-block.ts";
import type { SlaEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { slaEvents } from "./events.ts";
import { slaSqlOptions } from "./options.ts";
import { slaBinding } from "./record-binding.ts";
import { createSla } from "./sla.ts";

/** The `sla` block's manifest (ADR 0029). */
export const slaBlock: BlockOf<
  "sla",
  typeof createSla,
  SlaEvents,
  Record<never, never>,
  never,
  typeof slaBinding
> = defineBlock({
  name: "sla",
  schedules: [
    {
      name: "check",
      cron: "* * * * *",
      runs: "check()",
      description: "Records the warnings and breaches of the running clocks.",
    },
  ],
  sql: ["sla"],
  options: { sla: slaSqlOptions },
  events: slaEvents,
  create: createSla,
  record: slaBinding,
  category: "work",
  recipes: ["sla-badges"],
});
