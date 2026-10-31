import type { Money } from "../../commerce/money.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import { moneyOf } from "../money-codec.ts";
import { compact } from "../sales-shared.ts";
import { optionalText, recordOf, recordsOf, textOf } from "../shared.ts";

/** A source `invoiceFromSources` bills. */
export type InvoiceSource =
  | {
      readonly type: "order";
      readonly id: string;
      /** Invoice only these lines, each up to a whole quantity. */
      readonly lines?: readonly {
        readonly id: string;
        readonly quantity: number;
      }[];
    }
  | { readonly type: "shipment"; readonly id: string }
  | {
      readonly type: "time";
      readonly scope?: {
        readonly subject?: { readonly type: string; readonly id: string };
        readonly userId?: string;
        readonly starts?: string;
        readonly ends?: string;
        readonly entryIds?: readonly string[];
        readonly groupBy?: "subject" | "member" | "entry";
      };
    };

/** A draft invoice `invoiceFromSources` made. */
export interface SourceInvoice {
  readonly id: string;
  readonly currency: string;
  readonly total: Money;
}

/** What one `invoiceFromSources` call wrote. */
export interface InvoicedSources {
  /** One draft invoice per billing party and currency. */
  readonly invoices: readonly SourceInvoice[];
  /** Orders and shipments that were already fully invoiced. */
  readonly skipped: readonly { readonly type: string; readonly id: string }[];
}

/** A source with something left to invoice. */
export interface ReadySource {
  readonly type: "order" | "shipment" | "time";
  readonly id?: string;
  readonly reference?: string;
  readonly currency: string;
  readonly lines: number;
  /** Delivered quantity (hours for time) not yet invoiced. */
  readonly quantity: string;
  /** The amount before tax. */
  readonly amount: Money;
}

/** Collective invoicing: one invoice from several delivered sources. */
export interface InvoiceSources {
  /**
   * Bills delivered orders, delivered shipments and unbilled time for one
   * party. The sources split into one draft invoice per billing party and
   * currency. A source is invoiced once: a repeat call returns it in `skipped`
   * and writes nothing. Not available in import mode.
   */
  invoiceFromSources(
    organizationId: string,
    party: { readonly type: string; readonly id: string },
    sources: readonly InvoiceSource[],
    options?: {
      readonly title?: string;
      /**
       * Passed to `create` (`termsDays`, `note`, `legalEntityId`, extra
       * columns).
       */
      readonly attrs?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResult<InvoicedSources>;
  /** The sources that can be invoiced now, for one party or every party. */
  sourcesReadyToInvoice(
    organizationId: string,
    party?: { readonly type: string; readonly id: string },
  ): AsyncResult<readonly ReadySource[]>;
}

function sourceType(value: unknown): ReadySource["type"] {
  const text = textOf(value);

  if (text === "order" || text === "shipment" || text === "time") {
    return text;
  }

  throw new TypeError(`unknown source type ${text}`);
}

/** The collective invoicing methods of the invoices client. */
export function invoiceSources(call: BlockCall): InvoiceSources {
  return {
    invoiceFromSources: (organizationId, party, sources, options = {}) =>
      call(
        "invoice_from_sources",
        {
          tenant: organizationId,
          party,
          source_refs: sources,
          options: compact({ title: options.title, attrs: options.attrs }),
        },
        (value) => {
          const row = recordOf(value, "invoice_from_sources");

          return {
            invoices: recordsOf(row["invoices"], "source invoices").map(
              (each) => {
                const currency = textOf(each["currency"]);

                return {
                  id: textOf(each["id"]),
                  currency,
                  total: moneyOf(each["total"], currency, "invoice total"),
                };
              },
            ),
            skipped: recordsOf(row["skipped"], "skipped sources").map(
              (each) => ({
                type: textOf(each["type"]),
                id: textOf(each["id"]),
              }),
            ),
          };
        },
      ),
    sourcesReadyToInvoice: (organizationId, party) =>
      call(
        "sources_ready_to_invoice",
        { tenant: organizationId, party: party ?? null },
        (value) =>
          recordsOf(value, "sources ready to invoice").map((each) => {
            const currency = textOf(each["currency"]);
            const id = optionalText(each["id"]);
            const reference = optionalText(each["reference"]);

            return {
              type: sourceType(each["type"]),
              ...(id === undefined ? {} : { id }),
              ...(reference === undefined ? {} : { reference }),
              currency,
              lines: Number(each["lines"]),
              quantity: textOf(each["quantity"]),
              amount: moneyOf(each["amount"], currency, "source amount"),
            };
          }),
      ),
  };
}
