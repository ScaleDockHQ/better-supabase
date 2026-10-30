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
  /**
   * App columns of the version lines table. On publish, each one takes the
   * value of the line column of the same name (`lineExtraColumns`), so checks
   * and references on the version lines hold.
   */
  readonly versionLineExtraColumns?: ExtraColumns;
  /**
   * `"app"` when the app keeps the totals columns itself, such as with fixed
   * line discounts or a VAT regime: the block never recounts or writes them,
   * reads what they hold, and refuses a change to them once a quote is
   * answered, expired or withdrawn.
   */
  readonly totals?: "block" | "app";
  /**
   * `send` and `publish` also take a rejected, withdrawn or expired quote and
   * send it again in one call, without a draft step. With `workingCopy`, such a
   * quote can be edited before it is sent again.
   */
  readonly resend?: boolean;
  /**
   * `false` sends no `quote.decided` notification to the owner when a quote is
   * answered, so the app can send its own from the `quote.*` events. Default
   * `true`.
   */
  readonly notifications?: boolean;
  /**
   * Sending a quote holds stock for its tracked catalog lines through the
   * inventory block, keeping what isn't available on backorder. The holds end
   * when the quote goes back to draft, is withdrawn, expires or is rejected,
   * and when an order is made from it. Needs the inventory block.
   */
  readonly holds?: boolean;
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
    versionLineExtraColumns: option.extraColumns(),
    totals: option.string<"block" | "app">({ default: "block" }),
    resend: option.boolean({ default: false }),
    notifications: option.boolean({ default: true }),
    holds: option.boolean({ default: false }),
  });
