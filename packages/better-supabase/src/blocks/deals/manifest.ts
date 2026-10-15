import type { BlockOf } from "../define-block.ts";
import type { DealsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createDeals } from "./deals.ts";
import { dealsEvents } from "./events.ts";

/** The `deals` block's manifest (ADR 0029). */
export const dealsBlock: BlockOf<"deals", typeof createDeals, DealsEvents> =
  defineBlock({
    name: "deals",
    sql: ["deals"],
    options: {
      deals: optionKeys([
        "company",
        "contact",
        "motions",
        "priorities",
        "prefix",
        "readAll",
        "extraColumns",
      ]),
    },
    events: dealsEvents,
    create: createDeals,
    category: "crm",
  });
