import type { Booking, BookingStatus } from "./bookings.ts";

import {
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

const STATUSES: readonly BookingStatus[] = ["hold", "confirmed", "cancelled"];

/** A booking row as `hold_booking`, `list_bookings` and the others return it. */
export function bookingOf(value: unknown): Booking {
  const row = recordOf(value, "booking");

  const text = (key: string) => {
    const found = optionalText(row[key]);

    return found === undefined ? {} : { [key]: found };
  };

  const instant = (key: string) => {
    const found = optionalInstant(row[key]);

    return found === undefined ? {} : { [key]: found };
  };

  return {
    id: textOf(row["id"]),
    resourceId: textOf(row["resourceId"]),
    serviceId: textOf(row["serviceId"]),
    seat: Number(row["seat"] ?? 1),
    startsAt: requiredInstant(row["startsAt"], "startsAt"),
    endsAt: requiredInstant(row["endsAt"], "endsAt"),
    status: oneOf(row["status"], STATUSES, "hold"),
    ...instant("holdExpiresAt"),
    ...text("customerName"),
    ...text("customerEmail"),
    ...text("customerUserId"),
    ...text("notes"),
    ...instant("createdAt"),
    ...instant("cancelledAt"),
    ...text("cancelReason"),
    ...text("seriesId"),
  };
}
