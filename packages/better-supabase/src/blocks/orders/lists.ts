import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `orderPage`, `orderFacets` and `orderCount` accept (ADR 1077, 1224). The
 * manifest declares the same names, and the SQL list function `page_orders`
 * implements them. `from` and `to` take one instant and bound the placed time;
 * `q` matches the number, the email and the external id.
 */
export const orderListSurface: EntityListSurface = {
  sorts: ["placedAt", "number", "total"],
  facets: ["status", "currency", "channel"],
  filters: [
    "status",
    "customerId",
    "partyId",
    "channel",
    "source",
    "currency",
    "from",
    "to",
  ],
  search: ["number", "email", "externalId"],
};
