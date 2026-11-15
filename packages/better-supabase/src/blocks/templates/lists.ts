import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `templatePage`, `templateFacets` and `templateCount` accept for a
 * template (ADR 0749, 1077). The manifest declares the same names, and the SQL
 * list function `page_templates` implements them. `scope` takes `tenant`,
 * `brand` or `system`; `isDefault` takes `true` or `false` on a table with a
 * default flag.
 */
export const templateListSurface: EntityListSurface = {
  sorts: ["name", "createdAt", "updatedAt"],
  facets: ["type", "language", "scope"],
  filters: ["type", "language", "scope", "isDefault"],
  search: ["name", "key"],
};
