import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `outbox` block's manifest (ADR 0029). */
export const outboxBlock: Block<"outbox"> = defineBlock({
  name: "outbox",
  sql: ["outbox"],
  options: {
    outbox: optionKeys([
      "defaultSource",
      "emitRoles",
      "blockSource",
      "retention",
      "settle",
    ]),
  },
  category: "platform",
});
