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
    entities: {
      tax_code: {
        mutability: "editable",
        emits: { create: true, update: true },
      },
      tax_rate: { mutability: "editable", emits: { update: false } },
      tax_return: { mutability: "state-machine" },
    },
    description:
      "Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.",
  });
