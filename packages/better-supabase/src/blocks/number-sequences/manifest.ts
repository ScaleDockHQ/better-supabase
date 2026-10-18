import type { BlockOf } from "../define-block.ts";
import type { NumberSequencesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { numberSequencesEvents } from "./events.ts";
import { createNumberSequences } from "./number-sequences.ts";
import { numberSequencesSqlOptions } from "./options.ts";

/** The `number-sequences` block's manifest (ADR 0029). */
export const numberSequencesBlock: BlockOf<
  "number-sequences",
  typeof createNumberSequences,
  NumberSequencesEvents
> = defineBlock({
  name: "number-sequences",
  sql: ["number-sequences"],
  options: {
    "number-sequences": numberSequencesSqlOptions,
  },
  events: numberSequencesEvents,
  create: createNumberSequences,
  category: "database",
});
