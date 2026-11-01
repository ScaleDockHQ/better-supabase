import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.deals.options`. */
export type DealsSqlOptions = {
  readonly company?: string;
  readonly contact?: string;
  readonly motions?: unknown;
  readonly priorities?: unknown;
  readonly prefix?: string;
  readonly readAll?: boolean;
  readonly extraColumns?: ExtraColumns;
  readonly lineExtraColumns?: ExtraColumns;
  /**
   * `"percent"` when your own line table keeps discount and tax rates as
   * percentages, such as `vat_rate numeric(5, 2)`: the block converts them from
   * and to basis points. Default `"bps"`.
   */
  readonly lineRates?: "bps" | "percent";
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
    extraColumns: option.extraColumns(),
    lineExtraColumns: option.extraColumns(),
    lineRates: option.string<"bps" | "percent">({ default: "bps" }),
    searchColumn: option.boolean({ default: false }),
  });
