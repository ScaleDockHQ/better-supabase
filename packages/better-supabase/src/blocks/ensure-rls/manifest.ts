import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `ensure-rls` block's manifest (ADR 0029). */
export const ensureRlsBlock: Block<"ensure-rls"> = defineBlock({
  name: "ensure-rls",
  sql: ["ensure-rls"],
  category: "platform",
});
