import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a legal entity (ADR 0749). The
 * manifest declares the same names, and the SQL list function
 * `list_legal_entities` implements them.
 */
export const legalEntityListSurface: EntityListSurface = {
  sorts: ["code", "name"],
  facets: ["isDefault"],
  filters: ["includeArchived", "isDefault"],
};
