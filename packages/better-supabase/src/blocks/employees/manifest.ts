import type { BlockOf } from "../define-block.ts";
import type { EmployeesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { employeeFromApplicationFactory } from "./actions.ts";
import { createEmployees } from "./employees.ts";
import { employeesEvents } from "./events.ts";
import { employeesSqlOptions } from "./options.ts";
import { employeeChangeSchema, employeeInputSchema } from "./schemas.ts";

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
  entities: {
    employee: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "Employees with or without an account, a manager, team, job title, employment type and status, an org chart, offboarding, and private details and contracts behind employees.view_sensitive. With time-entries, time entries carry the employee_id of their member.",
  recipes: ["employee-directory"],
  actions: [
    {
      kind: "employees.from_application",
      title: "Preboard the hired candidate",
    },
  ],
  handlers: { "employees.from_application": employeeFromApplicationFactory },
  schemas: {
    employee: { input: employeeInputSchema, change: employeeChangeSchema },
  },
});
