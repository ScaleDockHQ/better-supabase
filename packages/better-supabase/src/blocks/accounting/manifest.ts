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
  },
  create: createAccounting,
  recipes: ["trial-balance"],
  category: "commerce",
  entities: {
    accounting_account: { mutability: "editable", emits: { update: false } },
    accounting_journal: { mutability: "editable", emits: { update: false } },
    accounting_period: { mutability: "state-machine" },
    accounting_entry: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
    accounting_dimension: { mutability: "editable", emits: { update: false } },
    accounting_budget: {
      mutability: "editable",
      emits: { create: true, update: true },
    },
  },
  description:
    "Double-entry books: a chart of accounts with account roles, journals, fiscal years of periods, balanced journal entries numbered per journal and year, dimensions, exchange rates, tax codes, the trial balance, profit and loss, balance sheet and general ledger, the period and year-end close, entries booked from invoices, expenses, stock, rent and gifts, tax reports and budgets.",
});
