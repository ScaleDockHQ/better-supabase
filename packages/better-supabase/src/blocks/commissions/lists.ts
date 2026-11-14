import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `commissionPlanPage`, `commissionPlanFacets` and `commissionPlanCount`
 * accept for a commission plan (ADR 0749). The manifest declares the same
 * names, and the SQL list function `list_commission_plans` implements them.
 */
export const commissionPlanListSurface: EntityListSurface = {
  sorts: ["createdAt", "name"],
  facets: ["kind"],
  filters: ["archived"],
};

/**
 * What `commissionPage`, `commissionFacets` and `commissionCount` accept for an
 * accrued commission. The SQL list function is `list_commissions`.
 */
export const commissionListSurface: EntityListSurface = {
  sorts: ["occurredOn", "createdAt", "amount"],
  facets: ["status", "seller"],
  filters: ["status", "seller"],
};

/**
 * What `statementPage`, `statementFacets` and `statementCount` accept for a
 * commission statement. The SQL list function is `list_commission_statements`.
 */
export const commissionStatementListSurface: EntityListSurface = {
  sorts: ["endsOn", "createdAt", "total"],
  facets: ["status", "seller"],
  filters: ["status", "seller"],
};
