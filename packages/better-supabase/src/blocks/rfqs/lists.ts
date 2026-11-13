import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `rfqPage`, `rfqFacets` and `rfqCount` accept for a request for quotation
 * (ADR 0749). The manifest declares the same names, and the SQL list function
 * `list_rfqs` implements them.
 */
export const rfqListSurface: EntityListSurface = {
  sorts: ["number", "dueAt"],
  facets: ["status"],
  filters: ["status"],
};
