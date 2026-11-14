import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `approvals.page`, `approvals.facets` and `approvals.count` accept for an
 * approval request (ADR 0749). The manifest declares the same names, and the
 * SQL list function `page_approvals` implements them. `assigned` is a flag
 * filter: `["true"]` keeps the requests the caller can decide.
 */
export const approvalListSurface: EntityListSurface = {
  sorts: ["createdAt", "action"],
  facets: ["status", "subjectType"],
  filters: ["status", "subjectType", "subjectId", "action", "assigned"],
};
