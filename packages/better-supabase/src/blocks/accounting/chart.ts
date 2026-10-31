import type { Err } from "../../core/result.ts";
import type {
  AccountRole,
  Accounting,
  AccountingAccount,
  AccountingAccountInput,
} from "./accounting.ts";

import { AsyncResult, err, ok } from "../../core/result.ts";

/** One account of a chart a format parsed. */
export interface ChartAccount extends Omit<
  AccountingAccountInput,
  "parentId" | "accountId"
> {
  /** The code of the parent account, which must be in the same chart. */
  readonly parentCode?: string;
  /** The roles this account plays, such as `receivable`. */
  readonly roles?: readonly AccountRole[];
}

/**
 * Reads a chart of accounts from a reference scheme's file: the Dutch RGS, a
 * national standard chart or an export from another ledger. Versioned: a
 * breaking change ships a new `apiVersion`. better-supabase bundles none; a
 * scheme package implements its own file layout.
 */
export interface AccountingChartFormat {
  readonly apiVersion: 1;
  /** The scheme's name, such as `rgs-3.5`. */
  readonly key: string;
  parse(
    body: string,
  ): readonly ChartAccount[] | Promise<readonly ChartAccount[]>;
}

/** Checks the format's `apiVersion` before parsing with it. */
export function chartFormatOf(
  format: AccountingChartFormat,
): AccountingChartFormat {
  const version: unknown = format.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `accounting chart format "${format.key}" targets chart format API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the format for API 1.`,
    );
  }

  return format;
}

export interface ChartImport {
  readonly format: string;
  /** The saved accounts, parents before their children. */
  readonly accounts: readonly AccountingAccount[];
  /** The roles that were mapped, by role. */
  readonly roles: Readonly<Partial<Record<AccountRole, string>>>;
}

const invalid = (message: string): Err =>
  err({
    kind: "invalid_input",
    message,
    status: 422,
    hint: "ACCOUNTING_CHART_INVALID",
  });

/** The accounts ordered so every parent comes before its children. */
function inParentOrder(
  chart: readonly ChartAccount[],
): readonly ChartAccount[] | string {
  const codes = new Set<string>();

  for (const account of chart) {
    if (codes.has(account.code)) {
      return `the chart lists account ${account.code} twice`;
    }

    codes.add(account.code);
  }

  const placed = new Set<string>();
  const ordered: ChartAccount[] = [];
  let pending = [...chart];

  while (pending.length > 0) {
    const ready = pending.filter(
      (account) =>
        account.parentCode === undefined || placed.has(account.parentCode),
    );

    if (ready.length === 0) {
      return `accounts ${pending.map((account) => account.code).join(", ")} name a parent that is not in the chart or form a parent cycle`;
    }

    for (const account of ready) {
      placed.add(account.code);
      ordered.push(account);
    }

    pending = pending.filter((account) => !placed.has(account.code));
  }

  return ordered;
}

/**
 * Parses `body` with `format` and saves the chart's accounts, parents first,
 * then maps the roles they name. Saving a code again updates that account, so
 * importing the same chart twice changes nothing. Nothing is saved when the
 * file lists a code twice, names a parent that isn't in it or maps one role to
 * two accounts (`ACCOUNTING_CHART_INVALID`). A format that throws comes back as
 * an error result.
 */
export function importChart(
  accounting: Pick<Accounting, "saveAccount" | "setAccountRole">,
  organizationId: string,
  format: AccountingChartFormat,
  body: string,
): AsyncResult<ChartImport> {
  return AsyncResult.from(async () => {
    const checked = chartFormatOf(format);
    const ordered = inParentOrder(await checked.parse(body));

    if (typeof ordered === "string") {
      return invalid(ordered);
    }

    const holders = new Map<AccountRole, string>();

    for (const account of ordered) {
      for (const role of account.roles ?? []) {
        const holder = holders.get(role);

        if (holder !== undefined && holder !== account.code) {
          return invalid(
            `role ${role} is on accounts ${holder} and ${account.code}`,
          );
        }

        holders.set(role, account.code);
      }
    }

    const saved = new Map<string, AccountingAccount>();
    const accounts: AccountingAccount[] = [];
    const assignments: (readonly [AccountRole, string])[] = [];

    for (const account of ordered) {
      const { parentCode, roles, ...input } = account;

      const parent =
        parentCode === undefined ? undefined : saved.get(parentCode);

      const result = await accounting.saveAccount(organizationId, {
        ...input,
        ...(parent ? { parentId: parent.id } : {}),
      });

      if (!result.ok) {
        return result;
      }

      saved.set(account.code, result.data);
      accounts.push(result.data);

      for (const role of roles ?? []) {
        assignments.push([role, result.data.id]);
      }
    }

    let mapped: Readonly<Partial<Record<AccountRole, string>>> = {};

    for (const [role, accountId] of assignments) {
      const result = await accounting.setAccountRole(
        organizationId,
        role,
        accountId,
      );

      if (!result.ok) {
        return result;
      }

      mapped = result.data;
    }

    return ok({ format: checked.key, accounts, roles: mapped });
  });
}
