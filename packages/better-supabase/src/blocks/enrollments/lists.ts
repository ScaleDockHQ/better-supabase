import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `enrollmentPage`, `enrollmentFacets` and `enrollmentCount` accept for an
 * enrollment (ADR 0749, 0779). The manifest declares the same names, and the
 * SQL list function `page_enrollments` implements them.
 */
export const enrollmentListSurface: EntityListSurface = {
  sorts: ["updatedAt", "enrolledAt"],
  facets: ["status", "program"],
  filters: ["status", "program", "subjectType", "subjectId"],
};
