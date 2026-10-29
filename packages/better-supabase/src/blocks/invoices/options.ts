import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.invoices.options`. */
export type InvoicesSqlOptions = {
  readonly company?: string;
  readonly contact?: string;
  readonly prefix?: string;
  readonly creditPrefix?: string;
  readonly termsDays?: number;
  readonly extraColumns?: ExtraColumns;
  readonly lineExtraColumns?: ExtraColumns;
  /**
   * `"percent"` when your own line table keeps discount and tax rates as
   * percentages, such as `vat_rate numeric(5, 2)`: the block converts them from
   * and to basis points. Default `"bps"`.
   */
  readonly lineRates?: "bps" | "percent";
  /**
   * App columns of the charges table, such as a `not null` kind, which
   * `charge()` sets from `fields`.
   */
  readonly chargeExtraColumns?: ExtraColumns;
  /**
   * `"app"` when the app keeps the totals columns itself, such as with VAT per
   * rate: the block never recounts or writes them and reads what they hold.
   */
  readonly totals?: "block" | "app";
  readonly providerPaymentMethods?: readonly string[];
  /**
   * The column an invoice's number is unique on, per tenant and kind:
   * `"number"` (default), `"identifier"` for numbering that restarts each
   * period with the period in the identifier, or `false` when the app keeps
   * numbers unique itself.
   */
  readonly uniqueNumber?: "number" | "identifier" | false;
  /**
   * `false` leaves out the unique `(invoice, position)` index on your own line
   * table, so the app can renumber lines in one update. Default `true`.
   */
  readonly linePositionKey?: boolean;
};

export const invoicesSqlOptions: BlockOptionsSchema<InvoicesSqlOptions> =
  blockOptions<InvoicesSqlOptions>({
    company: option.string({ default: "company" }),
    contact: option.string({ default: "person" }),
    prefix: option.string({ default: "INV-" }),
    creditPrefix: option.string({ default: "CN-" }),
    termsDays: option.number({ default: 30 }),
    extraColumns: option.extraColumns(),
    lineExtraColumns: option.extraColumns(),
    lineRates: option.string<"bps" | "percent">({ default: "bps" }),
    chargeExtraColumns: option.extraColumns(),
    totals: option.string<"block" | "app">({ default: "block" }),
    providerPaymentMethods: option.strings({ default: ["stripe", "order"] }),
    uniqueNumber: option.unknown<"number" | "identifier" | false>(),
    linePositionKey: option.boolean({ default: true }),
  });
