import type { BlockOf } from "../define-block.ts";
import type { InvoicesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { invoicesEvents } from "./events.ts";
import { createInvoices } from "./invoices.ts";
import { invoicesSqlOptions } from "./options.ts";

/** The `invoices` block's manifest (ADR 0029). */
export const invoicesBlock: BlockOf<
  "invoices",
  typeof createInvoices,
  InvoicesEvents
> = defineBlock({
  name: "invoices",
  sql: ["invoices"],
  options: { invoices: invoicesSqlOptions },
  events: invoicesEvents,
  create: createInvoices,
  category: "commerce",
  entities: {
    invoice: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "Invoices an organization sends its own customers and bills from its suppliers: drafts with lines, a gapless number per direction on issue, payments, credit notes, void and write-off, overdue and aging per currency, credit limits, the three-way match of a purchase bill, party payments split over invoices with the rest kept as credit, dunning levels, and invoices from accepted quotes.",
  recipes: ["invoices-table"],
  schedules: [
    {
      name: "dunning",
      cron: "0 6 * * *",
      runs: "runDunning()",
      description:
        "Raises overdue invoices to the reminder level they reached and adds the level's fee.",
    },
  ],
});
