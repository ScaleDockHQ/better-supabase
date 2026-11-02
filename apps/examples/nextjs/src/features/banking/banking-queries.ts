import "server-only";
import type {
  BankMatchReason,
  BankTransactionStatus,
} from "better-supabase/blocks/banking";
import type { MoneyJson } from "better-supabase/commerce";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** The best open invoice a transaction may pay, serializable. */
export interface BankSuggestionRow {
  readonly targetId: string;
  readonly label: string;
  readonly balance: MoneyJson;
  readonly reasons: readonly BankMatchReason[];
}

/** A bank transaction as the reconciliation grid shows it, serializable. */
export interface BankTransactionRow {
  readonly id: string;
  readonly bookedOn: string;
  readonly amount: MoneyJson;
  readonly counterparty: string | null;
  readonly remittance: string | null;
  readonly status: BankTransactionStatus;
  /** Set for unmatched transactions with a candidate invoice. */
  readonly suggestion: BankSuggestionRow | null;
}

/** One bank account with its reconciliation and recent transactions. */
export interface BankAccountReconciliation {
  readonly id: string;
  readonly name: string;
  readonly iban: string | null;
  readonly statementBalance: MoneyJson | null;
  readonly unmatchedCount: number;
  readonly unmatchedTotal: MoneyJson;
  readonly difference: MoneyJson | null;
  readonly reconciled: boolean;
  readonly transactions: readonly BankTransactionRow[];
}

/** The latest transactions a grid shows per account. */
const LINES = 100;

const TransactionStatus = v.picklist(["unmatched", "matched", "ignored"]);

const MatchReasons = v.array(
  v.picklist(["reference", "remittance", "amount", "counterparty"]),
);

/** The money of a board row: minor-unit text and its currency. */
function amountOf(amount: string, currency: string): MoneyJson {
  return { amount, currency };
}

async function loadReconciliation(): Promise<
  readonly BankAccountReconciliation[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const { banking } = db;
  const accounts = await banking.accounts().orThrow();

  // One `reconciliationBoard` call per account replaces the status, the
  // transactions and the review queue.
  return Promise.all(
    accounts.map(async (account) => {
      const { status, lines, suggestions } = await banking
        .reconciliationBoard({ accountId: account.id, limit: LINES })
        .orThrow();

      const suggested = new Map(
        suggestions.map((item) => [item.transactionId, item] as const),
      );

      return {
        id: account.id,
        name: account.name,
        iban: account.iban ?? null,
        statementBalance: status.statementBalance
          ? amountOf(status.statementBalance, status.currency)
          : null,
        unmatchedCount: status.unmatchedCount,
        unmatchedTotal: amountOf(status.unmatchedTotal, status.currency),
        difference: status.difference
          ? amountOf(status.difference, status.currency)
          : null,
        reconciled: status.reconciled,
        transactions: lines.map((line): BankTransactionRow => {
          const suggestion = suggested.get(line.id);

          return {
            id: line.id,
            bookedOn: line.bookedOn,
            amount: amountOf(line.amount, line.currency),
            counterparty: line.counterpartyName,
            remittance: line.remittance,
            status: v.parse(TransactionStatus, line.status),
            suggestion: suggestion
              ? {
                  targetId: suggestion.targetId,
                  label: suggestion.label,
                  balance: amountOf(suggestion.balance, suggestion.currency),
                  reasons: v.parse(MatchReasons, suggestion.reasons),
                }
              : null,
          };
        }),
      };
    }),
  );
}

/** Each bank account with its reconciliation and its latest transactions. */
export function getBankReconciliation(): Promise<
  Loaded<readonly BankAccountReconciliation[]>
> {
  return settle(loadReconciliation);
}
