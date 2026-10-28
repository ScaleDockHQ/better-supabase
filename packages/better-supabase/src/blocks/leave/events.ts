import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `leave.requested`, `leave.approved`, `leave.rejected` and `leave.cancelled`:
 * the request.
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

/** `leave.adjusted`: a grant or manual adjustment to a member's balance. */
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
  readonly "leave.requested": LeaveRequestEventData;
  readonly "leave.approved": LeaveRequestEventData;
  readonly "leave.cancelled": LeaveRequestEventData;
  readonly "leave.rejected": LeaveRequestEventData;
  readonly "leave.adjusted": LeaveAdjustedEventData;
};

/** The `leave` block's event types, for its manifest and `onBlockEvent`. */
export const leaveEvents: Events<LeaveEvents> = defineEvents({
  "leave.requested": event<LeaveRequestEventData>(),
  "leave.approved": event<LeaveRequestEventData>(),
  "leave.cancelled": event<LeaveRequestEventData>(),
  "leave.rejected": event<LeaveRequestEventData>(),
  "leave.adjusted": event<LeaveAdjustedEventData>(),
});
