import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createFieldHistory } from "./field-history.ts";
import { fieldHistorySqlOptions } from "./options.ts";
import { fieldHistoryBinding } from "./record-binding.ts";

/** The `field-history` block's manifest (ADR 0029). */
export const fieldHistoryBlock: BlockOf<
  "field-history",
  typeof createFieldHistory,
  never,
  Record<never, never>,
  never,
  typeof fieldHistoryBinding
> = defineBlock({
  name: "field-history",
  sql: ["field-history"],
  options: { "field-history": fieldHistorySqlOptions },
  record: fieldHistoryBinding,
  create: createFieldHistory,
  category: "database",
});
