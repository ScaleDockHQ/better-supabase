import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What the field definition `page`, `facets` and `count` accept (ADR 0749,
 * 1077). The manifest declares the same names, and the SQL list function
 * `page_field_definitions` implements them. `sensitive` and `archived` take
 * `true`.
 */
export const fieldDefinitionListSurface: EntityListSurface = {
  sorts: ["key", "label", "type", "rank"],
  facets: ["entity", "type"],
  filters: ["entity", "type", "sensitive", "archived"],
  search: ["key", "label"],
};
