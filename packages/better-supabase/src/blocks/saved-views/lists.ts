import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a saved view (ADR 0749, 1077).
 * The manifest declares the same names, and the SQL list function
 * `page_saved_views` implements them. The list runs as the caller, so the read
 * policy decides which views are visible. `list` is the list the view belongs
 * to, such as `deals`.
 */
export const savedViewListSurface: EntityListSurface = {
  sorts: ["rank", "name", "updatedAt"],
  facets: ["scope", "kind"],
  filters: ["list", "scope", "kind"],
  search: ["name"],
};
