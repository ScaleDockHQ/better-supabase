import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `rls-guard` block's manifest (ADR 0029). */
export const rlsGuardBlock: Block<"rls-guard"> = defineBlock({
  name: "rls-guard",
  sql: ["rls-guard"],
  category: "database",
});
