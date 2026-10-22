import type { BlockOf } from "../define-block.ts";
import type { NumberingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { numberingEvents } from "./events.ts";
import { createNumbering } from "./numbering.ts";
import { numberingSqlOptions } from "./options.ts";

/** The `numbering` block's manifest (ADR 0029). */
export const numberingBlock: BlockOf<
  "numbering",
  typeof createNumbering,
  NumberingEvents
> = defineBlock({
  name: "numbering",
  sql: ["numbering"],
  options: { numbering: numberingSqlOptions },
  events: numberingEvents,
  create: createNumbering,
  category: "database",
});
