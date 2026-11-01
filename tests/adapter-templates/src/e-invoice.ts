import type {
  EInvoiceChannel,
  EInvoiceFormat,
} from "better-supabase/e-invoicing";

import type { HttpOptions } from "./http.ts";

import { record, requestJson, text } from "./http.ts";

const escapeXml = (value: string): string =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

/**
 * An `EInvoiceFormat` for one network's layout (ADR 0180). It reads the issued
 * invoice and returns the document; a real format maps the lines, the tax
 * breakdown and the parties. `render` throws for a draft, which has no number.
 */
export const exampleEInvoiceFormat: EInvoiceFormat = {
  apiVersion: 1,
  key: "example-ubl",
  render(invoice) {
    if (invoice.identifier === undefined || invoice.issuedOn === undefined) {
      throw new TypeError("only an issued invoice can be sent as an e-invoice");
    }

    const type = invoice.kind === "credit_note" ? "CreditNote" : "Invoice";

    return {
      type,
      id: invoice.identifier,
      xml: [
        `<${type}>`,
        `  <ID>${escapeXml(invoice.identifier)}</ID>`,
        `  <IssueDate>${invoice.issuedOn.toString()}</IssueDate>`,
        `  <DocumentCurrencyCode>${escapeXml(invoice.currency)}</DocumentCurrencyCode>`,
        `</${type}>`,
      ].join("\n"),
    };
  },
};

/**
 * An `EInvoiceChannel` over an access point's API (ADR 0180). `send` returns
 * the access point's message id, which the block keeps in
 * `invoice_e_deliveries`; `status` answers later what the network says about
 * it.
 */
export function createEInvoiceChannel(options: HttpOptions): EInvoiceChannel {
  return {
    apiVersion: 1,
    key: "example-access-point",
    async send(document, context) {
      const body = await requestJson(options, "/documents", {
        method: "POST",
        body: {
          type: document.type,
          id: document.id,
          xml: document.xml,
          recipient: {
            scheme: context.recipient.scheme,
            id: context.recipient.id,
          },
        },
        // A retry of the same invoice must not send a second document.
        headers: { "idempotency-key": context.invoice.id },
        ...(context.signal === undefined ? {} : { signal: context.signal }),
      });

      if (!body.ok) {
        throw new Error(body.error.message);
      }

      return { messageId: text(record(body.data, "document").id, "id") };
    },
    async status(messageId, context) {
      const body = await requestJson(
        options,
        `/documents/${encodeURIComponent(messageId)}`,
        context.signal === undefined ? {} : { signal: context.signal },
      );

      if (!body.ok) {
        throw new Error(body.error.message);
      }

      const document = record(body.data, "document");
      const state = text(document.state, "state");

      if (
        state !== "pending" &&
        state !== "delivered" &&
        state !== "rejected"
      ) {
        throw new TypeError(`unknown state "${state}"`);
      }

      return {
        state,
        ...(typeof document.reason === "string"
          ? { reason: document.reason }
          : {}),
      };
    },
  };
}
