import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `incident.opened`. */
export interface IncidentOpenedEventData {
  readonly organizationId: string;
  readonly incidentId: string;
  readonly title: string;
  readonly severity: string;
  readonly status: string;
  /** Whether the incident shows on the public status page. */
  readonly public: boolean;
}

/** `incident.updated`: a timeline update, with the status it set. */
export interface IncidentUpdatedEventData {
  readonly organizationId: string;
  readonly incidentId: string;
  readonly updateId: string;
  readonly status: string;
  readonly public: boolean;
}

/** `incident.resolved`. */
export interface IncidentResolvedEventData {
  readonly organizationId: string;
  readonly incidentId: string;
  readonly severity: string;
}

/** `postmortem.published`. */
export interface PostmortemPublishedEventData {
  readonly organizationId: string;
  readonly postmortemId: string;
  readonly incidentId: string;
}

/** `status_component.changed`: a component's current status changed. */
export interface StatusComponentChangedEventData {
  readonly organizationId: string;
  readonly statusComponentId: string;
  readonly status: string;
  readonly previousStatus: string;
}

/** The events of the `incidents` block: type to data. */
export type IncidentsEvents = {
  readonly "incident.opened": IncidentOpenedEventData;
  readonly "incident.updated": IncidentUpdatedEventData;
  readonly "incident.resolved": IncidentResolvedEventData;
  readonly "postmortem.published": PostmortemPublishedEventData;
  readonly "status_component.changed": StatusComponentChangedEventData;
};

/** The `incidents` block's event types, for its manifest and `onBlockEvent`. */
export const incidentsEvents: Events<IncidentsEvents> = defineEvents({
  "incident.opened": event<IncidentOpenedEventData>(),
  "incident.updated": event<IncidentUpdatedEventData>(),
  "incident.resolved": event<IncidentResolvedEventData>(),
  "postmortem.published": event<PostmortemPublishedEventData>(),
  "status_component.changed": event<StatusComponentChangedEventData>(),
});
