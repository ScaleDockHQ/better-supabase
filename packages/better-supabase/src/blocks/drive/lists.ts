import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `documentPage`, `documentFacets` and `documentCount` accept for a
 * controlled document, a `drive_node` with a document status (ADR 0749, 1077).
 * The manifest declares the same names, and the SQL list function
 * `page_drive_documents` implements them. `review` takes `due` or `ok`, and
 * `reviewDue` takes `"true"` for effective documents whose review date has
 * come.
 */
export const driveDocumentListSurface: EntityListSurface = {
  sorts: ["number", "name", "nextReviewOn"],
  facets: ["type", "status", "review"],
  filters: ["type", "status", "ownerId", "review", "reviewDue"],
  search: ["number", "name"],
};
