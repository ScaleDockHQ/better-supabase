import type { BlockOf } from "../define-block.ts";
import type { MaintenanceEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { maintenanceEvents } from "./events.ts";
import { createMaintenance } from "./maintenance.ts";
import {
  maintenanceCalibrationInputSchema,
  maintenancePlanInputSchema,
} from "./schemas.ts";

/** The `maintenance` block's manifest (ADR 0029). */
export const maintenanceBlock: BlockOf<
  "maintenance",
  typeof createMaintenance,
  MaintenanceEvents
> = defineBlock({
  name: "maintenance",
  sql: ["maintenance"],
  events: maintenanceEvents,
  schemas: {
    maintenance_plan: { input: maintenancePlanInputSchema },
    maintenance_calibration: { input: maintenanceCalibrationInputSchema },
  },
  create: createMaintenance,
  recipes: [],
  category: "work",
  description:
    "Preventive maintenance plans that fall due by time, by a meter or by an RRULE, meter readings, calibration records, and the dispatch work orders the plans open with their spare parts. Technicians and calibrations can require qualifications.",
});
