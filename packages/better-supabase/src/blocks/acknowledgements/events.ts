import type { SubjectEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `acknowledgement_assignment.created` and `.deleted`: a member, team or role
 * was asked, or no longer asked, to acknowledge a record.
 */
export interface AcknowledgementAssignmentEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly assignmentId: string;
  readonly principalType: "user" | "team" | "role";
  readonly principalId: string;
}

/** `acknowledgement.created`: a member acknowledged a version of a record. */
export interface AcknowledgementCreatedEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly versionId: string;
  readonly userId: string;
}

/**
 * `acknowledgement.reminded`: an assigned member passed the due date of a
 * record's current version without acknowledging it and was reminded, once per
 * version.
 */
export interface AcknowledgementRemindedEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly versionId: string;
  readonly userId: string;
  /** `YYYY-MM-DD`. */
  readonly dueOn: string;
}

/** The events of the `acknowledgements` block: type to data. */
export type AcknowledgementsEvents = {
  readonly "acknowledgement_assignment.created": AcknowledgementAssignmentEventData;
  readonly "acknowledgement_assignment.deleted": AcknowledgementAssignmentEventData;
  readonly "acknowledgement.created": AcknowledgementCreatedEventData;
  readonly "acknowledgement.reminded": AcknowledgementRemindedEventData;
};

/**
 * The `acknowledgements` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const acknowledgementsEvents: Events<AcknowledgementsEvents> =
  defineEvents({
    "acknowledgement_assignment.created":
      event<AcknowledgementAssignmentEventData>(),
    "acknowledgement_assignment.deleted":
      event<AcknowledgementAssignmentEventData>(),
    "acknowledgement.created": event<AcknowledgementCreatedEventData>(),
    "acknowledgement.reminded": event<AcknowledgementRemindedEventData>(),
  });
