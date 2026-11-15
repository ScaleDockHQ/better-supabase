import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `modelPage`, `modelFacets` and `modelCount` accept for a score model
 * (ADR 0749, 1077). The manifest declares the same names, and the SQL list
 * function `page_score_models` implements them. Archived models are hidden
 * unless `archived` is `["true"]` (only the archived ones). Listing needs
 * `scores.read`.
 */
export const scoreModelListSurface: EntityListSurface = {
  sorts: ["name", "key", "version"],
  facets: ["subjectType", "enabled"],
  filters: ["subjectType", "enabled", "archived"],
  search: ["name", "key"],
};
