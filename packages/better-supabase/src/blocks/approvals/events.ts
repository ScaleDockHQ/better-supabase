import type { CollaborationEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `approval_policy.created`, `approval_policy.updated` and
 * `approval_policy.deleted`.
 */
export interface ApprovalPolicyEventData {
  readonly organizationId: string;
  /** The tenant policy. */
  readonly id: string;
  readonly subjectType: string;
  readonly action: string;
}

/** The events of the `approvals` block: type to data. */
export type ApprovalsEvents = {
  readonly "approval.requested": CollaborationEventData;
  readonly "approval.approved": CollaborationEventData;
  readonly "approval.rejected": CollaborationEventData;
  readonly "approval.cancelled": CollaborationEventData;
  readonly "approval.expired": CollaborationEventData;
  readonly "approval.delegated": CollaborationEventData;
  readonly "approval.consumed": CollaborationEventData;
  readonly "approval.escalated": CollaborationEventData;
  readonly "approval_policy.created": ApprovalPolicyEventData;
  readonly "approval_policy.updated": ApprovalPolicyEventData;
  readonly "approval_policy.deleted": ApprovalPolicyEventData;
};

/** The `approvals` block's event types, for its manifest and `onBlockEvent`. */
export const approvalsEvents: Events<ApprovalsEvents> = defineEvents({
  "approval.requested": event<CollaborationEventData>(),
  "approval.approved": event<CollaborationEventData>(),
  "approval.rejected": event<CollaborationEventData>(),
  "approval.cancelled": event<CollaborationEventData>(),
  "approval.expired": event<CollaborationEventData>(),
  "approval.delegated": event<CollaborationEventData>(),
  "approval.consumed": event<CollaborationEventData>(),
  "approval.escalated": event<CollaborationEventData>(),
  "approval_policy.created": event<ApprovalPolicyEventData>(),
  "approval_policy.updated": event<ApprovalPolicyEventData>(),
  "approval_policy.deleted": event<ApprovalPolicyEventData>(),
});
