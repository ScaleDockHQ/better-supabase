import type { BlockOf } from "../define-block.ts";
import type { PayrollExportEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { payrollExportEvents } from "./events.ts";
import { payrollRunListSurface } from "./lists.ts";
import { payrollExportSqlOptions } from "./options.ts";
import { createPayrollExport } from "./payroll-export.ts";
import { payrollRunInputSchema } from "./schemas.ts";

/** The `payroll-export` block's manifest (ADR 0029, ADR 0155). */
export const payrollExportBlock: BlockOf<
  "payroll-export",
  typeof createPayrollExport,
  PayrollExportEvents
> = defineBlock({
  name: "payroll-export",
  sql: ["payroll-export"],
  options: { "payroll-export": payrollExportSqlOptions },
  events: payrollExportEvents,
  schemas: { payroll_run: { input: payrollRunInputSchema } },
  create: createPayrollExport,
  recipes: ["payroll-runs"],
  category: "people",
  entities: {
    payroll_run: {
      ...payrollRunListSurface,
      mutability: "state-machine",
      emits: { create: true, delete: false },
    },
    payroll_line: { mutability: "read-only" },
  },
  concerns: ["lifecycle"],
  description:
    "Payroll runs that collect the hours worked, the approved leave and optionally the scheduled shifts of a period into lines per person, locked by an export through a versioned PayrollExportFormat port.",
});
