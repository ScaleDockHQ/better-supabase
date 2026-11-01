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

/** `incident_postmortem.published`. */
export interface PostmortemPublishedEventData {
  readonly organizationId: string;
  readonly postmortemId: string;
  readonly incidentId: string;
}

/** `incident_profile.updated`: the regulatory reporting profile was saved. */
export interface IncidentProfileUpdatedEventData {
  readonly organizationId: string;
  readonly incidentId: string;
  readonly regimes: readonly string[];
}

/** `incident_filing.submitted`: a submission to an authority was recorded. */
export interface IncidentFilingSubmittedEventData {
  readonly organizationId: string;
  readonly incidentId: string;
  readonly id: string;
  readonly regime: string;
  readonly stage: string;
  readonly dueAt: string | null;
  readonly reference: string | null;
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
  readonly "incident_postmortem.published": PostmortemPublishedEventData;
  readonly "incident_profile.updated": IncidentProfileUpdatedEventData;
  readonly "incident_filing.submitted": IncidentFilingSubmittedEventData;
  readonly "status_component.changed": StatusComponentChangedEventData;
};

/** The `incidents` block's event types, for its manifest and `onBlockEvent`. */
export const incidentsEvents: Events<IncidentsEvents> = defineEvents({
  "incident.opened": event<IncidentOpenedEventData>(),
  "incident.updated": event<IncidentUpdatedEventData>(),
  "incident.resolved": event<IncidentResolvedEventData>(),
  "incident_postmortem.published": event<PostmortemPublishedEventData>(),
  "incident_profile.updated": event<IncidentProfileUpdatedEventData>(),
  "incident_filing.submitted": event<IncidentFilingSubmittedEventData>(),
  "status_component.changed": event<StatusComponentChangedEventData>(),
});
