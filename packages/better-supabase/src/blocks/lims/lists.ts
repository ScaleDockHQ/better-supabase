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
};
