import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a contract (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_contracts`
 * implements them. `renewingBefore` is a date (a list of one) that keeps the
 * active contracts whose notice deadline falls on or before it.
 */
export const contractListSurface: EntityListSurface = {
  sorts: ["createdAt", "endsOn", "startsOn", "title"],
  facets: ["status", "ownerId"],
  filters: [
    "status",
    "ownerId",
    "counterpartyType",
    "counterpartyId",
    "renewingBefore",
  ],
  search: ["title", "description"],
};

/**
 * What `obligationPage`, `obligationFacets` and `obligationCount` accept for a
 * contract obligation. `dueBefore` is a date (a list of one).
 */
export const obligationListSurface: EntityListSurface = {
  sorts: ["dueOn", "createdAt"],
  facets: ["status", "contractId"],
  filters: ["contractId", "ownerId", "status", "dueBefore"],
  search: ["title", "description"],
};
