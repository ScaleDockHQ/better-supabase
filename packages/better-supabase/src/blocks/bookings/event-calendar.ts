import type { EventCalendarEvent } from "../calendar/event-calendar.ts";
import type { Booking, BookingSlot } from "./bookings.ts";

export interface BookingEventOptions {
  /** The title of a booking. Default the customer's name, else `Booking`. */
  readonly titleOf?: (booking: Booking) => string;
  /** The color of a booking. Default none; holds are always read-only. */
  readonly colorOf?: (booking: Booking) => string | undefined;
}

/**
 * Bookings as event calendar events for a resource view (ReUI's Event
 * Calendar with `resources`, or a schedule): each booking sits on its
 * resource's row. Cancelled bookings are left out.
 */
export function toEventCalendarBookings(
  bookings: readonly Booking[],
  options: BookingEventOptions = {},
): EventCalendarEvent<Booking>[] {
  return bookings.flatMap((booking) => {
    if (booking.status === "cancelled") {
      return [];
    }

    const color = options.colorOf?.(booking);

    return [
      {
        id: booking.id,
        title: options.titleOf?.(booking) ?? booking.customerName ?? "Booking",
        start: new Date(booking.startsAt.epochMilliseconds),
        end: new Date(booking.endsAt.epochMilliseconds),
        resourceId: booking.resourceId,
        ...(color === undefined ? {} : { color }),
        ...(booking.status === "hold" ? { readOnly: true } : {}),
        data: booking,
      },
    ];
  });
}

/** Slots grouped by their local date (`YYYY-MM-DD`), in start order, for a day-by-day picker. */
export function slotsByDay(
  slots: readonly BookingSlot[],
): Map<string, BookingSlot[]> {
  const days = new Map<string, BookingSlot[]>();

  const sorted = slots.toSorted(
    (a, b) => a.startsAt.epochMilliseconds - b.startsAt.epochMilliseconds,
  );

  for (const slot of sorted) {
    const day = slot.localStart.toPlainDate().toString();
    const list = days.get(day);

    if (list === undefined) {
      days.set(day, [slot]);
    } else {
      list.push(slot);
    }
  }

  return days;
}
