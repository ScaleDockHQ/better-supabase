import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `actor` block's manifest (ADR 0029). */
export const createdByBlock: Block<"created-by"> = defineBlock({
  name: "created-by",
  sql: ["created-by"],
  category: "identity",
});
