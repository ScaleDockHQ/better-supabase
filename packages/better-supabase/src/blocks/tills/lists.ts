import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `sessionPage`, `sessionFacets` and `sessionCount` accept for a till
 * session (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_till_sessions` implements them.
 */
export const tillSessionListSurface: EntityListSurface = {
  sorts: ["openedAt", "closedAt"],
  facets: ["status", "tillId"],
  filters: ["tillId", "status"],
};
