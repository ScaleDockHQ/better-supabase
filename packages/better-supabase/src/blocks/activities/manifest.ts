import type { BlockOf } from "../define-block.ts";
import type { ActivitiesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createActivities } from "./activities.ts";
import { activitiesEvents } from "./events.ts";
import { activitiesSqlOptions } from "./options.ts";
import { activityChangeSchema, activityInputSchema } from "./schemas.ts";

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
    activity: { input: activityInputSchema, change: activityChangeSchema },
  },
  create: createActivities,
  category: "crm",
  entities: {
    activity: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.",
  recipes: ["activity-timeline"],
});
