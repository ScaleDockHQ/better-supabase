import type { BlockOf } from "../define-block.ts";
import type { BankingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createBanking } from "./banking.ts";
import { bankingEvents } from "./events.ts";
import { bankingSqlOptions } from "./options.ts";
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
  options: { banking: bankingSqlOptions },
  events: bankingEvents,
  schemas: {
    bank_account: { input: bankAccountInputSchema },
    bank_match: { input: bankMatchInputSchema },
    bank_rule: { input: bankRuleInputSchema },
  },
  create: createBanking,
  recipes: ["bank-reconciliation"],
  category: "commerce",
});
