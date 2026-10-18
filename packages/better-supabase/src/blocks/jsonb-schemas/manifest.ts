import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `jsonb-schemas` block's manifest (ADR 0029). */
export const jsonbSchemasBlock: Block<"jsonb-schemas"> = defineBlock({
  name: "jsonb-schemas",
  sql: ["jsonb-schemas"],
  category: "database",
});
