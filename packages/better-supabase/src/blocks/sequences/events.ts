import type { Events } from "../../core/event-map.ts";
import type { EnrollmentEventData } from "../enrollments/events.ts";

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
 * A recipient's run now emits the `enrollment.*` events, with the program
 * `sequence:<sequence id>`.
 *
 * @deprecated Use `EnrollmentEventData` from `better-supabase/blocks/enrollments`.
 * Removed in 0.48.
 */
export type SequenceEnrollmentEventData = EnrollmentEventData;

/** The events of the `sequences` block: type to data. */
export type SequencesEvents = {
  readonly "sequence.created": SequenceEventData;
  readonly "sequence.updated": SequenceEventData;
  readonly "sequence.deleted": SequenceEventData;
};

/** The `sequences` block's event types, for its manifest and `onBlockEvent`. */
export const sequencesEvents: Events<SequencesEvents> = defineEvents({
  "sequence.created": event<SequenceEventData>(),
  "sequence.updated": event<SequenceEventData>(),
  "sequence.deleted": event<SequenceEventData>(),
});
