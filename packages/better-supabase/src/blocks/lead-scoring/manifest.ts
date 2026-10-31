import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createLeadScoring } from "./lead-scoring.ts";
import { leadScoringSqlOptions } from "./options.ts";

/** The `lead-scoring` block's manifest (ADR 0029, ADR 0067). */
export const leadScoringBlock: BlockOf<
  "lead-scoring",
  typeof createLeadScoring
> = defineBlock({
  name: "lead-scoring",
  sql: ["lead-scoring"],
  options: { "lead-scoring": leadScoringSqlOptions },
  create: createLeadScoring,
  category: "crm",
});
