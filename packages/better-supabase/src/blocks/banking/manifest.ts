import type { BlockOf } from "../define-block.ts";
import type { BankingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBanking } from "./banking.ts";
import { bankingEvents } from "./events.ts";
import {
  bankAccountInputSchema,
  bankMatchInputSchema,
  bankRuleInputSchema,
} from "./schemas.ts";

/** The `banking` block's manifest (ADR 0029, ADR 0149). */
export const bankingBlock: BlockOf<
  "banking",
  typeof createBanking,
  BankingEvents
> = defineBlock({
  name: "banking",
  sql: ["banking"],
  events: bankingEvents,
  schemas: {
    bank_account: { input: bankAccountInputSchema },
    bank_match: { input: bankMatchInputSchema },
    bank_rule: { input: bankRuleInputSchema },
  },
  create: createBanking,
  recipes: ["bank-reconciliation"],
  category: "commerce",
  entities: {
    bank_transaction: { mutability: "state-machine" },
    bank_account: { mutability: "editable", emits: { update: false } },
    bank_statement: { mutability: "state-machine" },
    bank_match: { mutability: "read-only" },
    bank_rule: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Bank accounts with imported CAMT.053, MT940 and feed statements, matches of each transaction to invoices, expense reports and accounting entries with suggestions from RF and Dutch payment references, bank rules that book or set aside what they match, and a reconciliation status per account against the ledger.",
});
