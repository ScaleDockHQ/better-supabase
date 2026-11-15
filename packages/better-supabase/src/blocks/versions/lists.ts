import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `versionPage`, `versionFacets` and `versionCount` accept for a version
 * (ADR 0749, 1077). The manifest declares the same names, and the SQL list
 * function `page_versions` implements them. `source` takes `manual`, `auto` or
 * `restore`.
 */
export const versionListSurface: EntityListSurface = {
  sorts: ["createdAt", "number"],
  facets: ["source", "subjectType"],
  filters: ["subjectType", "subjectId", "source"],
  search: ["label", "subjectId"],
};
