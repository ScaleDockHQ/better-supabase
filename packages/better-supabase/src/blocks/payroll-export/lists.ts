import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `runPage`, `runFacets` and `runCount` accept for a payroll run (ADR
 * 0749, 0779). The manifest declares the same names, and the SQL list function
 * `page_payroll_runs` implements them.
 */
export const payrollRunListSurface: EntityListSurface = {
  sorts: ["periodFrom", "createdAt"],
  facets: ["status"],
  filters: ["status"],
};
