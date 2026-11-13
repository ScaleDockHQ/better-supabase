import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `warranty.page`, `warranty.facets` and `warranty.count` accept for a warranty claim (ADR
 * 0749). The manifest declares the same names, and the SQL list function
 * `list_warranty_claims` implements them.
 */
export const warrantyClaimListSurface: EntityListSurface = {
  sorts: ["createdAt", "amount"],
  facets: ["status"],
  filters: ["status", "assetId"],
};
