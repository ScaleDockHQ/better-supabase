import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `reviewPage`, `reviewFacets` and `reviewCount` accept for a review (ADR
 * 0749, 1077). The manifest declares the same names, and the SQL list function
 * `page_reviews` implements them. A page reads one subject's published reviews,
 * so the client sets `subjectType` and `subjectId`; `q` searches the title and
 * the body.
 */
export const reviewListSurface: EntityListSurface = {
  sorts: ["publishedAt", "rating"],
  facets: ["rating", "verified"],
  filters: ["subjectType", "subjectId", "rating", "verified"],
  search: ["title", "body"],
};
