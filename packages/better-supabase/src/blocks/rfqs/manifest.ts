import type { BlockOf } from "../define-block.ts";
import type { RfqsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { rfqsEvents } from "./events.ts";
import { createRfqs } from "./rfqs.ts";
import { rfqInputSchema } from "./schemas.ts";

/** The `rfqs` block's manifest (ADR 0029). */
export const rfqsBlock: BlockOf<"rfqs", typeof createRfqs, RfqsEvents> =
  defineBlock({
    name: "rfqs",
    sql: ["rfqs"],
    events: rfqsEvents,
    schemas: { rfq: { input: rfqInputSchema } },
    create: createRfqs,
    recipes: [],
    category: "commerce",
  });
