import type { Invoice } from "../blocks/invoices/invoices.ts";
import type { EInvoiceEndpoint } from "./party.ts";

/** A UBL document as `toUbl` writes it or a channel receives it. */
export interface EInvoiceDocument {
  /** `Invoice` or `CreditNote`, the document's root element. */
  readonly type: "Invoice" | "CreditNote";
  /** The document number (BT-1). */
  readonly id: string;
  readonly xml: string;
}

/** What a format and a channel get next to the invoice. */
export interface EInvoiceContext {
  readonly organizationId: string;
  readonly signal?: AbortSignal;
  /**
   * The participant ids stored for the invoice's seller (its legal entity or
   * the organization) and buyer (its company), when `sendEInvoice` renders.
   */
  readonly endpoints?: {
    readonly seller?: EInvoiceEndpoint;
    readonly buyer?: EInvoiceEndpoint;
  };
}

/**
 * Renders an issued invoice or credit note as an e-invoice document. Versioned:
 * a breaking change ships a new `apiVersion`. `peppolBis3Format` is the one
 * better-supabase ships.
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

/** What `send` gets next to the document. */
export interface EInvoiceSendContext extends EInvoiceContext {
  /** The buyer's participant id the access point delivers to. */
  readonly recipient: EInvoiceEndpoint;
  readonly invoice: Invoice;
}

/** What a channel reports after it accepted a document. */
export interface EInvoiceSent {
  /** The channel's id for the transmission, to look it up later. */
  readonly messageId: string;
  readonly acceptedAt?: Temporal.Instant;
}

/** Where a sent e-invoice stands at the network. */
export interface EInvoiceStatus {
  readonly state: "pending" | "delivered" | "rejected";
  /** Why the network rejected it. */
  readonly reason?: string;
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
  /** Identifies the channel in logs and deliveries, such as `"storecove"`. */
  readonly key: string;
  send(
    document: EInvoiceDocument,
    context: EInvoiceSendContext,
  ): Promise<EInvoiceSent>;
  /** What the network says about a sent document, when it can be asked. */
  status?(messageId: string, context: EInvoiceContext): Promise<EInvoiceStatus>;
  /** Documents waiting for the app, when the access point delivers by polling. */
  receive?(context: EInvoiceContext): Promise<readonly EInvoiceReceived[]>;
  /**
   * Whether the participant can receive the document type, from the Peppol
   * directory (an SMP lookup). Checked before `send` when present.
   */
  lookup?(
    endpoint: EInvoiceEndpoint,
    context: EInvoiceContext,
  ): Promise<boolean>;
}

/** Checks a format's contract version before the app uses it. */
export function eInvoiceFormatOf(format: EInvoiceFormat): EInvoiceFormat {
  const version: unknown = format.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `e-invoice format "${format.key}" targets e-invoice format API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the format for API 1.`,
    );
  }

  return format;
}

/** Checks a channel's contract version before the app uses it. */
export function eInvoiceChannelOf(channel: EInvoiceChannel): EInvoiceChannel {
  const version: unknown = channel.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `e-invoice channel "${channel.key}" targets e-invoice channel API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the channel for API 1.`,
    );
  }

  return channel;
}
