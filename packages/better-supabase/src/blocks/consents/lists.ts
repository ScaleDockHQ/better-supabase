import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `purposePage`, `purposeFacets` and `purposeCount` accept for a consent
 * purpose (ADR 0749, 1077). The manifest declares the same names, and the SQL
 * list function implements them. Archived purposes are hidden unless `archived`
 * is `["true"]` (only the archived ones). The consents, signals and receipts of
 * a record stay record-scoped reads, see the block page.
 */
export const purposeListSurface: EntityListSurface = {
  sorts: ["key", "createdAt"],
  facets: ["legalBasis"],
  filters: ["key", "legalBasis", "archived"],
  search: ["key", "title"],
};
