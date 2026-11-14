import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `sequencePage`, `sequenceFacets` and `sequenceCount` accept for a
 * sequence (ADR 0749, 0779). The manifest declares the same names, and the SQL
 * list function `page_sequences` implements them.
 */
export const sequenceListSurface: EntityListSurface = {
  sorts: ["name", "updatedAt"],
  facets: ["status"],
  filters: ["status"],
};
