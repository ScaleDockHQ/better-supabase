const FIRST_CODE = 1000;

/** The fields of a chart account the planner reads. */
export interface ChartAccount {
  readonly id: string;
  readonly code: string;
  readonly name: string;
  readonly type: string;
  readonly active: boolean;
  readonly currency?: string;
}

/** Map an account the chart has, or create one with this code and name. */
export type CashAccountPlan =
  | { readonly kind: "map"; readonly accountId: string }
  | { readonly kind: "create"; readonly code: string; readonly name: string };

/**
 * Where a new till's cash goes: an active, unused euro asset account with
 * "cash" in its name, or a new account on the next free code from 1000.
 */
export function planCashAccount(
  accounts: readonly ChartAccount[],
  usedAccountIds: ReadonlySet<string>,
  tillName: string,
): CashAccountPlan {
  const mapped = accounts.find(
    (account) =>
      account.active &&
      account.type === "asset" &&
      !usedAccountIds.has(account.id) &&
      (account.currency === undefined || account.currency === "EUR") &&
      /\bcash\b/i.test(account.name),
  );

  if (mapped) {
    return { kind: "map", accountId: mapped.id };
  }

  const codes = new Set(accounts.map((account) => account.code));
  let next = FIRST_CODE;

  while (codes.has(String(next))) {
    next += 1;
  }

  return { kind: "create", code: String(next), name: `Cash ${tillName}` };
}
