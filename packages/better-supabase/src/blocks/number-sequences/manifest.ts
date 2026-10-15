import type { BlockOf } from "../define-block.ts";
import type { NumberSequencesEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { numberSequencesEvents } from "./events.ts";
import { createNumberSequences } from "./number-sequences.ts";

/** The `number-sequences` block's manifest (ADR 0029). */
export const numberSequencesBlock: BlockOf<
  "number-sequences",
  typeof createNumberSequences,
  NumberSequencesEvents
> = defineBlock({
  name: "number-sequences",
  sql: ["number-sequences"],
  options: {
    "number-sequences": optionKeys(["entities"]),
  },
  events: numberSequencesEvents,
  create: createNumberSequences,
  category: "platform",
});
