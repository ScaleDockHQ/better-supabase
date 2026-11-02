import "server-only";
import type { MoneyJson } from "better-supabase/commerce";

import { money, moneyToJson } from "better-supabase/commerce";
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

/** One account's row in the trial balance, serializable. */
export interface TrialBalanceRow {
  readonly accountId: string;
  readonly code: string;
  readonly name: string;
  readonly debit: MoneyJson;
  readonly credit: MoneyJson;
  readonly closing: MoneyJson;
}

/** The books as the finance page shows them; `null` before setup. */
export interface Books {
  readonly asOf: string;
  readonly accounts: readonly TrialBalanceRow[];
  readonly totals: { readonly debit: MoneyJson; readonly credit: MoneyJson };
  readonly totalAssets: MoneyJson;
  readonly liabilitiesAndEquity: MoneyJson;
  readonly netIncome: MoneyJson;
  /** Sales tax less purchase tax this year: owed when positive. */
  readonly netTax: MoneyJson;
  readonly balanced: boolean;
}

async function loadBooks(): Promise<Books | "not-set-up" | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { accounting } = db;
  const settings = await accounting.settings(tenant).orThrow();

  if (!settings) {
    return "not-set-up";
  }

  const today = Temporal.Now.plainDateISO("UTC");

  const yearStart = today.with({
    month: settings.fiscalYearStartMonth,
    day: 1,
  });

  const since =
    Temporal.PlainDate.compare(yearStart, today) > 0
      ? yearStart.subtract({ years: 1 })
      : yearStart;

  const [trial, sheet, pnl, tax] = await Promise.all([
    accounting.trialBalance({ organizationId: tenant, until: today }).orThrow(),
    accounting.balanceSheet({ organizationId: tenant, asOf: today }).orThrow(),
    accounting
      .profitAndLoss({ organizationId: tenant, since, until: today })
      .orThrow(),
    accounting
      .taxReport({ organizationId: tenant, since, until: today })
      .orThrow(),
  ]);

  const json = (amount: bigint): MoneyJson =>
    moneyToJson(money(amount, settings.functionalCurrency));

  return {
    asOf: today.toString(),
    accounts: trial.accounts.map((row) => ({
      accountId: row.accountId,
      code: row.code,
      name: row.name,
      debit: json(row.debit),
      credit: json(row.credit),
      closing: json(row.closing),
    })),
    totals: {
      debit: json(trial.totals.debit),
      credit: json(trial.totals.credit),
    },
    totalAssets: json(sheet.totalAssets),
    liabilitiesAndEquity: json(sheet.totalLiabilities + sheet.totalEquity),
    netIncome: json(pnl.netIncome),
    netTax: json(tax.netTax),
    balanced: sheet.balanced,
  };
}

/** The trial balance, balance sheet totals and this year's net income and tax. */
export function getBooks(): Promise<Loaded<Books | "not-set-up">> {
  return settle(loadBooks);
}
