import type { BlockOf } from "../define-block.ts";
import type { InspectionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { inspectionsEvents } from "./events.ts";
import { createInspections } from "./inspections.ts";
import { inspectionListSurface } from "./lists.ts";
import { inspectionsSqlOptions } from "./options.ts";
import {
  inspectionFindingInputSchema,
  inspectionInputSchema,
  inspectionProgramInputSchema,
} from "./schemas.ts";

/** The `inspections` block's manifest (ADR 0029, ADR 0132). */
export const inspectionsBlock: BlockOf<
  "inspections",
  typeof createInspections,
  InspectionsEvents
> = defineBlock({
  name: "inspections",
  sql: ["inspections"],
  options: { inspections: inspectionsSqlOptions },
  events: inspectionsEvents,
  schemas: {
    inspection: { input: inspectionInputSchema },
    inspection_program: { input: inspectionProgramInputSchema },
    inspection_finding: { input: inspectionFindingInputSchema },
  },
  create: createInspections,
  recipes: ["inspection-program-calendar", "inspection-run"],
  category: "work",
  entities: {
    inspection: {
      ...inspectionListSurface,
      mutability: "editable",
      emits: { create: false, update: true },
    },
    inspection_program: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    inspection_finding: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
    inspection_member: { mutability: "read-only" },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Audit programmes, inspections numbered AUD-2026-001 with a team and a checklist form, findings typed as nonconformities, observations or opportunities, and cases opened from nonconformities before an inspection closes.",
  schedules: [
    {
      name: "overdue",
      cron: "0 6 * * *",
      runs: "notifyOverdue()",
      description:
        "Tells the lead of each inspection past its planned end, once per planned end.",
    },
  ],
});
