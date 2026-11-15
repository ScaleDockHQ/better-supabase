import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page` and `count` accept for a prompt name (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_prompts`
 * implements them. The labels of a name are a map, not one column, so the
 * entity declares no facet; `label` filters to the names that have it.
 */
export const promptListSurface: EntityListSurface = {
  sorts: ["name", "updatedAt", "versionCount"],
  filters: ["name", "label"],
  search: ["name"],
};
