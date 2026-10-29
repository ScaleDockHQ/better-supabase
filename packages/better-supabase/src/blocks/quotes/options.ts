import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.quotes.options`. */
export type QuotesSqlOptions = {
  readonly company?: string;
  readonly contact?: string;
  readonly prefix?: string;
  readonly validDays?: number;
  readonly extraColumns?: ExtraColumns;
  readonly lineExtraColumns?: ExtraColumns;
  /**
   * `"percent"` when your own line table keeps discount and tax rates as
   * percentages, such as `vat_rate numeric(5, 2)`: the block converts them from
   * and to basis points. Default `"bps"`.
   */
  readonly lineRates?: "bps" | "percent";
  /**
   * Staff edit a sent quote while the customer keeps seeing its last published
   * version; sending it again publishes the next revision on the same link, and
   * an acceptance restores the version the customer saw.
   */
  readonly workingCopy?: boolean;
  /**
   * Each published version keeps its lines as rows with their own ids in
   * `quote_version_lines`, so other records can point at them.
   */
  readonly versionLines?: boolean;
};

export const quotesSqlOptions: BlockOptionsSchema<QuotesSqlOptions> =
  blockOptions<QuotesSqlOptions>({
    company: option.string({ default: "company" }),
    contact: option.string({ default: "person" }),
    prefix: option.string({ default: "Q-" }),
    validDays: option.number({ default: 30 }),
    extraColumns: option.extraColumns(),
    lineExtraColumns: option.extraColumns(),
    lineRates: option.string<"bps" | "percent">({ default: "bps" }),
    workingCopy: option.boolean({ default: false }),
    versionLines: option.boolean({ default: false }),
  });
