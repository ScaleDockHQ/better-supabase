import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `subjectRequestPage`, `subjectRequestFacets` and `subjectRequestCount`
 * accept for a data subject request (ADR 0749, 1077). The manifest declares the
 * same names, and the SQL list function implements them. `open` and `overdue`
 * are flag filters: `["true"]` leaves out the closed requests, or keeps the
 * open ones past their due date. Retention policies, legal holds and exports
 * stay array reads, see the block page.
 */
export const subjectRequestListSurface: EntityListSurface = {
  sorts: ["dueAt", "receivedAt"],
  facets: ["status", "kind"],
  filters: ["status", "kind", "open", "overdue"],
  search: ["subjectId", "requester"],
};
