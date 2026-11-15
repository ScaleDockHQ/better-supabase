import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the booking `pageBookings`, `bookingFacets` and `countBookings` accept
 * (ADR 0749, 1077). The manifest declares the same names, and the SQL list
 * function `page_bookings` implements them. `from` and `to` take one instant
 * and `archived` takes `true`.
 */
export const bookingListSurface: EntityListSurface = {
  sorts: ["startsAt", "createdAt", "customerName"],
  facets: ["status", "resourceId"],
  filters: [
    "status",
    "resourceId",
    "serviceId",
    "customerId",
    "from",
    "to",
    "archived",
  ],
  search: ["customerName", "customerEmail"],
};
