import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `conversationPage`, `conversationFacets` and `conversationCount` accept
 * (ADR 0749, 1077). The SQL list function `page_conversations` implements them.
 * The page holds the caller's conversations, latest message first; without
 * `kind` it leaves out the inbox's own. `q` searches the title.
 */
export const conversationListSurface: EntityListSurface = {
  sorts: ["lastMessageAt", "createdAt", "title"],
  facets: ["kind"],
  filters: ["kind"],
  search: ["title"],
};
