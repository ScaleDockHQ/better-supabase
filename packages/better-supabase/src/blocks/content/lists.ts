import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a content entry (ADR 0749). The
 * manifest declares the same names, and the SQL list function
 * `list_content_entries` implements them. `q` matches the title and slug.
 */
export const contentEntryListSurface: EntityListSurface = {
  sorts: ["updatedAt", "title", "createdAt", "publishedAt"],
  facets: ["type", "locale", "status"],
  filters: ["type", "locale", "status", "translationGroupId"],
  search: ["title", "slug"],
};
