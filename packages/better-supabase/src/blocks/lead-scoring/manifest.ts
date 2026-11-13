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
  entities: {
    lead_scoring: { mutability: "append-only", emits: { create: false } },
  },
  description:
    "Scores people, and optionally companies, under a tenant-editable score model. Each record's columns, enrichment status, segments and mail opens, clicks and replies feed the model, and the record is scored again when any of them change.",
});
