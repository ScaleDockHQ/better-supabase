import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `categoryPage`, `categoryFacets` and `categoryCount` accept for an
 * expense category (ADR 0749, 1077). Archived categories are hidden unless
 * `archived` is `["true"]` (only the archived ones). The SQL list function is
 * `page_expense_categories`.
 */
export const expenseCategoryListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["currency"],
  filters: ["currency", "archived"],
  search: ["name"],
};

/**
 * The same for an expense report (`page_expense_reports`). `mine` is
 * `["true"]`: a member with `expenses.read` otherwise sees every member's
 * reports, and one without sees only their own.
 */
export const expenseReportListSurface: EntityListSurface = {
  sorts: ["createdAt", "title"],
  facets: ["status", "currency"],
  filters: ["userId", "status", "currency", "mine"],
  search: ["title"],
};

/**
 * The same for an expense when reports are off (`page_expenses`). `mine` works
 * as it does for reports.
 */
export const expenseListSurface: EntityListSurface = {
  sorts: ["spentOn", "amount", "createdAt"],
  facets: ["status", "currency"],
  filters: ["userId", "status", "currency", "categoryId", "mine"],
  search: ["description", "merchant"],
};
