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
});
