import type { BlockOf } from "../define-block.ts";
import type { CasesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCases } from "./cases.ts";
import { casesEvents } from "./events.ts";
import { casesSqlOptions } from "./options.ts";
import {
  caseActionInputSchema,
  caseInputSchema,
  caseKindInputSchema,
} from "./schemas.ts";

/** The `cases` block's manifest (ADR 0029, ADR 0132). */
export const casesBlock: BlockOf<"cases", typeof createCases, CasesEvents> =
  defineBlock({
    name: "cases",
    sql: ["cases"],
    options: { cases: casesSqlOptions },
    events: casesEvents,
    schemas: {
      case: { input: caseInputSchema },
      case_kind: { input: caseKindInputSchema },
      case_action: { input: caseActionInputSchema },
    },
    create: createCases,
    recipes: ["case-board", "case-detail"],
    category: "work",
    schedules: [
      {
        name: "effectiveness-due",
        cron: "0 6 * * *",
        runs: "notifyDueEffectiveness()",
        description:
          "Reports the cases whose effectiveness check date has come.",
      },
    ],
  });
