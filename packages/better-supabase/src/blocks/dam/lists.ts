import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `rightPage`, `rightFacets` and `rightCount` accept for a usage right
 * (ADR 0749). The manifest declares the same names, and the SQL list function
 * `list_usage_rights` implements them. `expiringWithinDays` is one value, such
 * as `["30"]`.
 */
export const damUsageRightListSurface: EntityListSurface = {
  sorts: ["expiresOn", "startsOn"],
  facets: ["status"],
  filters: ["nodeId", "status", "expiringWithinDays"],
};
