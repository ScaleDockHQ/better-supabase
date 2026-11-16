import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `teamPage`, `teamFacets` and `teamCount` accept for a team (ADR 0749,
 * 1077). The manifest declares the same names, and the SQL list function
 * `list_teams` implements them. `q` searches the name, the slug and the
 * description.
 */
export const teamListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["status"],
  filters: ["status"],
  search: ["name", "slug", "description"],
};
