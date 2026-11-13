import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `passPage`, `passFacets` and `passCount` accept for a pass (ADR 0749,
 * 0779). The manifest declares the same names, and the SQL list function
 * `page_passes` implements them.
 */
export const passListSurface: EntityListSurface = {
  sorts: ["createdAt", "validFrom", "validUntil"],
  facets: ["status"],
  filters: ["status", "holderUserId"],
};
