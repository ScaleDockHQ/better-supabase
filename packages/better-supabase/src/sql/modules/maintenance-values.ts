// The maintenance block's fixed values. This file imports nothing, so the
// client entry can read them without the SQL builders.

/** What makes a plan fall due. */
export const MAINTENANCE_PLAN_KINDS = ["time", "meter"] as const;

/** Whether a plan creates work orders. */
export const MAINTENANCE_PLAN_STATUSES = ["active", "paused"] as const;

/** How a calibration turned out. */
export const MAINTENANCE_CALIBRATION_RESULTS = [
  "pass",
  "fail",
  "adjusted",
] as const;

/** The priorities a plan's work orders take, as the dispatch block names them. */
export const MAINTENANCE_PRIORITIES = [
  "low",
  "normal",
  "high",
  "urgent",
] as const;
