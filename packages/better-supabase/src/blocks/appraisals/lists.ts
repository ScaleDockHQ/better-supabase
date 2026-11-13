import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `appraisalPage`, `appraisalFacets` and `appraisalCount` accept for an
 * appraisal (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_appraisals` implements them. `mine` is `["true"]`.
 */
export const appraisalListSurface: EntityListSurface = {
  sorts: ["createdAt", "rating"],
  facets: ["status"],
  filters: ["cycleId", "status", "subjectUserId", "mine"],
};
