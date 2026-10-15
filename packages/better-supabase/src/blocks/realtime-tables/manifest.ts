import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `realtime-tables` block's manifest (ADR 0029). */
export const realtimeTablesBlock: Block<"realtime-tables"> = defineBlock({
  name: "realtime-tables",
  sql: ["realtime-tables"],
  category: "platform",
});
