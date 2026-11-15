import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `requestPage`, `requestFacets` and `requestCount` accept for a signature
 * request (ADR 0749, 1077). The manifest declares the same names, and the SQL
 * list function `page_signature_requests` implements them. `mine` takes
 * `"true"` and keeps the requests the caller is asked to sign.
 */
export const signatureRequestListSurface: EntityListSurface = {
  sorts: ["createdAt", "completedAt"],
  facets: ["status"],
  filters: ["status", "subjectType", "subjectId", "mine"],
  search: ["subjectId", "message"],
};
