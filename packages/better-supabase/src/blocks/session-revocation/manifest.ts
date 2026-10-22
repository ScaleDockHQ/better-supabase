import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { sessionRevocationSqlOptions } from "./options.ts";

/** The `sessions` block's manifest (ADR 0029). */
export const sessionRevocationBlock: Block<"session-revocation"> = defineBlock({
  name: "session-revocation",
  sql: ["session-revocation"],
  options: { "session-revocation": sessionRevocationSqlOptions },
  category: "identity",
  recipes: ["sessions-list"],
});
