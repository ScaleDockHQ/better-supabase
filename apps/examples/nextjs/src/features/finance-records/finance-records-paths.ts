import type { AppHref } from "@/i18n/navigation";
import type { FinanceEntityKey } from "@/lib/finance-list";

import { toAppHref } from "@/i18n/navigation";

/**
 * Where each entity's overview lives. A record's page is the overview path
 * and the id, so a row link and a back link never drift apart.
 */
export const FINANCE_PATHS = {
  invoices: "/finance/invoices",
  payables: "/finance/payables",
  expenses: "/finance/expenses",
  ledger: "/finance/ledger",
  journal: "/finance/accounting",
  "billable-time": "/finance/billable-time",
  recurring: "/finance/recurring",
  tax: "/finance/tax",
  periods: "/finance/periods",
  payroll: "/payroll",
  "legal-entities": "/legal-entities",
  funding: "/funding",
  "bank-accounts": "/banking/accounts",
  "bank-transactions": "/banking/transactions",
} as const satisfies Readonly<Record<FinanceEntityKey, string>>;

/** The page of one record. */
export function financeRecordPath(
  entity: FinanceEntityKey,
  id: string,
): AppHref {
  return toAppHref(`${FINANCE_PATHS[entity]}/${id}`);
}
