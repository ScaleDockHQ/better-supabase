import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AccountingPeriod } from "../accounting/index.ts";
import type { BankTransaction } from "../banking/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { FinanceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";

/** What `finance.closePeriod` returns. */
export type PeriodClose =
  | { readonly closed: true; readonly period: AccountingPeriod }
  | { readonly closed: false; readonly blockers: readonly string[] };

/** What `finance.reconcile` returns. */
export interface ReconcileRun {
  /** The transactions matched to their best open invoice. */
  readonly matched: readonly BankTransaction[];
  /** The transactions with no invoice that scored `minScore`. */
  readonly unmatched: readonly string[];
  /** The transactions whose match failed, with the error message. */
  readonly failed: readonly {
    readonly transactionId: string;
    readonly message: string;
  }[];
}

/** The helpers `finance` adds over its parts. */
export interface Finance {
  /**
   * Closes the period when nothing blocks it. A blocked period is not an error:
   * the result lists the blockers (unreconciled bank lines, drafts) and changes
   * nothing. It is one database call and one transaction
   * (`close_accounting_period_if_clear`, ADR 1235); the TypeScript hooks of
   * `closeBlockers` and `closePeriod` do not fire, the hook of
   * `finance.closePeriod` does.
   */
  closePeriod(periodId: string): AsyncResult<PeriodClose>;
  /**
   * Matches an account's unmatched bank transactions to their best open invoice
   * with `banking.reconcile`: one database call and one transaction (ADR 1235)
   * that records the invoice payment of each transaction with a suggestion
   * scoring at least `minScore`. A transaction that fails to match is listed in
   * `failed` and the run goes on. The TypeScript hooks of the banking steps do
   * not fire; the hook of `finance.reconcile` does. Run `closePeriod`
   * afterwards.
   */
  reconcile(input: {
    accountId: string;
    minScore?: number | undefined;
    limit?: number | undefined;
  }): AsyncResult<ReconcileRun>;
}

/** What the `finance` creator receives. */
export type FinanceOptions = BlockContext &
  CompositeOptions<FinanceParts> & {
    /** \`before\` and \`after\` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Finance>>;
    /** Receives the errors \`after\` hooks throw. Default: \`console\`. */
    readonly logger?: Logger;
  };

/** Creates the `finance` helpers over the clients of its parts. */
export function createFinance(options: FinanceOptions): Finance {
  const { accounting, banking } = options.parts;

  const client: Finance = {
    closePeriod: (periodId) => accounting.closePeriodIfClear(periodId),
    reconcile: (input) => banking.reconcile(input),
  };

  return withBlockHooks(client, options.hooks, {
    block: "finance",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
