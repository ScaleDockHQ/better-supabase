import type { BlockOf } from "../define-block.ts";
import type { MedicationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { OFFLINE_RULES } from "../offline-rules.ts";
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
  entities: {
    medication: {
      mutability: "editable",
      emits: { update: false },
      offline: OFFLINE_RULES.medications,
    },
    medication_order: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
    medication_administration: {
      mutability: "state-machine",
      emits: { create: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "A medication catalog per organization, orders for a record with a dose, route, schedule and an as-needed maximum, orders imported from a pharmacy, planned doses, each dose recorded as given, refused, skipped or missed with a second check for high-risk medication, and a medication chart per record.",
});
