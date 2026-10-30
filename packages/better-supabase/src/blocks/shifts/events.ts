import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

interface ShiftEventBase {
  readonly organizationId: string;
  readonly shiftId: string;
  readonly teamId: string | null;
  /** ISO timestamps. */
  readonly startsAt: string;
  readonly endsAt: string;
}

/** `shift.created`: a draft shift was planned, by hand or from a template. */
export interface ShiftCreatedEventData extends ShiftEventBase {
  readonly status: string;
}

/** `shift.published`: members can see the shift. */
export type ShiftPublishedEventData = ShiftEventBase;

/** `shift.cancelled`: the shift won't happen; its assignments are released. */
export interface ShiftCanceledEventData extends ShiftEventBase {
  readonly reason: string | null;
}

/** `shift_assignment.created`: a member was put on a shift. */
export interface ShiftAssignmentCreatedEventData {
  readonly organizationId: string;
  readonly shiftId: string;
  readonly assignmentId: string;
  readonly userId: string;
  readonly startsAt: string;
  readonly endsAt: string;
}

/**
 * `shift_assignment.released`: a member is off a shift, or their request for it
 * was turned down. `reason` is the planner's text, `shift_canceled`, `swapped`
 * or `request_rejected`.
 */
export interface ShiftAssignmentReleasedEventData extends ShiftAssignmentCreatedEventData {
  readonly reason: string | null;
}

/** `shift_swap.requested`: a member offered their shift to another. */
export interface ShiftSwapRequestedEventData {
  readonly organizationId: string;
  readonly swapId: string;
  readonly assignmentId: string;
  readonly shiftId: string;
  readonly fromUserId: string;
  readonly toUserId: string;
}

/** `shift_swap.decided`: a swap was approved, rejected or withdrawn. */
export interface ShiftSwapDecidedEventData extends ShiftSwapRequestedEventData {
  /** `approved`, `rejected` or `canceled`. */
  readonly status: string;
}

/** The events of the `shifts` block: type to data. */
export type ShiftsEvents = {
  readonly "shift.created": ShiftCreatedEventData;
  readonly "shift.published": ShiftPublishedEventData;
  readonly "shift.cancelled": ShiftCanceledEventData;
  readonly "shift_assignment.created": ShiftAssignmentCreatedEventData;
  readonly "shift_assignment.released": ShiftAssignmentReleasedEventData;
  readonly "shift_swap.requested": ShiftSwapRequestedEventData;
  readonly "shift_swap.decided": ShiftSwapDecidedEventData;
};

/** The `shifts` block's event types, for its manifest and `onBlockEvent`. */
export const shiftsEvents: Events<ShiftsEvents> = defineEvents({
  "shift.created": event<ShiftCreatedEventData>(),
  "shift.published": event<ShiftPublishedEventData>(),
  "shift.cancelled": event<ShiftCanceledEventData>(),
  "shift_assignment.created": event<ShiftAssignmentCreatedEventData>(),
  "shift_assignment.released": event<ShiftAssignmentReleasedEventData>(),
  "shift_swap.requested": event<ShiftSwapRequestedEventData>(),
  "shift_swap.decided": event<ShiftSwapDecidedEventData>(),
});
