import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `giftPage`, `giftFacets` and `giftCount` accept for a gift (ADR 0749).
 * The manifest declares the same names, and the SQL list function `list_gifts`
 * implements them.
 */
export const giftListSurface: EntityListSurface = {
  sorts: ["receivedOn", "createdAt"],
  facets: ["status", "fundId"],
  filters: ["donorType", "donorId", "fundId", "pledgeId", "status"],
};

/**
 * What `pledgePage`, `pledgeFacets` and `pledgeCount` accept for a pledge. The
 * SQL list function is `list_pledges`.
 */
export const pledgeListSurface: EntityListSurface = {
  sorts: ["createdAt"],
  facets: ["status"],
  filters: ["donorType", "donorId", "status"],
};
