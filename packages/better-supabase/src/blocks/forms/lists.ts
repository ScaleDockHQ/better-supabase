import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a form (ADR 0749). The manifest
 * declares the same names, and the SQL list function `list_forms` implements
 * them.
 */
export const formListSurface: EntityListSurface = {
  sorts: ["createdAt", "title", "key"],
  facets: ["status"],
  filters: ["status"],
};
