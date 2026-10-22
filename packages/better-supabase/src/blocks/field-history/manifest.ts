import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createFieldHistory } from "./field-history.ts";
import { fieldHistorySqlOptions } from "./options.ts";

/** The `field-history` block's manifest (ADR 0029). */
export const fieldHistoryBlock: BlockOf<
  "field-history",
  typeof createFieldHistory
> = defineBlock({
  name: "field-history",
  sql: ["field-history"],
  options: { "field-history": fieldHistorySqlOptions },
  create: createFieldHistory,
  category: "database",
});
