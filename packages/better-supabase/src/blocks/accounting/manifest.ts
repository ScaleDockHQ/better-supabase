import type { BlockOf } from "../define-block.ts";
import type { AccountingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAccounting } from "./accounting.ts";
import { accountingEvents } from "./events.ts";
import { accountingSqlOptions } from "./options.ts";
import {
  accountingAccountInputSchema,
  accountingEntryInputSchema,
  accountingJournalInputSchema,
  accountingTaxCodeInputSchema,
} from "./schemas.ts";

/** The `accounting` block's manifest (ADR 0029). */
export const accountingBlock: BlockOf<
  "accounting",
  typeof createAccounting,
  AccountingEvents
> = defineBlock({
  name: "accounting",
  sql: ["accounting"],
  options: { accounting: accountingSqlOptions },
  events: accountingEvents,
  schemas: {
    accounting_account: { input: accountingAccountInputSchema },
    accounting_journal: { input: accountingJournalInputSchema },
    accounting_entry: { input: accountingEntryInputSchema },
    accounting_tax_code: { input: accountingTaxCodeInputSchema },
  },
  create: createAccounting,
  recipes: ["trial-balance"],
  category: "commerce",
});
