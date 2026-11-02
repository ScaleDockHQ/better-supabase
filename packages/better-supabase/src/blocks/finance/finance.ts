import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AccountingPeriod } from "../accounting/index.ts";
import type { BankTransaction } from "../banking/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { FinanceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

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
   * nothing.
   */
  closePeriod(periodId: string): AsyncResult<PeriodClose>;
  /**
   * Matches an account's unmatched bank transactions to their best open
   * invoice: reads `banking.reviewQueue`, then calls `banking.acceptBestMatch`
   * for each transaction that has a suggestion scoring at least `minScore`
   * (default 1), which records the invoice payment. A transaction that fails to
   * match is listed in `failed` and the run goes on, so only a failed queue
   * read returns an error. Run `closePeriod` afterwards.
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
    closePeriod: (periodId) =>
      accounting
        .closeBlockers(periodId)
        .andThen<PeriodClose>((blockers) =>
          blockers.length > 0
            ? Async.ok({ closed: false, blockers })
            : accounting
                .closePeriod(periodId)
                .map((period) => ({ closed: true, period })),
        ),
    reconcile: ({ accountId, minScore, limit }) =>
      Async.from<ReconcileRun>(async () => {
        const queue = await banking.reviewQueue({
          accountId,
          ...(limit === undefined ? {} : { limit }),
        });

        if (!queue.ok) {
          return queue;
        }

        const matched: BankTransaction[] = [];
        const unmatched: string[] = [];
        const failed: { transactionId: string; message: string }[] = [];

        for (const { transaction, suggestion } of queue.data) {
          if (
            suggestion === undefined ||
            (minScore !== undefined && suggestion.score < minScore)
          ) {
            unmatched.push(transaction.id);
            continue;
          }

          // One match at a time: each records a payment against the invoice.
          const accepted = await banking.acceptBestMatch({
            transactionId: transaction.id,
            ...(minScore === undefined ? {} : { minScore }),
          });

          if (accepted.ok) {
            matched.push(accepted.data);
          } else {
            failed.push({
              transactionId: transaction.id,
              message: accepted.error.message,
            });
          }
        }

        return ok({ matched, unmatched, failed });
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "finance",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
