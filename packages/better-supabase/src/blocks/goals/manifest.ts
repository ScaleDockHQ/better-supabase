import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createGoals } from "./goals.ts";
import { goalsSqlOptions } from "./options.ts";

/** The `goals` block's manifest (ADR 0029). */
export const goalsBlock: BlockOf<"goals", typeof createGoals> = defineBlock({
  name: "goals",
  sql: ["goals"],
  options: { goals: goalsSqlOptions },
  create: createGoals,
  category: "crm",
  recipes: ["targets-progress"],
});
