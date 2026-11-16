import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `chats.page`, `chats.facets` and `chats.count` accept (ADR 0749, 1077).
 * The SQL list function `page_ai_chats` implements them. `projectId` takes one
 * uuid, `pinned` and `archived` take `"true"` or `"false"`; without `archived`
 * the archived chats stay out. `q` searches titles and message text. The
 * default order is newest activity first.
 */
export const chatListSurface: EntityListSurface = {
  sorts: ["lastMessageAt", "createdAt", "title"],
  facets: ["pinned", "archived"],
  filters: ["projectId", "pinned", "archived"],
  search: ["title", "messages"],
};

/**
 * What `projects.page`, `projects.facets` and `projects.count` accept. The SQL
 * list function `page_ai_projects` implements them for the caller's own
 * projects. The default order is pinned first, then the most recently changed.
 */
export const projectListSurface: EntityListSurface = {
  sorts: ["updatedAt", "name"],
  facets: ["pinned", "archived"],
  filters: ["pinned", "archived"],
  search: ["name"],
};
