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
    entities: {
      rfq: { mutability: "editable", emits: { create: true, update: true } },
      rfq_line: { mutability: "read-only" },
      rfq_supplier: { mutability: "read-only" },
      rfq_quote: { mutability: "state-machine", emits: { create: false } },
      rfq_quote_line: { mutability: "read-only" },
    },
    description:
      "Requests for quotation to invited suppliers, their quotes per line, a side by side comparison and an award that marks the winner and can create the purchase order.",
  });
