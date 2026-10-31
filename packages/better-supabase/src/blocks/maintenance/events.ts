import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `maintenance_plan.*` event carries. */
export interface MaintenancePlanEventData {
  readonly organizationId: string;
  /** The plan. */
  readonly id: string;
  readonly title: string;
  /** `time` or `meter`. */
  readonly kind: string;
  /** `active` or `paused`. */
  readonly status: string;
}

/** `maintenance_plan.triggered` and `maintenance_plan.completed`. */
export interface MaintenancePlanWorkOrderEventData extends MaintenancePlanEventData {
  /** The dispatch work order the plan opened. */
  readonly workOrderId: string;
}

/** `maintenance_meter_reading.recorded`. */
export interface MaintenanceMeterReadingEventData {
  readonly organizationId: string;
  readonly meterId: string;
  /** The reading as a decimal string. */
  readonly value: string;
  readonly readAt: string;
}

/** `maintenance_calibration.recorded`. */
export interface MaintenanceCalibrationEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly assetId: string | null;
  readonly instrument: string;
  /** `pass`, `fail` or `adjusted`. */
  readonly result: string;
}

/** The events of the `maintenance` block: type to data. */
export type MaintenanceEvents = {
  readonly "maintenance_plan.created": MaintenancePlanEventData;
  readonly "maintenance_plan.updated": MaintenancePlanEventData;
  readonly "maintenance_plan.deleted": MaintenancePlanEventData;
  readonly "maintenance_plan.triggered": MaintenancePlanWorkOrderEventData;
  readonly "maintenance_plan.completed": MaintenancePlanWorkOrderEventData;
  readonly "maintenance_meter_reading.recorded": MaintenanceMeterReadingEventData;
  readonly "maintenance_calibration.recorded": MaintenanceCalibrationEventData;
};

/** The `maintenance` block's event types, for its manifest and `onBlockEvent`. */
export const maintenanceEvents: Events<MaintenanceEvents> = defineEvents({
  "maintenance_plan.created": event<MaintenancePlanEventData>(),
  "maintenance_plan.updated": event<MaintenancePlanEventData>(),
  "maintenance_plan.deleted": event<MaintenancePlanEventData>(),
  "maintenance_plan.triggered": event<MaintenancePlanWorkOrderEventData>(),
  "maintenance_plan.completed": event<MaintenancePlanWorkOrderEventData>(),
  "maintenance_meter_reading.recorded":
    event<MaintenanceMeterReadingEventData>(),
  "maintenance_calibration.recorded": event<MaintenanceCalibrationEventData>(),
});
