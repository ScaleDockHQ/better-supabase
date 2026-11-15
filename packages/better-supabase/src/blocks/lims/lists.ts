import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `samplePage`, `sampleFacets` and `sampleCount` accept for a sample (ADR
 * 0749). The manifest declares the same names, and the SQL list function
 * `list_samples` implements them.
 */
export const limsSampleListSurface: EntityListSurface = {
  sorts: ["number", "receivedOn"],
  facets: ["status", "kind"],
  filters: ["status", "kind"],
  search: ["number", "title", "lot"],
};

/**
 * The same for a test method (`page_lims_methods`). Archived methods are hidden
 * unless `includeArchived` is `["true"]`.
 */
export const limsMethodListSurface: EntityListSurface = {
  sorts: ["key", "name", "createdAt"],
  facets: ["unit"],
  filters: ["unit", "includeArchived"],
  search: ["key", "name"],
};
