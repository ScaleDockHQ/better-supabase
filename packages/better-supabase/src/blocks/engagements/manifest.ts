import type { BlockOf } from "../define-block.ts";
import type { EngagementsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createEngagements } from "./engagements.ts";
import { engagementsEvents } from "./events.ts";
import { engagementsSqlOptions } from "./options.ts";
import { engagementChangeSchema, engagementInputSchema } from "./schemas.ts";

/** The `engagements` block's manifest (ADR 0029). */
export const engagementsBlock: BlockOf<
  "engagements",
  typeof createEngagements,
  EngagementsEvents,
  { readonly files: "optional" }
> = defineBlock({
  name: "engagements",
  sql: ["engagements"],
  options: { engagements: engagementsSqlOptions },
  events: engagementsEvents,
  consumes: { files: "optional" },
  schemas: {
    engagement: {
      input: engagementInputSchema,
      change: engagementChangeSchema,
    },
  },
  create: createEngagements,
  category: "crm",
  recipes: ["activity-timeline"],
});
