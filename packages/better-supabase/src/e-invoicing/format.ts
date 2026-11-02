import type { Invoice } from "../blocks/invoices/invoices.ts";
import type { EInvoiceContext, EInvoiceFormat } from "./channel.ts";
import type { EInvoiceParty } from "./party.ts";
import type { UblOptions } from "./ubl.ts";

import { toUbl } from "./ubl.ts";

/** What `peppolBis3Format` asks the app for. */
export interface PeppolBis3FormatOptions {
  /**
   * The seller and the buyer of the invoice, with their Peppol participant ids.
   * The invoices block's `eInvoiceParties` returns them.
   */
  readonly parties: (
    invoice: Invoice,
    context: EInvoiceContext,
  ) =>
    | { readonly seller: EInvoiceParty; readonly buyer: EInvoiceParty }
    | Promise<{
        readonly seller: EInvoiceParty;
        readonly buyer: EInvoiceParty;
      }>;
  /** The rest of the `toUbl` options, such as `payment` or `orderReference`. */
  readonly options?: (
    invoice: Invoice,
    context: EInvoiceContext,
  ) => Omit<UblOptions, "seller" | "buyer">;
}

/** The format key of `peppolBis3Format`. */
export const PEPPOL_BIS_3_FORMAT = "peppol-bis-3";

/** Renders an issued invoice or credit note as Peppol BIS Billing 3.0 UBL. */
export function peppolBis3Format(
  config: PeppolBis3FormatOptions,
): EInvoiceFormat {
  return {
    apiVersion: 1,
    key: PEPPOL_BIS_3_FORMAT,
    async render(invoice, context) {
      const parties = await config.parties(invoice, context);

      return toUbl(invoice, {
        ...config.options?.(invoice, context),
        ...parties,
      });
    },
  };
}
