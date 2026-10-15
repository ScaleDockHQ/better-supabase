import type { BlockOf } from "../define-block.ts";
import type { EngagementsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createEngagements } from "./engagements.ts";
import { engagementsEvents } from "./events.ts";
import { engagementsSqlOptions } from "./options.ts";

/** The `engagements` block's manifest (ADR 0029). */
export const engagementsBlock: BlockOf<
  "engagements",
  typeof createEngagements,
  EngagementsEvents
> = defineBlock({
  name: "engagements",
  sql: ["engagements"],
  options: {
    engagements: engagementsSqlOptions,
  },
  events: engagementsEvents,
  create: createEngagements,
  category: "crm",
});
