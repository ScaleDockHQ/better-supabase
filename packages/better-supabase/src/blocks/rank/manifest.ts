import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createRank } from "./rank.ts";

/** The `rank` block's manifest (ADR 0029). */
export const rankBlock: BlockOf<"rank", typeof createRank> = defineBlock({
  name: "rank",
  sql: ["rank"],
  create: createRank,
  category: "database",
  description:
    "Fractional rank keys: rank_between, move() for every config.recordTypes entry with a rank column (through the caller's policies and any state-machine trigger), and a rebalance job.",
  recipes: ["record-board", "work-item-board"],
});
