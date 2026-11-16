import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `files.page`, `files.facets` and `files.count` accept (ADR 0749, 1077).
 * The SQL list function `page_ai_files` implements them. `chatId` takes one
 * chat id, as `files.list` did; `status`, `source` and `mediaType` take lists.
 * `q` searches the filename. The default order is oldest first, as `list`.
 */
export const fileListSurface: EntityListSurface = {
  sorts: ["createdAt", "filename", "size"],
  facets: ["status", "source", "mediaType"],
  filters: ["chatId", "status", "source", "mediaType"],
  search: ["filename"],
};
