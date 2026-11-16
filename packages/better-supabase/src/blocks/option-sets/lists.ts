import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `setPage`, `setFacets` and `setCount` accept for an option set (ADR
 * 0749, 1077). The manifest declares the same names, and the SQL list function
 * `page_option_sets` implements them. Archived sets are hidden unless
 * `archived` is `["true"]` (only the archived ones). Listing needs the read
 * permission.
 */
export const optionSetListSurface: EntityListSurface = {
  sorts: ["createdAt", "name"],
  facets: ["subjectType", "field"],
  filters: ["subjectType", "field", "scopeId", "archived"],
  search: ["name", "key", "field"],
};
