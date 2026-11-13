import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `risks.page`, `risks.facets` and `risks.count` accept for a risk (ADR
 * 0749). The manifest declares the same names, and the SQL list function
 * `list_risks` implements them.
 */
export const riskListSurface: EntityListSurface = {
  sorts: ["residualScore", "number", "nextReviewOn"],
  facets: ["status", "category", "band"],
  filters: ["status", "category", "band", "ownerId", "reviewDue"],
  search: true,
};
