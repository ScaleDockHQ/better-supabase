import type { BlockOf } from "../define-block.ts";
import type { EmployeesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createEmployees } from "./employees.ts";
import { employeesEvents } from "./events.ts";
import { employeesSqlOptions } from "./options.ts";

/** The `employees` block's manifest (ADR 0029). */
export const employeesBlock: BlockOf<
  "employees",
  typeof createEmployees,
  EmployeesEvents
> = defineBlock({
  name: "employees",
  sql: ["employees"],
  options: { employees: employeesSqlOptions },
  events: employeesEvents,
  create: createEmployees,
  category: "people",
  recipes: ["employee-directory"],
});
