import type { BlockOf } from "../define-block.ts";
import type { EPrescribingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createEPrescribing } from "./e-prescribing.ts";
import { ePrescribingEvents } from "./events.ts";

/** The `e-prescribing` block's manifest (ADR 0029). */
export const ePrescribingBlock: BlockOf<
  "e-prescribing",
  typeof createEPrescribing,
  EPrescribingEvents
> = defineBlock({
  name: "e-prescribing",
  sql: ["e-prescribing"],
  events: ePrescribingEvents,
  schemas: {},
  create: createEPrescribing,
  recipes: [],
  category: "people",
  entities: {
    prescription: { mutability: "state-machine", emits: { create: true } },
  },
  concerns: ["lifecycle"],
  description:
    "Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.",
});
