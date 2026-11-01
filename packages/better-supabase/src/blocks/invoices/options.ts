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
  readonly paymentsAfterWriteOff?: boolean;
  /**
   * `true` also sends the `invoice.totals_corrected` event when
   * `recompute_invoice_totals` corrects an invoice. The correction is always
   * audited, and by default it sends no event. Default `false`.
   */
  readonly correctionEvents?: boolean;
  /**
   * The kind column's value that marks a deposit invoice, one of the values
   * `values.invoices.kind.invoice` maps to. `fromQuote` writes it on a deposit
   * invoice and finds the deposits to deduct by it and the quote link.
   */
  readonly depositKind?: string;
  readonly depositLine?: {
    readonly description?: string;
    readonly fields?: Readonly<Record<string, unknown>>;
  };
  readonly quoteLineValues?: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
  /** The number prefix of a purchase bill. Default `BILL-`. */
  readonly purchasePrefix?: string;
  /** The number prefix of a purchase credit note. Default `BCN-`. */
  readonly purchaseCreditPrefix?: string;
  /**
   * The price difference a three-way match accepts per line: `bps` of the
   * expected amount or `amount` minor units, whichever is larger. Default `{
   * bps: 100, amount: 500 }`.
   */
  readonly matchTolerance?: { readonly bps?: number; readonly amount?: number };
  /**
   * Catalog variant lines without a `discountBps` or `unitAmount` take the
   * discount matrix's rule for the customer and quantity: its discount and its
   * fixed price (catalog `resolve_line_discount`). Needs the catalog block.
   * Default `false`, so lines price as before.
   */
  readonly discountMatrix?: boolean;
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
    paymentsAfterWriteOff: option.boolean({ default: false }),
    correctionEvents: option.boolean({ default: false }),
    depositKind: option.string(),
    depositLine:
      option.unknown<NonNullable<InvoicesSqlOptions["depositLine"]>>(),
    quoteLineValues:
      option.unknown<NonNullable<InvoicesSqlOptions["quoteLineValues"]>>(),
    purchasePrefix: option.string({ default: "BILL-" }),
    purchaseCreditPrefix: option.string({ default: "BCN-" }),
    matchTolerance:
      option.unknown<NonNullable<InvoicesSqlOptions["matchTolerance"]>>(),
    discountMatrix: option.boolean({ default: false }),
  });
