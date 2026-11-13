import type { BlockOf } from "../define-block.ts";
import type { ObservationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { observationsEvents } from "./events.ts";
import { createObservations } from "./observations.ts";
import { observationsSqlOptions } from "./options.ts";
import {
  observationDefinitionInputSchema,
  observationInputSchema,
} from "./schemas.ts";

/** The `observations` block's manifest (ADR 0029). */
export const observationsBlock: BlockOf<
  "observations",
  typeof createObservations,
  ObservationsEvents
> = defineBlock({
  name: "observations",
  sql: ["observations"],
  options: { observations: observationsSqlOptions },
  events: observationsEvents,
  schemas: {
    observation_definition: { input: observationDefinitionInputSchema },
    observation: { input: observationInputSchema },
  },
  create: createObservations,
  recipes: ["observation-chart"],
  category: "people",
  entities: {
    observation: { mutability: "state-machine", emits: { create: true } },
    observation_definition: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Typed measurements of a record against definitions with a UCUM unit, a code (LOINC for the shipped vital signs) and valid, reference and critical ranges: a computed flag, critical alerts to the record team's leads, amendments and entered-in-error corrections, idempotent device ingest, series and latest values, and observations mapped from form submissions.",
});
