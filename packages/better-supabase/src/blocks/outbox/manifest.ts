import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { outboxSqlOptions } from "./options.ts";

/** The `outbox` block's manifest (ADR 0029). */
export const outboxBlock: Block<"outbox"> = defineBlock({
  name: "outbox",
  sql: ["outbox"],
  options: {
    outbox: outboxSqlOptions,
  },
  category: "platform",
});
