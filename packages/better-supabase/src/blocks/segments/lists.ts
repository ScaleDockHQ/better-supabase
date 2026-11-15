import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a segment (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_segments`
 * implements them. Listing needs `segments.read`.
 */
export const segmentListSurface: EntityListSurface = {
  sorts: ["name", "createdAt", "memberCount"],
  facets: ["subjectType"],
  filters: ["subjectType"],
  search: ["name", "description"],
};
