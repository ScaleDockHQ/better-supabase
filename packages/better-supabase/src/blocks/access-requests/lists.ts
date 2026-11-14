import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for an access request (ADR 0749).
 * The manifest declares the same names, and the SQL list function
 * `list_access_requests` implements them.
 */
export const accessRequestListSurface: EntityListSurface = {
  sorts: ["createdAt"],
  facets: ["status", "role"],
  filters: ["status", "role", "mine"],
};
