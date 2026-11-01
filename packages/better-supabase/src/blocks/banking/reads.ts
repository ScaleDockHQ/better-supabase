import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BankReconciliationBoard } from "../../sql/modules/banking-reads.ts";

import { decodeRead } from "../../core/read-type.ts";
import { BANK_RECONCILIATION_BOARD_RESULT } from "../../sql/modules/banking-reads.ts";

export type {
  BankBoardLine,
  BankBoardStatus,
  BankBoardSuggestion,
  BankReconciliationBoard,
} from "../../sql/modules/banking-reads.ts";

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
}

export function bankReads(call: BlockCall): BankReads {
  return {
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
