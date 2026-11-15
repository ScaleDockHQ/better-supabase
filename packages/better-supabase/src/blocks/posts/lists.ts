import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What a post's `page`, `facets` and `count` accept (ADR 1077). The manifest
 * declares the same names, and the SQL list function `page_posts` implements
 * them. The default sort is `active` (pinned first, then the latest activity).
 * Archived and merged posts stay out unless the `archived` or `merged` flag
 * filter is set. `q` searches the title and the body.
 */
export const postListSurface: EntityListSurface = {
  sorts: ["active", "new", "top"],
  facets: ["status", "boardId"],
  filters: ["boardId", "status", "authorId", "merged", "archived"],
  search: ["title", "body"],
};

/**
 * What a board's `boardPage`, `boardFacets` and `boardCount` accept (ADR 1077).
 * The `archived` flag also reads archived boards; `q` searches the name and the
 * description.
 */
export const boardListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["kind"],
  filters: ["kind", "archived"],
  search: ["name", "description"],
};
