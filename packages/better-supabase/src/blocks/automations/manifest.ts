import type { BlockOf } from "../define-block.ts";
import type { AutomationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAutomations } from "./automations.ts";
import { automationsEvents } from "./events.ts";
import { automationsSqlOptions } from "./options.ts";

/** The `rules` block's manifest (ADR 0029). */
export const automationsBlock: BlockOf<
  "automations",
  typeof createAutomations,
  AutomationsEvents
> = defineBlock({
  name: "automations",
  sql: ["automations"],
  options: { automations: automationsSqlOptions },
  events: automationsEvents,
  create: createAutomations,
  category: "automation",
  recipes: ["rule-builder"],
});
