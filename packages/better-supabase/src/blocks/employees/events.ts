import type { EmployeeEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `employees` block: type to data. */
export type EmployeesEvents = {
  readonly "employee.created": EmployeeEventData;
  readonly "employee.updated": EmployeeEventData;
  readonly "employee.offboarded": EmployeeEventData;
  readonly "employee.manager_changed": EmployeeEventData;
  readonly "employee.deleted": EmployeeEventData;
};

/** The `employees` block's event types, for its manifest and `onBlockEvent`. */
export const employeesEvents: Events<EmployeesEvents> = defineEvents({
  "employee.created": event<EmployeeEventData>(),
  "employee.updated": event<EmployeeEventData>(),
  "employee.offboarded": event<EmployeeEventData>(),
  "employee.manager_changed": event<EmployeeEventData>(),
  "employee.deleted": event<EmployeeEventData>(),
});
