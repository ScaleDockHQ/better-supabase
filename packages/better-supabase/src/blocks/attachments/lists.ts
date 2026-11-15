import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `attachmentPage`, `attachmentFacets` and `attachmentCount` accept for a
 * file (ADR 0749, 1077). The manifest declares the same names, and the SQL list
 * function `page_attachments` implements them. `status` takes the scan states
 * `pending`, `clean`, `infected` and `failed`; `documentTypeId` needs a table
 * with document types.
 */
export const attachmentListSurface: EntityListSurface = {
  sorts: ["createdAt", "name", "size"],
  facets: ["status", "subjectType"],
  filters: ["subjectType", "subjectId", "status", "documentTypeId"],
  search: ["name"],
};
