import type { SchedulingEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `bookings` block: type to data. */
export type BookingsEvents = {
  readonly "booking.reserved": SchedulingEventData;
  readonly "booking.confirmed": SchedulingEventData;
  readonly "booking.cancelled": SchedulingEventData;
  readonly "booking.expired": SchedulingEventData;
  readonly "booking.rescheduled": SchedulingEventData;
};

/** The `bookings` block's event types, for its manifest and `onBlockEvent`. */
export const bookingsEvents: Events<BookingsEvents> = defineEvents({
  "booking.reserved": event<SchedulingEventData>(),
  "booking.confirmed": event<SchedulingEventData>(),
  "booking.cancelled": event<SchedulingEventData>(),
  "booking.expired": event<SchedulingEventData>(),
  "booking.rescheduled": event<SchedulingEventData>(),
});
