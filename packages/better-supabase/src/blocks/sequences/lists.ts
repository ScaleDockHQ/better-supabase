import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `sequencePage`, `sequenceFacets` and `sequenceCount` accept for a
 * sequence (ADR 0749, 0779). The manifest declares the same names, and the SQL
 * list function `page_sequences` implements them.
 */
export const sequenceListSurface: EntityListSurface = {
  sorts: ["name", "updatedAt"],
  facets: ["status"],
  filters: ["status"],
};

/**
 * What `enrollmentPage`, `enrollmentFacets` and `enrollmentCount` accept for a
 * sequence recipient (ADR 0749, 1077). The manifest declares the same names,
 * and the SQL list function implements them. The page lists every recipient of
 * the organization; `sequenceId` narrows it to one sequence.
 */
export const enrollmentListSurface: EntityListSurface = {
  sorts: ["enrolledAt"],
  facets: ["status"],
  filters: ["sequenceId", "subjectType", "subjectId", "status"],
};
