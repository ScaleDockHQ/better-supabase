import type { BlockOf } from "../define-block.ts";
import type { EmployeesEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createEmployees } from "./employees.ts";
import { employeesEvents } from "./events.ts";

/** The `employees` block's manifest (ADR 0029). */
export const employeesBlock: BlockOf<
  "employees",
  typeof createEmployees,
  EmployeesEvents
> = defineBlock({
  name: "employees",
  sql: ["employees"],
  options: {
    employees: optionKeys(["employmentTypes", "extraColumns"]),
  },
  events: employeesEvents,
  create: createEmployees,
  category: "work",
});
