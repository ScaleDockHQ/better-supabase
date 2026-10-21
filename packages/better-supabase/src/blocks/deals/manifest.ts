import type { BlockOf } from "../define-block.ts";
import type { DealsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDeals } from "./deals.ts";
import { dealsEvents } from "./events.ts";
import { dealsSqlOptions } from "./options.ts";
import { dealChangeSchema, dealInputSchema } from "./schemas.ts";

/** The `deals` block's manifest (ADR 0029). */
export const dealsBlock: BlockOf<"deals", typeof createDeals, DealsEvents> =
  defineBlock({
    name: "deals",
    sql: ["deals"],
    options: { deals: dealsSqlOptions },
    events: dealsEvents,
    create: createDeals,
    category: "crm",
    recipes: ["deal-board"],
    schemas: { deal: { input: dealInputSchema, change: dealChangeSchema } },
  });
