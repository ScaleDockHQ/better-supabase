import type { BlockOf } from "../define-block.ts";
import type { IncidentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { incidentsEvents } from "./events.ts";
import { createIncidents } from "./incidents.ts";
import { incidentsSqlOptions } from "./options.ts";
import {
  incidentChangesSchema,
  incidentInputSchema,
  postmortemInputSchema,
  statusComponentInputSchema,
  statusPageInputSchema,
} from "./schemas.ts";

/** The `incidents` block's manifest (ADR 0029). */
export const incidentsBlock: BlockOf<
  "incidents",
  typeof createIncidents,
  IncidentsEvents
> = defineBlock({
  name: "incidents",
  sql: ["incidents"],
  options: { incidents: incidentsSqlOptions },
  events: incidentsEvents,
  schemas: {
    incident: { input: incidentInputSchema, change: incidentChangesSchema },
    status_component: { input: statusComponentInputSchema },
    incident_postmortem: { input: postmortemInputSchema },
    status_page: { input: statusPageInputSchema },
  },
  create: createIncidents,
  recipes: ["status-page"],
  category: "work",
});
