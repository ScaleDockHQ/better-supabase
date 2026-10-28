import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** An assignment was created or changed. */
export interface AcknowledgementAssignmentCreatedEventData {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly assignmentId: string;
  readonly principalType: "user" | "team" | "role";
  readonly principalId: string;
  readonly dueOn: string | null;
}

/** An assignment was removed. */
export interface AcknowledgementAssignmentDeletedEventData {
  readonly organizationId: string;
  readonly assignmentId: string;
}

/** A member acknowledged a version. */
export interface AcknowledgementCreatedEventData {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly versionId: string;
  readonly userId: string;
  readonly method: "click" | "signature";
}

/** An acknowledgement is due. */
export interface AcknowledgementExpiredEventData {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly versionId: string;
  readonly userId: string;
  readonly dueOn: string;
}

/** The events of the `acknowledgements` block. */
export type AcknowledgementsEvents = {
  readonly "acknowledgement_assignment.created": AcknowledgementAssignmentCreatedEventData;
  readonly "acknowledgement_assignment.deleted": AcknowledgementAssignmentDeletedEventData;
  readonly "acknowledgement.created": AcknowledgementCreatedEventData;
  readonly "acknowledgement.expired": AcknowledgementExpiredEventData;
};

export const acknowledgementsEvents: Events<AcknowledgementsEvents> =
  defineEvents({
    "acknowledgement_assignment.created":
      event<AcknowledgementAssignmentCreatedEventData>(),
    "acknowledgement_assignment.deleted":
      event<AcknowledgementAssignmentDeletedEventData>(),
    "acknowledgement.created": event<AcknowledgementCreatedEventData>(),
    "acknowledgement.expired": event<AcknowledgementExpiredEventData>(),
  });
