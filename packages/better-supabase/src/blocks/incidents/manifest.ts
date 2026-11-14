import type { BlockOf } from "../define-block.ts";
import type { IncidentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { incidentsEvents } from "./events.ts";
import { createIncidents } from "./incidents.ts";
import { incidentListSurface } from "./lists.ts";
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
  entities: {
    incident: {
      ...incidentListSurface,
      mutability: "editable",
      emits: { create: false, update: true },
    },
    status_component: {
      mutability: "editable",
      emits: { update: true, delete: false },
    },
    incident_postmortem: { mutability: "editable", emits: { update: false } },
    status_page: { mutability: "editable", emits: { update: false } },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Incidents with a severity, a status timeline of updates, the components they affect and a postmortem, plus a public status page: component status, public incident updates and uptime history, readable anonymously through one function that returns only the fields marked public.",
});
