import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `planPage`, `planFacets` and `planCount` accept for a maintenance plan
 * (ADR 0749). The manifest declares the same names, and the SQL list function
 * `list_maintenance_plans` implements them. `due` is `["true"]`.
 */
export const maintenancePlanListSurface: EntityListSurface = {
  sorts: ["nextDueAt", "title"],
  facets: ["status", "kind"],
  filters: ["status", "kind", "assetId", "due"],
};

/**
 * The same for a calibration (`list_calibrations`). `dueBefore` is one instant,
 * such as `["2026-12-01T00:00:00Z"]`.
 */
export const maintenanceCalibrationListSurface: EntityListSurface = {
  sorts: ["performedAt", "dueAt"],
  facets: ["result"],
  filters: ["assetId", "dueBefore"],
};
