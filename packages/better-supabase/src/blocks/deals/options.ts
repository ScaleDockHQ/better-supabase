import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.deals.options`. */
export type DealsSqlOptions = {
  readonly company?: string;
  readonly contact?: string;
  readonly motions?: unknown;
  readonly priorities?: unknown;
  readonly prefix?: string;
  readonly readAll?: boolean;
  /**
   * `"percent"` when your own line table keeps discount and tax rates as
   * percentages, such as `vat_rate numeric(5, 2)`: the block converts them from
   * and to basis points. Default `"bps"`.
   */
  readonly lineRates?: "bps" | "percent";
  /**
   * How the discount column of your line table stores its rate, when it differs
   * from `lineRates`: `"bps"` for basis points next to percent tax rates.
   * Default: `lineRates`.
   */
  readonly lineDiscountRates?: "bps" | "percent";
  /**
   * Adds a stored `search_tsv` column and a GIN index to deals, so queries
   * match with `search_tsv @@ websearch_to_tsquery('simple', ...)`. Default
   * `false`.
   */
  readonly searchColumn?: boolean;
};

export const dealsSqlOptions: BlockOptionsSchema<DealsSqlOptions> =
  blockOptions<DealsSqlOptions>({
    company: option.string({ default: "company" }),
    contact: option.string({ default: "person" }),
    motions: option.unknown(),
    priorities: option.unknown(),
    prefix: option.string({ default: "DEAL-" }),
    readAll: option.boolean({ default: true }),
    lineRates: option.string<"bps" | "percent">({ default: "bps" }),
    lineDiscountRates: option.string<"bps" | "percent">(),
    searchColumn: option.boolean({ default: false }),
  });
