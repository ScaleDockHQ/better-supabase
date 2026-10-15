import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `pgtap` block's manifest (ADR 0029). */
export const pgtapBlock: Block<"pgtap"> = defineBlock({
  name: "pgtap",
  sql: ["pgtap"],
  category: "platform",
});
