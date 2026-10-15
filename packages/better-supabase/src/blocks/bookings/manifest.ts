import type { BlockOf } from "../define-block.ts";
import type { BookingsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBookings } from "./bookings.ts";
import { bookingsEvents } from "./events.ts";

/** The `bookings` block's manifest (ADR 0029). */
export const bookingsBlock: BlockOf<
  "bookings",
  typeof createBookings,
  BookingsEvents
> = defineBlock({
  name: "bookings",
  sql: ["bookings"],
  events: bookingsEvents,
  create: createBookings,
  client: "bookings",
  category: "scheduling",
});
