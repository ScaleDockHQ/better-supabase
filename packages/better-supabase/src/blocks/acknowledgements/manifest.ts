import type { BlockOf } from "../define-block.ts";
import type { AcknowledgementsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAcknowledgements } from "./acknowledgements.ts";
import { acknowledgementsEvents } from "./events.ts";

/** The `acknowledgements` block's manifest (ADR 0029). */
export const acknowledgementsBlock: BlockOf<
  "acknowledgements",
  typeof createAcknowledgements,
  AcknowledgementsEvents
> = defineBlock({
  name: "acknowledgements",
  sql: ["acknowledgements"],
  events: acknowledgementsEvents,
  create: createAcknowledgements,
  category: "collaboration",
  recipes: ["acknowledgement-inbox"],
});
