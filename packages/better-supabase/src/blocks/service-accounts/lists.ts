import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `principalPage`, `principalFacets` and `principalCount` accept for a
 * service principal (ADR 0749, 1077). The manifest declares the same names, and
 * the SQL list function implements them. `isDefault` and `disabled` take
 * `["true"]` or `["false"]`.
 */
export const principalListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["role", "isDefault", "disabled"],
  filters: ["role", "isDefault", "disabled"],
  search: ["name"],
};
