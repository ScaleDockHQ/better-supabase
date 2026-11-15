import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `sessionPage`, `sessionFacets` and `sessionCount` accept for a support
 * session (ADR 0749, 1077). The manifest declares the same names, and the SQL
 * list function `page_support_sessions` implements them. The list is
 * platform-wide, so it takes no organization. `active` is a flag filter:
 * `["true"]` keeps the sessions still running.
 */
export const sessionListSurface: EntityListSurface = {
  sorts: ["startedAt", "expiresAt"],
  facets: ["readOnly"],
  filters: ["adminId", "targetUserId", "tenant", "active"],
};
