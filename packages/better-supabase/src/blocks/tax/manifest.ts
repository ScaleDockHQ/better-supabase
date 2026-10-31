import type { BlockOf } from "../define-block.ts";
import type { TaxEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { taxEvents } from "./events.ts";
import { taxCodeInputSchema } from "./schemas.ts";
import { createTax } from "./tax.ts";

/** The `tax` block's manifest (ADR 0029, ADR 0143). */
export const taxBlock: BlockOf<"tax", typeof createTax, TaxEvents> =
  defineBlock({
    name: "tax",
    sql: ["tax"],
    events: taxEvents,
    schemas: { tax_code: { input: taxCodeInputSchema } },
    create: createTax,
    category: "commerce",
  });
