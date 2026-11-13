import type { RecordBinding } from "../record-bindings.ts";
import type { Booking, Bookings } from "./bookings.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/**
 * A customer's bookings, newest first: the subject's `id` is the customer's
 * user id. It reads through `bookings.forCustomer`, which takes the
 * organization from the block's `tenant` option and shows what the caller's
 * policies allow. Booking writes take instants and a service, so the binding
 * has none.
 */
export const bookingsBinding: RecordBinding<Bookings, readonly Booking[]> =
  defineRecordBinding({
    permissions: { read: "read" },
    module: "bookings",
    load: (client: Bookings, subject) => client.forCustomer({ subject }),
    events: ["booking.*"],
  });
