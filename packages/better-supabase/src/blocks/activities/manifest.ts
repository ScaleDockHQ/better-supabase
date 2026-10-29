import type { BlockOf } from "../define-block.ts";
import type { ActivitiesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createActivities } from "./activities.ts";
import { activitiesEvents } from "./events.ts";
import { activitiesSqlOptions } from "./options.ts";
import { engagementChangeSchema, engagementInputSchema } from "./schemas.ts";

/** The `activities` block's manifest (ADR 0029). */
export const activitiesBlock: BlockOf<
  "activities",
  typeof createActivities,
  ActivitiesEvents,
  { readonly files: "optional" }
> = defineBlock({
  name: "activities",
  sql: ["activities"],
  options: { activities: activitiesSqlOptions },
  events: activitiesEvents,
  consumes: { files: "optional" },
  schemas: {
    engagement: {
      input: engagementInputSchema,
      change: engagementChangeSchema,
    },
  },
  create: createActivities,
  category: "crm",
  recipes: ["activity-timeline"],
});
