import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a tag (ADR 0749, 1077). The
 * manifest declares the same names, and the SQL list function `page_tags`
 * implements them. `rank` is the tenant's manual order.
 */
export const tagListSurface: EntityListSurface = {
  sorts: ["rank", "name", "kind", "createdAt"],
  facets: ["kind"],
  filters: ["kind"],
  search: ["name", "slug", "description"],
};
