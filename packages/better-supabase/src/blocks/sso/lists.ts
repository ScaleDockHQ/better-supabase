import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `domainPage`, `domainFacets` and `domainCount` accept for an
 * organization domain (ADR 0749, 1077). The manifest declares the same names,
 * and the SQL list function implements them. `verified` and `enforceSso` take
 * `["true"]` or `["false"]`.
 */
export const domainListSurface: EntityListSurface = {
  sorts: ["domain", "verifiedAt"],
  facets: ["verified", "enforceSso"],
  filters: ["verified", "enforceSso", "autoJoinRole"],
  search: ["domain"],
};

/**
 * What `providerPage`, `providerFacets` and `providerCount` accept for an SSO
 * provider (ADR 0749, 1077). The manifest declares the same names, and the SQL
 * list function implements them.
 */
export const providerListSurface: EntityListSurface = {
  sorts: ["createdAt"],
  facets: ["type"],
  filters: ["type"],
};
