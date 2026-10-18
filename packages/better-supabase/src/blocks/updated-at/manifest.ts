import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `updated-at` block's manifest (ADR 0029). */
export const updatedAtBlock: Block<"updated-at"> = defineBlock({
  name: "updated-at",
  sql: ["updated-at"],
  category: "database",
});
