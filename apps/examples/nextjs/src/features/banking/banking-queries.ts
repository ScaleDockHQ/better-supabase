import "server-only";
import type {
  BankMatchReason,
  BankTransactionStatus,
} from "better-supabase/blocks/banking";
import type { MoneyJson } from "better-supabase/commerce";

import { moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

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

/** Unmatched transactions get a suggestion each; the rest show their status. */
const SUGGESTED = 20;

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

  return Promise.all(
    accounts.map(async (account) => {
      const [status, transactions] = await Promise.all([
        banking.reconciliation(account.id).orThrow(),
        banking.transactions(account.id, { limit: 100 }).orThrow(),
      ]);

      const open = transactions
        .filter((transaction) => transaction.status === "unmatched")
        .slice(0, SUGGESTED);

      const suggestions = new Map(
        await Promise.all(
          open.map(
            async (transaction) =>
              [
                transaction.id,
                (await banking.suggestMatches(transaction.id).orThrow()).find(
                  (suggestion) => suggestion.targetType === "invoice",
                ),
              ] as const,
          ),
        ),
      );

      return {
        id: account.id,
        name: account.name,
        iban: account.iban ?? null,
        statementBalance: status.statementBalance
          ? moneyToJson(status.statementBalance)
          : null,
        unmatchedCount: status.unmatchedCount,
        unmatchedTotal: moneyToJson(status.unmatchedTotal),
        difference: status.difference ? moneyToJson(status.difference) : null,
        reconciled: status.reconciled,
        transactions: transactions.map((transaction): BankTransactionRow => {
          const suggestion = suggestions.get(transaction.id);

          return {
            id: transaction.id,
            bookedOn: transaction.bookedOn.toString(),
            amount: moneyToJson(transaction.amount),
            counterparty: transaction.counterpartyName ?? null,
            remittance: transaction.remittance ?? null,
            status: transaction.status,
            suggestion: suggestion
              ? {
                  targetId: suggestion.targetId,
                  label: suggestion.label,
                  balance: moneyToJson(suggestion.balance),
                  reasons: suggestion.reasons,
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
