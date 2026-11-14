import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `guests.page`, `guests.facets` and `guests.count` accept for a guest
 * (ADR 0749). The manifest declares the same names, and the SQL list function
 * `page_guests` implements them.
 */
export const guestListSurface: EntityListSurface = {
  sorts: ["createdAt", "email"],
  facets: ["status"],
  filters: ["status"],
};
