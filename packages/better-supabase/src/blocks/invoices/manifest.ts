import type { BlockOf } from "../define-block.ts";
import type { InvoicesEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { invoicesEvents } from "./events.ts";
import { createInvoices } from "./invoices.ts";

/** The `invoices` block's manifest (ADR 0029). */
export const invoicesBlock: BlockOf<
  "invoices",
  typeof createInvoices,
  InvoicesEvents
> = defineBlock({
  name: "invoices",
  sql: ["invoices"],
  options: {
    invoices: optionKeys([
      "company",
      "contact",
      "prefix",
      "creditPrefix",
      "termsDays",
      "extraColumns",
    ]),
  },
  events: invoicesEvents,
  create: createInvoices,
  category: "commerce",
});
