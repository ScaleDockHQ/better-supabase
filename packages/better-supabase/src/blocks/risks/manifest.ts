import type { BlockOf } from "../define-block.ts";
import type { RisksEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { risksEvents } from "./events.ts";
import { risksSqlOptions } from "./options.ts";
import { createRisks } from "./risks.ts";
import { riskInputSchema } from "./schemas.ts";

/** The `risks` block's manifest (ADR 0029). */
export const risksBlock: BlockOf<"risks", typeof createRisks, RisksEvents> =
  defineBlock({
    name: "risks",
    sql: ["risks"],
    options: { risks: risksSqlOptions },
    events: risksEvents,
    schemas: { risk: { input: riskInputSchema } },
    create: createRisks,
    recipes: [],
    category: "work",
  });
