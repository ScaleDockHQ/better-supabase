/** Where a bill of materials version stands; one version per variant is active. */
export const BOM_STATUSES = ["draft", "active", "archived"] as const;

/** Where a production order stands. */
export const PRODUCTION_ORDER_STATUSES = [
  "draft",
  "released",
  "in_progress",
  "done",
  "canceled",
] as const;

/** Where one operation of a production order stands. */
export const PRODUCTION_OPERATION_STATUSES = [
  "pending",
  "in_progress",
  "done",
] as const;

/** What `material_requirements` suggests for a shortage. */
export const REQUIREMENT_ACTIONS = ["produce", "purchase"] as const;

/** How many bill of materials levels an explosion follows. */
export const BOM_MAX_DEPTH = 20;
