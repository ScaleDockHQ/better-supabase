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
  search: ["number", "note"],
};

/** The same for a bill of materials version (`page_boms`). */
export const bomListSurface: EntityListSurface = {
  sorts: ["variant", "createdAt", "activatedAt"],
  facets: ["status"],
  filters: ["variantId", "status"],
  search: ["note"],
};

/**
 * The same for a work center (`page_work_centers`). Archived work centers are
 * hidden unless `includeArchived` is `["true"]`.
 */
export const workCenterListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["currency"],
  filters: ["currency", "includeArchived"],
  search: ["name"],
};
