import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `documents.page`, `documents.facets` and `documents.count` accept (ADR
 * 0749, 1077). The SQL list function `page_knowledge_documents` implements
 * them. `collectionId`, `scopeId`, `subjectType` and `subjectId` take one value
 * each, as the array method's options did; `scope` and `status` take lists. `q`
 * searches the title.
 */
export const documentListSurface: EntityListSurface = {
  sorts: ["createdAt", "title"],
  facets: ["scope", "status"],
  filters: [
    "scope",
    "status",
    "collectionId",
    "scopeId",
    "subjectType",
    "subjectId",
  ],
  search: ["title"],
};

/**
 * What `collections.page`, `collections.facets` and `collections.count` accept.
 * The SQL list function `page_knowledge_collections` implements them. The
 * default order is highest priority first, then by name.
 */
export const collectionListSurface: EntityListSurface = {
  sorts: ["priority", "name", "createdAt"],
  facets: ["visibility"],
  filters: ["visibility"],
  search: ["name", "description"],
};
