import type { Invoice } from "./invoices.ts";

import { AsyncResult, err, ok } from "../../core/result.ts";

/** What a format and a channel get next to the invoice. */
export interface EInvoiceContext {
  readonly organizationId: string;
  readonly signal?: AbortSignal;
}

/** An invoice rendered in a network's format, such as UBL for Peppol BIS. */
export interface EInvoiceDocument {
  readonly body: string;
  /** A file name without a path, such as `INV-2026-0042.xml`. */
  readonly filename: string;
  /** The media type, such as `application/xml`. */
  readonly contentType: string;
}

/**
 * Renders an issued invoice or credit note as an e-invoice document: UBL 2.1,
 * Peppol BIS Billing 3.0, XRechnung or Factur-X. Versioned: a breaking change
 * ships a new `apiVersion`. better-supabase bundles none; a format package
 * implements the layout of its own standard.
 */
export interface EInvoiceFormat {
  readonly apiVersion: 1;
  /** The format's name, such as `peppol-bis-3`. */
  readonly key: string;
  render(
    invoice: Invoice,
    context: EInvoiceContext,
  ): EInvoiceDocument | Promise<EInvoiceDocument>;
}

/** Where a sent e-invoice stands at the network. */
export interface EInvoiceStatus {
  readonly state: "pending" | "delivered" | "rejected";
  /** Why the network rejected it. */
  readonly reason?: string;
}

/**
 * How e-invoices reach the customer's access point: Peppol, a national platform
 * or a provider's API. Versioned like `EInvoiceFormat`; the channel package
 * owns credentials and transport.
 */
export interface EInvoiceChannel {
  readonly apiVersion: 1;
  /** The channel's name, such as `peppol`. */
  readonly key: string;
  send(
    document: EInvoiceDocument,
    context: EInvoiceContext & { readonly invoice: Invoice },
  ): Promise<{ readonly externalRef: string }>;
  /** What the network says about a sent document, when it can be asked. */
  status?(
    externalRef: string,
    context: EInvoiceContext,
  ): Promise<EInvoiceStatus>;
}

/** Checks the format's `apiVersion` before rendering with it. */
export function eInvoiceFormatOf(format: EInvoiceFormat): EInvoiceFormat {
  const version: unknown = format.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `e-invoice format "${format.key}" targets e-invoice format API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the format for API 1.`,
    );
  }

  return format;
}

/** Checks the channel's `apiVersion` before sending with it. */
export function eInvoiceChannelOf(channel: EInvoiceChannel): EInvoiceChannel {
  const version: unknown = channel.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `e-invoice channel "${channel.key}" targets e-invoice channel API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the channel for API 1.`,
    );
  }

  return channel;
}

export interface SendEInvoiceOptions {
  /** An issued invoice or credit note, as `invoices.issue` returns it. */
  readonly invoice: Invoice;
  readonly format: EInvoiceFormat;
  readonly channel: EInvoiceChannel;
  readonly signal?: AbortSignal;
}

export interface EInvoiceDelivery {
  readonly invoiceId: string;
  readonly format: string;
  readonly channel: string;
  /** The channel's reference; keep it to ask `status` later. */
  readonly externalRef: string;
  readonly document: EInvoiceDocument;
}

/**
 * Renders the invoice with `format` and sends it through `channel`. Drafts and
 * void invoices are refused with `EINVOICE_NOT_ISSUED`, and a format or channel
 * that throws (or targets another API version) comes back as an error result,
 * never as an exception. The call does not record anything: the app keeps the
 * `externalRef`.
 */
export function sendEInvoice(
  options: SendEInvoiceOptions,
): AsyncResult<EInvoiceDelivery> {
  return AsyncResult.from(async () => {
    const { invoice } = options;

    if (invoice.status === "draft" || invoice.status === "void") {
      return err({
        kind: "invalid_input",
        message: `a ${invoice.status} invoice can't be sent as an e-invoice`,
        status: 422,
        hint: "EINVOICE_NOT_ISSUED",
      });
    }

    const format = eInvoiceFormatOf(options.format);

    const channel = eInvoiceChannelOf(options.channel);

    const context: EInvoiceContext = {
      organizationId: invoice.organizationId,
      ...(options.signal ? { signal: options.signal } : {}),
    };

    const document = await format.render(invoice, context);

    const sent = await channel.send(document, { ...context, invoice });

    return ok({
      invoiceId: invoice.id,
      format: format.key,
      channel: channel.key,
      externalRef: sent.externalRef,
      document,
    });
  });
}
