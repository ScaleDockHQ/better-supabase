import type { BlockOf } from "../define-block.ts";
import type { MedicationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { medicationsEvents } from "./events.ts";
import { createMedications } from "./medications.ts";
import { medicationsSqlOptions } from "./options.ts";
import {
  medicationInputSchema,
  medicationOrderInputSchema,
} from "./schemas.ts";

/** The `medications` block's manifest (ADR 0029). */
export const medicationsBlock: BlockOf<
  "medications",
  typeof createMedications,
  MedicationsEvents
> = defineBlock({
  name: "medications",
  sql: ["medications"],
  options: { medications: medicationsSqlOptions },
  events: medicationsEvents,
  schemas: {
    medication: { input: medicationInputSchema },
    medication_order: { input: medicationOrderInputSchema },
  },
  create: createMedications,
  recipes: ["medication-chart"],
  category: "people",
});
