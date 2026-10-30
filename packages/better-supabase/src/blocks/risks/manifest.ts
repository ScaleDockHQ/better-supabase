import type { BlockOf } from "../define-block.ts";
import type { RisksEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { risksEvents } from "./events.ts";
import { risksSqlOptions } from "./options.ts";
import { createRisks } from "./risks.ts";
import {
  riskAssessmentInputSchema,
  riskInputSchema,
  riskMatrixInputSchema,
} from "./schemas.ts";

/** The `risks` block's manifest (ADR 0029). */
export const risksBlock: BlockOf<"risks", typeof createRisks, RisksEvents> =
  defineBlock({
    name: "risks",
    sql: ["risks"],
    options: { risks: risksSqlOptions },
    events: risksEvents,
    schemas: {
      risk: { input: riskInputSchema },
      risk_matrix: { input: riskMatrixInputSchema },
      risk_assessment: { input: riskAssessmentInputSchema },
    },
    create: createRisks,
    recipes: ["risk-register", "risk-heatmap"],
    category: "work",
    schedules: [
      {
        name: "review-due",
        cron: "0 6 * * *",
        runs: "notifyDueReviews()",
        description: "Reports the risks whose review date has come.",
      },
    ],
  });
