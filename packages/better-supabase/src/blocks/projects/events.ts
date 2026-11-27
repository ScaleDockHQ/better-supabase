import type { Events } from "../../events/index.ts";

import { defineEvents, event } from "../../events/index.ts";

/** A posted project update. */
export interface ProjectUpdateEventData {
  readonly organizationId: string;
  readonly projectId: string;
  readonly updateId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly health: "on_track" | "at_risk" | "off_track";
  readonly actorId?: string;
  readonly actorKind?: string;
  readonly actorName?: string;
}

/** An initiative. */
export interface InitiativeEventData {
  readonly organizationId: string;
  readonly initiativeId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly name: string;
  readonly actorId?: string;
  readonly actorKind?: string;
  readonly actorName?: string;
}

/** The events of the projects glue module. */
export type ProjectsEvents = {
  readonly "project_update.created": ProjectUpdateEventData;
  readonly "initiative.created": InitiativeEventData;
  readonly "initiative.updated": InitiativeEventData;
  readonly "initiative.archived": InitiativeEventData;
  readonly "initiative.deleted": InitiativeEventData;
};

/** The projects module's event types. */
export const projectsEvents: Events<ProjectsEvents> = defineEvents({
  "project_update.created": event<ProjectUpdateEventData>(),
  "initiative.created": event<InitiativeEventData>(),
  "initiative.updated": event<InitiativeEventData>(),
  "initiative.archived": event<InitiativeEventData>(),
  "initiative.deleted": event<InitiativeEventData>(),
});
