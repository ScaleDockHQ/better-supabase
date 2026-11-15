import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for an announcement (ADR 0749,
 * 1077). The manifest declares the same names, and the SQL list function
 * `page_announcements` implements them. Staff read the list with
 * `announcements.manage`; `archived: ["true"]` adds the archived rows.
 */
export const announcementListSurface: EntityListSurface = {
  sorts: ["startsAt", "title", "createdAt"],
  facets: ["severity", "audience"],
  filters: ["severity", "audience", "archived"],
  search: ["title", "body"],
};
