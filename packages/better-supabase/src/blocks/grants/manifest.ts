import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `grants` block's manifest (ADR 0029). */
export const grantsBlock: Block<"grants"> = defineBlock({
  name: "grants",
  sql: ["grants"],
  options: {
    grants: optionKeys(["fromPolicies"]),
  },
  category: "platform",
});
