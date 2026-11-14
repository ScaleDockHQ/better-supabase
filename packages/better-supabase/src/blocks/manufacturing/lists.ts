import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `orderPage`, `orderFacets` and `orderCount` accept for a production
 * order (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_production_orders` implements them.
 */
export const productionOrderListSurface: EntityListSurface = {
  sorts: ["dueOn", "createdAt", "number"],
  facets: ["status"],
  filters: ["status", "variantId"],
};
