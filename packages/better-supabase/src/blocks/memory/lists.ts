import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `page`, `facets` and `count` accept for a memory (ADR 1077). The SQL
 * list function `page_memories` implements them for one namespace (`ns`), as
 * `memory_list` does. `kind` defaults to the archival facts and `category`
 * takes a list. `q` searches the content. The default order is newest first.
 * `useCount`, `lastUsedAt` and `category` exist when the memories table has
 * those columns.
 */
export const memoryListSurface: EntityListSurface = {
  sorts: ["createdAt", "updatedAt", "path", "useCount", "lastUsedAt"],
  facets: ["kind", "category"],
  filters: ["kind", "category"],
  search: ["content"],
};
