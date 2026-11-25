import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BankReconciliationBoard } from "../../sql/modules/banking-reads.ts";
import type { BankTransaction } from "./banking.ts";

import { recordOf } from "../../core/block-helpers.ts";
import { decodeRead } from "../../core/read-type.ts";
import { BANK_RECONCILIATION_BOARD_RESULT } from "../../sql/modules/banking-reads.ts";

export type {
  BankBoardLine,
  BankBoardStatus,
  BankBoardSuggestion,
  BankReconciliationBoard,
} from "../../sql/modules/banking-reads.ts";

/** What `banking.reconcile` returns. */
export interface BankReconcileRun {
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

/** The composed reads of the banking client. */
export interface BankReads {
  /**
   * An account's reconciliation page in one call: its status, its latest
   * `limit` transactions (default 50) and the best open invoice for each
   * unmatched one in `suggestions`. `reconciliation` and `reviewQueue` give the
   * same pieces one call at a time.
   */
  reconciliationBoard(input: {
    accountId: string;
    limit?: number | undefined;
  }): AsyncResult<BankReconciliationBoard>;
  /**
   * Matches an account's unmatched transactions (newest first, `limit` default 20)
   * to their best open invoice in one database call and one transaction (ADR
   * 1235). A transaction without a suggestion scoring `minScore` is listed in
   * `unmatched`, and one whose match fails in `failed`; the rest still match.
   * The TypeScript hooks of `reviewQueue` and `acceptBestMatch` do not fire,
   * the hook of `reconcile` does.
   */
  reconcile(input: {
    accountId: string;
    minScore?: number | undefined;
    limit?: number | undefined;
  }): AsyncResult<BankReconcileRun>;
}

export function bankReads(
  call: BlockCall,
  transactionOf: (value: unknown) => BankTransaction,
): BankReads {
  return {
    reconcile: ({ accountId, minScore, limit }) =>
      call(
        "reconcile_bank_account",
        {
          account_id: accountId,
          min_score: minScore ?? null,
          line_limit: limit ?? 20,
        },
        (value) => {
          const row = recordOf(value, "reconcile_bank_account");

          const list = (key: string): readonly unknown[] => {
            const items = row[key];

            return Array.isArray(items) ? items : [];
          };

          return {
            matched: list("matched").map(transactionOf),
            unmatched: list("unmatched").map(String),
            failed: list("failed").map((item) => {
              const failure = recordOf(item, "reconcile_bank_account");

              return {
                transactionId: String(failure["transactionId"]),
                message: String(failure["message"]),
              };
            }),
          };
        },
      ),
    reconciliationBoard: ({ accountId, limit }) =>
      call(
        "bank_reconciliation_board",
        {
          account_id: accountId,
          ...(limit === undefined ? {} : { line_limit: limit }),
        },
        (value) =>
          decodeRead<BankReconciliationBoard>(
            BANK_RECONCILIATION_BOARD_RESULT,
            value,
            "bank_reconciliation_board",
          ),
      ),
  };
}
