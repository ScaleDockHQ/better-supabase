import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the trash `page`, `facets` and `count` accept (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_trash`
 * implements them.
 */
export const trashListSurface: EntityListSurface = {
  sorts: ["trashedAt", "subjectType", "purgeAfter"],
  facets: ["subjectType"],
  filters: ["subjectType"],
  search: ["title"],
};
