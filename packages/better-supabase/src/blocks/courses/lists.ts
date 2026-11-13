import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a course (ADR 0749). The
 * manifest declares the same names, and the SQL list function `list_courses`
 * implements them.
 */
export const courseListSurface: EntityListSurface = {
  sorts: ["title"],
  facets: ["status"],
  filters: ["status"],
};
