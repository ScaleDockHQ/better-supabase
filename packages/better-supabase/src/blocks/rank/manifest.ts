import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createRank } from "./rank.ts";

/** The `rank` block's manifest (ADR 0029). */
export const rankBlock: BlockOf<"rank", typeof createRank> = defineBlock({
  name: "rank",
  sql: ["rank"],
  create: createRank,
  category: "database",
  recipes: ["record-board", "work-item-board"],
});
