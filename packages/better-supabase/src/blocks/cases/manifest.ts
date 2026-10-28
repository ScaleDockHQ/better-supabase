import type { BlockOf } from "../define-block.ts";
import type { CasesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createCases } from "./cases.ts";
import { casesEvents } from "./events.ts";
import { casesSqlOptions } from "./options.ts";
import { caseInputSchema } from "./schemas.ts";

/** The `cases` block's manifest (ADR 0029). */
export const casesBlock: BlockOf<"cases", typeof createCases, CasesEvents> =
  defineBlock({
    name: "cases",
    sql: ["cases"],
    options: { cases: casesSqlOptions },
    events: casesEvents,
    schemas: { case: { input: caseInputSchema } },
    create: createCases,
    recipes: [],
    category: "work",
  });
