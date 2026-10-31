import type { EInvoiceEndpoint } from "./party.ts";

/** A UBL document as `toUbl` writes it or a channel receives it. */
export interface EInvoiceDocument {
  /** `Invoice` or `CreditNote`, the document's root element. */
  readonly type: "Invoice" | "CreditNote";
  /** The document number (BT-1). */
  readonly id: string;
  readonly xml: string;
}

/** What a channel reports after it accepted a document. */
export interface EInvoiceSent {
  /** The channel's id for the transmission, to look it up later. */
  readonly messageId: string;
  readonly acceptedAt?: Temporal.Instant;
}

/** A document a channel delivered to the app. */
export interface EInvoiceReceived extends EInvoiceDocument {
  readonly messageId: string;
  readonly sender?: EInvoiceEndpoint;
}

/**
 * Sends UBL documents over a network such as Peppol, through an access point
 * the app picks. Implement it over `fetch`; better-supabase bundles none.
 */
export interface EInvoiceChannel {
  readonly apiVersion: 1;
  /** Identifies the channel in logs, such as `"storecove"`. */
  readonly name: string;
  send(
    document: EInvoiceDocument,
    recipient: EInvoiceEndpoint,
  ): Promise<EInvoiceSent>;
  /** Documents waiting for the app, when the access point delivers by polling. */
  receive?(): Promise<readonly EInvoiceReceived[]>;
}

/** Checks a channel's contract version before the app uses it. */
export function eInvoiceChannelOf(channel: EInvoiceChannel): EInvoiceChannel {
  const version: unknown = channel.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `e-invoice channel "${channel.name}" targets e-invoice channel API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the channel for API 1.`,
    );
  }

  return channel;
}
