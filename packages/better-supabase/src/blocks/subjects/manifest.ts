import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `subjects` block's manifest (ADR 0029). */
export const subjectsBlock: Block<"subjects"> = defineBlock({
  name: "subjects",
  sql: ["subjects"],
  category: "foundation",
});
