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
  entities: {
    field_history: {
      mutability: "append-only",
      emits: { create: false },
      personalData: ["before", "after", "changedBy"],
      subjectColumn: "subjectId",
      erase: "anonymize",
      retention: "audit",
      legalHold: true,
      partition: { by: "changedAt", every: "month", archive: "detach" },
    },
  },
  description:
    "The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.",
});
