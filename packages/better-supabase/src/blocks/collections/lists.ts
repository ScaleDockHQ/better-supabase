import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `collectionPage`, `collectionFacets` and `collectionCount` accept for a
 * collection (ADR 0749, 1077). The manifest declares the same names, and the
 * SQL list function `page_collections` implements them. `includeArchived` is a
 * flag filter: `["true"]` also reads archived collections. `q` searches the
 * name and the description.
 */
export const collectionListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["subjectType", "scope"],
  filters: ["subjectType", "scope", "includeArchived"],
  search: ["name", "description"],
};
