import type { BlockOf } from "../define-block.ts";
import type { BookingsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBookings } from "./bookings.ts";
import { bookingsEvents } from "./events.ts";
import { bookingsSqlOptions } from "./options.ts";
import { bookingsBinding } from "./record-binding.ts";

/** The `bookings` block's manifest (ADR 0029). */
export const bookingsBlock: BlockOf<
  "bookings",
  typeof createBookings,
  BookingsEvents,
  Record<never, never>,
  never,
  typeof bookingsBinding
> = defineBlock({
  name: "bookings",
  sql: ["bookings"],
  options: { bookings: bookingsSqlOptions },
  events: bookingsEvents,
  create: createBookings,
  client: "bookings",
  record: bookingsBinding,
  category: "scheduling",
  entities: { booking: { mutability: "state-machine" } },
  concerns: ["lifecycle", "search"],
  description:
    "Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; recurring series book every occurrence; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.",
  recipes: ["booking-page", "availability-editor"],
});
