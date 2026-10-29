import type { BlockOf } from "../define-block.ts";
import type { InspectionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { inspectionsEvents } from "./events.ts";
import { createInspections } from "./inspections.ts";
import { inspectionsSqlOptions } from "./options.ts";
import { inspectionInputSchema } from "./schemas.ts";

/** The `inspections` block's manifest (ADR 0029). */
export const inspectionsBlock: BlockOf<
  "inspections",
  typeof createInspections,
  InspectionsEvents
> = defineBlock({
  name: "inspections",
  sql: ["inspections"],
  options: { inspections: inspectionsSqlOptions },
  events: inspectionsEvents,
  schemas: { inspection: { input: inspectionInputSchema } },
  create: createInspections,
  recipes: [],
  category: "work",
});
