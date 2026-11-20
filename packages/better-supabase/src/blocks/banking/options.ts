import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.banking.options`. */
export type BankingSqlOptions = {
  /**
   * `"organization"` keeps one primary account per organization; making an
   * account primary clears the flag on all the others. Default `"currency"`,
   * one per organization and currency.
   */
  readonly primary?: "currency" | "organization";
  /**
   * Lets an account have no currency. Each transaction imported into one names
   * its own, and a payment batch still needs an account with a currency.
   * Default `false`.
   */
  readonly optionalCurrency?: boolean;
};

export const bankingSqlOptions: BlockOptionsSchema<BankingSqlOptions> =
  blockOptions<BankingSqlOptions>({
    primary: option.string<"currency" | "organization">({
      default: "currency",
    }),
    optionalCurrency: option.boolean({ default: false }),
  });
