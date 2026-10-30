import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `observation_definition.created` and `.updated`: a definition was saved. */
export interface ObservationDefinitionSavedEventData {
  /** Null for a system definition every organization reads. */
  readonly organizationId: string | null;
  readonly definitionId: string;
  readonly key: string;
  readonly title: string;
}

/** The fields every observation event carries. */
export interface ObservationEventData {
  readonly organizationId: string;
  readonly observationId: string;
  readonly definitionKey: string;
  readonly subjectType: string;
  readonly subjectId: string;
}

/** `observation.recorded`: a new measurement, not an amendment. */
export interface ObservationRecordedEventData extends ObservationEventData {
  /** ISO 8601. */
  readonly observedAt: string;
  /** `normal`, `low`, `high`, `critical_low` or `critical_high`, or null. */
  readonly flag: string | null;
  /** `manual`, `form`, `device` or `import`. */
  readonly source: string;
}

/** `observation.critical_recorded`: a value at or past a critical bound. */
export interface ObservationCriticalEventData extends ObservationEventData {
  /** ISO 8601. */
  readonly observedAt: string;
  /** `critical_low` or `critical_high`. */
  readonly flag: string;
}

/** `observation.amended`: a corrected value replaced an observation. */
export interface ObservationAmendedEventData extends ObservationEventData {
  /** The observation the amendment replaced. */
  readonly replacesId: string;
  readonly reason: string;
}

/** `observation.error_marked`: an observation was entered in error. */
export interface ObservationErrorMarkedEventData extends ObservationEventData {
  readonly reason: string;
}

/** The events of the `observations` block: type to data. */
export type ObservationsEvents = {
  readonly "observation_definition.created": ObservationDefinitionSavedEventData;
  readonly "observation_definition.updated": ObservationDefinitionSavedEventData;
  readonly "observation.recorded": ObservationRecordedEventData;
  readonly "observation.critical_recorded": ObservationCriticalEventData;
  readonly "observation.amended": ObservationAmendedEventData;
  readonly "observation.error_marked": ObservationErrorMarkedEventData;
};

/** The `observations` block's event types, for its manifest and `onBlockEvent`. */
export const observationsEvents: Events<ObservationsEvents> = defineEvents({
  "observation_definition.created":
    event<ObservationDefinitionSavedEventData>(),
  "observation_definition.updated":
    event<ObservationDefinitionSavedEventData>(),
  "observation.recorded": event<ObservationRecordedEventData>(),
  "observation.critical_recorded": event<ObservationCriticalEventData>(),
  "observation.amended": event<ObservationAmendedEventData>(),
  "observation.error_marked": event<ObservationErrorMarkedEventData>(),
});
