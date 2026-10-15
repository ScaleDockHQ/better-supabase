import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `sessions` block's manifest (ADR 0029). */
export const sessionsBlock: Block<"sessions"> = defineBlock({
  name: "sessions",
  sql: ["sessions"],
  options: {
    sessions: optionKeys(["exclude", "policies"]),
  },
  category: "foundation",
});
