import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `periodPage`, `periodFacets` and `periodCount` accept for a period (ADR
 * 0749). The manifest declares the same names, and the SQL list function
 * `list_periods` implements them.
 */
export const periodListSurface: EntityListSurface = {
  sorts: ["startsOn", "endsOn"],
  facets: ["kind", "status"],
  filters: ["kind", "status"],
};
