import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.accounting.options`. */
export type AccountingSqlOptions = {
  /** Extra columns on `accounting_entries`, written through `fields`. */
  readonly extraColumns?: ExtraColumns;
  /**
   * The chart `setup_accounting` creates for a new organization: `generic`
   * (default), a small chart with every account role mapped, or `none` for a
   * chart the app imports itself.
   */
  readonly chart?: "generic" | "none";
  /**
   * The functional currency `setup_accounting` uses when the call names none.
   * Default `EUR`.
   */
  readonly functionalCurrency?: string;
  /**
   * The month (1 to 12) a fiscal year starts in, when the call names none.
   * Default 1.
   */
  readonly fiscalYearStartMonth?: number;
  /** The account subtypes `save_accounting_account` accepts. */
  readonly subtypes?: readonly string[];
};

export const accountingSqlOptions: BlockOptionsSchema<AccountingSqlOptions> =
  blockOptions<AccountingSqlOptions>({
    extraColumns: option.extraColumns(),
    chart: option.string<"generic" | "none">({ default: "generic" }),
    functionalCurrency: option.string({ default: "EUR" }),
    fiscalYearStartMonth: option.number({ default: 1 }),
    subtypes: option.strings(),
  });
