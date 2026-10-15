import type {
  CollaborationEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `approvals` block: type to data. */
export type ApprovalsEvents = {
  readonly "approval.requested": CollaborationEventData;
  readonly "approval.approved": CollaborationEventData;
  readonly "approval.rejected": CollaborationEventData;
  readonly "approval.cancelled": CollaborationEventData;
  readonly "approval.expired": CollaborationEventData;
  readonly "approval.delegated": CollaborationEventData;
};

/** The `approvals` block's event types, for its manifest and `onBlockEvent`. */
export const approvalsEvents: Events<ApprovalsEvents> = defineEvents({
  "approval.requested": event<CollaborationEventData>(),
  "approval.approved": event<CollaborationEventData>(),
  "approval.rejected": event<CollaborationEventData>(),
  "approval.cancelled": event<CollaborationEventData>(),
  "approval.expired": event<CollaborationEventData>(),
  "approval.delegated": event<CollaborationEventData>(),
});
