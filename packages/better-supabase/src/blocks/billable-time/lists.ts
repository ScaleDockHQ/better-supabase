import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `ratePage`, `rateFacets` and `rateCount` accept for a time rate (ADR
 * 0749, 1077). The manifest declares the same names, and the SQL list function
 * `page_time_rates` implements them. Listing needs `billable_time.read`.
 */
export const rateListSurface: EntityListSurface = {
  sorts: ["effectiveFrom", "rate"],
  facets: ["currency", "subjectType"],
  filters: ["userId", "subjectType", "subjectId", "currency"],
  search: ["subjectType", "subjectId"],
};
