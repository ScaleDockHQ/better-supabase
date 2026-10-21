import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { grantsSqlOptions } from "./options.ts";

/** The `grants` block's manifest (ADR 0029). */
export const grantsBlock: Block<"grants"> = defineBlock({
  name: "grants",
  sql: ["grants"],
  options: { grants: grantsSqlOptions },
  category: "identity",
});
