import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `actor` block's manifest (ADR 0029). */
export const actorBlock: Block<"actor"> = defineBlock({
  name: "actor",
  sql: ["actor"],
  category: "foundation",
});
