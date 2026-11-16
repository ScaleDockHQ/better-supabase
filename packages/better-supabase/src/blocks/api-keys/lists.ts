import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `keyPage`, `keyFacets` and `keyCount` accept for an API key (ADR 0749,
 * 1077). The manifest declares the same names, and the SQL list function
 * implements them. `revoked` takes `["true"]` or `["false"]`. Without an
 * `organizationId` the page lists the caller's personal keys.
 */
export const keyListSurface: EntityListSurface = {
  sorts: ["createdAt", "name", "expiresAt", "lastUsedAt"],
  facets: ["revoked"],
  filters: ["userId", "revoked"],
  search: ["name", "prefix"],
};
