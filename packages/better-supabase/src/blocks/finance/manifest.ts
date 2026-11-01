import type { BlockOf } from "../define-block.ts";

import { accountingBlock } from "../accounting/manifest.ts";
import { bankingBlock } from "../banking/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { invoicesBlock } from "../invoices/manifest.ts";
import { taxBlock } from "../tax/manifest.ts";
import { createFinance } from "./finance.ts";

/** The blocks `finance` is made of, by block name. */
export const financeParts: {
  readonly accounting: typeof accountingBlock;
  readonly tax: typeof taxBlock;
  readonly banking: typeof bankingBlock;
  readonly invoices: typeof invoicesBlock;
} = {
  accounting: accountingBlock,
  tax: taxBlock,
  banking: bankingBlock,
  invoices: invoicesBlock,
};

export type FinanceParts = typeof financeParts;

/**
 * The `finance` composite (ADR 0177): the books, tax, bank reconciliation and
 * invoices. It installs its parts and sets their defaults; the parts stay
 * ordinary blocks in the config.
 */
export const financeBlock: BlockOf<"finance", typeof createFinance> =
  defineBlock({
    name: "finance",
    composes: financeParts,
    create: createFinance,
    category: "commerce",
  });
