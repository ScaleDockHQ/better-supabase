import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `leave_request.requested`, `leave_request.approved`, `leave_request.rejected`
 * and `leave_request.cancelled`: the request.
 */
export interface LeaveRequestEventData {
  readonly organizationId: string;
  /** The leave request. */
  readonly id: string;
  readonly userId: string | null;
  readonly employeeId?: string;
  readonly typeId: string;
  /** `YYYY-MM-DD`. */
  readonly startsOn: string;
  /** `YYYY-MM-DD`, inclusive. */
  readonly endsOn: string;
  /** Working days, or hours for an hours type, as text. */
  readonly amount: string;
  readonly approvalId: string | null;
}

/** `leave_balance.adjusted`: a grant or manual adjustment to a member's balance. */
export interface LeaveAdjustedEventData {
  readonly organizationId: string;
  /** The ledger entry. */
  readonly id: string;
  readonly userId: string | null;
  readonly employeeId?: string;
  readonly typeId: string;
  readonly kind: "grant" | "adjustment";
  /** Signed, as text. */
  readonly amount: string;
  /** The year the entry counts toward. */
  readonly period: number;
}

/** The events of the `leave` block: type to data. */
export type LeaveEvents = {
  readonly "leave_request.requested": LeaveRequestEventData;
  readonly "leave_request.approved": LeaveRequestEventData;
  readonly "leave_request.cancelled": LeaveRequestEventData;
  readonly "leave_request.rejected": LeaveRequestEventData;
  /** A pending or approved request's dates, parts or hours changed. */
  readonly "leave_request.updated": LeaveRequestEventData;
  /** Approved leave was split around a gap; the event names the new part. */
  readonly "leave_request.split": LeaveRequestEventData;
  readonly "leave_balance.adjusted": LeaveAdjustedEventData;
};

/** The `leave` block's event types, for its manifest and `onBlockEvent`. */
export const leaveEvents: Events<LeaveEvents> = defineEvents({
  "leave_request.requested": event<LeaveRequestEventData>(),
  "leave_request.approved": event<LeaveRequestEventData>(),
  "leave_request.cancelled": event<LeaveRequestEventData>(),
  "leave_request.rejected": event<LeaveRequestEventData>(),
  "leave_request.updated": event<LeaveRequestEventData>(),
  "leave_request.split": event<LeaveRequestEventData>(),
  "leave_balance.adjusted": event<LeaveAdjustedEventData>(),
});
