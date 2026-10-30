import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `sequence.created`, `sequence.updated` and `sequence.deleted`. */
export interface SequenceEventData {
  readonly organizationId: string;
  /** The sequence. */
  readonly id: string;
  readonly key: string;
  readonly status: string;
}

/**
 * The `sequence_enrollment.*` events: a recipient enrolled, finished a step,
 * paused, resumed, exited or completed the sequence.
 */
export interface SequenceEnrollmentEventData {
  readonly organizationId: string;
  /** The enrollment. */
  readonly id: string;
  readonly sequenceId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly status: string;
  /** The step, on `step_completed`. */
  readonly step: string | null;
  /** Why the run ended, on `exited`: replied, manual, failed or archived. */
  readonly reason: string | null;
}

/** The events of the `sequences` block: type to data. */
export type SequencesEvents = {
  readonly "sequence.created": SequenceEventData;
  readonly "sequence.updated": SequenceEventData;
  readonly "sequence.deleted": SequenceEventData;
  readonly "sequence_enrollment.created": SequenceEnrollmentEventData;
  readonly "sequence_enrollment.step_completed": SequenceEnrollmentEventData;
  readonly "sequence_enrollment.paused": SequenceEnrollmentEventData;
  readonly "sequence_enrollment.resumed": SequenceEnrollmentEventData;
  readonly "sequence_enrollment.exited": SequenceEnrollmentEventData;
  readonly "sequence_enrollment.completed": SequenceEnrollmentEventData;
};

/** The `sequences` block's event types, for its manifest and `onBlockEvent`. */
export const sequencesEvents: Events<SequencesEvents> = defineEvents({
  "sequence.created": event<SequenceEventData>(),
  "sequence.updated": event<SequenceEventData>(),
  "sequence.deleted": event<SequenceEventData>(),
  "sequence_enrollment.created": event<SequenceEnrollmentEventData>(),
  "sequence_enrollment.step_completed": event<SequenceEnrollmentEventData>(),
  "sequence_enrollment.paused": event<SequenceEnrollmentEventData>(),
  "sequence_enrollment.resumed": event<SequenceEnrollmentEventData>(),
  "sequence_enrollment.exited": event<SequenceEnrollmentEventData>(),
  "sequence_enrollment.completed": event<SequenceEnrollmentEventData>(),
});
