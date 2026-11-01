import type { BlockCall } from "../../core/block-helpers.ts";
import type { Err } from "../../core/result.ts";
import type {
  EInvoiceChannel,
  EInvoiceContext,
  EInvoiceDocument,
  EInvoiceFormat,
} from "../../e-invoicing/channel.ts";
import type { EInvoiceEndpoint } from "../../e-invoicing/party.ts";
import type { FromUblOptions, UblBill } from "../../e-invoicing/read.ts";
import type { LineInput } from "../sales-lines.ts";
import type { Invoice, InvoiceInput } from "./invoices.ts";

import { sha256Hex } from "../../core/block-helpers.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  eInvoiceChannelOf,
  eInvoiceFormatOf,
} from "../../e-invoicing/channel.ts";
import { fromUbl } from "../../e-invoicing/read.ts";
import { compact } from "../sales-shared.ts";
import {
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/** Where an e-invoice stands in the delivery log. */
export type EInvoiceDeliveryState =
  | "pending"
  | "delivered"
  | "rejected"
  | "received"
  | "unmatched";

/** One row of `invoice_e_deliveries`: a document a channel took or delivered. */
export interface EInvoiceDeliveryRecord {
  readonly id: string;
  readonly organizationId: string;
  /** The invoice sent, or the purchase bill a received document became. */
  readonly invoiceId?: string;
  readonly direction: "outbound" | "inbound";
  readonly format?: string;
  readonly channel: string;
  /** The channel's id for the document. */
  readonly messageId: string;
  readonly state: EInvoiceDeliveryState;
  /** Why the network rejected it, or why a received one is unmatched. */
  readonly reason?: string;
  /** SHA-256 of the document's XML. */
  readonly documentHash?: string;
  readonly createdAt?: Temporal.Instant;
  readonly updatedAt?: Temporal.Instant;
}

/** What `sendEInvoice` did. */
export interface EInvoiceDelivery {
  readonly delivery: EInvoiceDeliveryRecord;
  readonly document: EInvoiceDocument;
}

/** What `syncEInvoices` found. */
export interface EInvoiceSync {
  readonly checked: number;
  readonly delivered: number;
  readonly rejected: number;
}

/** What `receiveEInvoices` did with each document the channel had. */
export interface EInvoiceReceipt {
  /** Purchase bills created. */
  readonly created: readonly EInvoiceDeliveryRecord[];
  /** Documents already in the log. */
  readonly skipped: number;
  /** Documents logged as `unmatched`: no known supplier, or unreadable. */
  readonly unmatched: readonly EInvoiceDeliveryRecord[];
}

/** The participant ids of an invoice's seller and buyer. */
export interface EInvoiceEndpoints {
  readonly seller?: EInvoiceEndpoint;
  readonly buyer?: EInvoiceEndpoint;
}

export type EInvoicePartyKind = "organization" | "legal_entity" | "company";

export interface SendEInvoiceOptions {
  /** Defaults to the channel's own format; pass `peppolBis3Format(...)`. */
  readonly format: EInvoiceFormat;
  readonly channel: EInvoiceChannel;
  /** Send again after a rejection, or when the first send is still pending. */
  readonly resend?: boolean;
  readonly signal?: AbortSignal;
}

/** E-invoice delivery on the invoices client. */
export interface InvoiceEDelivery<I> {
  /**
   * Renders an issued invoice or credit note with `format`, checks the buyer
   * with `channel.lookup` when it has one, sends it, and logs the delivery as
   * `pending`. Needs `invoices.send` and a participant id on the buyer's
   * company. A delivered invoice is refused unless `resend` is set.
   */
  sendEInvoice(
    invoice: I,
    options: SendEInvoiceOptions,
  ): AsyncResult<EInvoiceDelivery>;
  /**
   * Logs a document the channel already accepted, as `pending`. Use it with
   * the message id a failed `sendEInvoice` names instead of sending again; the
   * same channel and message id return the first row.
   */
  recordEInvoiceDelivery(
    invoice: I,
    input: {
      readonly channel: string;
      readonly format: string;
      readonly messageId: string;
    },
  ): AsyncResult<EInvoiceDeliveryRecord>;
  /** Asks the channel about every pending delivery and records the answer. */
  syncEInvoices(
    organizationId: string,
    options: {
      readonly channel: EInvoiceChannel;
      readonly signal?: AbortSignal;
    },
  ): AsyncResult<EInvoiceSync>;
  /**
   * Takes the documents the channel has for the organization and creates a
   * purchase bill for each whose sender is a known company. The log makes a
   * replay add nothing.
   */
  receiveEInvoices(
    organizationId: string,
    options: ReceiveEInvoicesOptions,
  ): AsyncResult<EInvoiceReceipt>;
  /**
   * Sets, or with `null` clears, the participant id of an organization, legal
   * entity or company.
   */
  setEInvoiceEndpoint(
    organizationId: string,
    partyKind: EInvoicePartyKind,
    partyId: string,
    endpoint: EInvoiceEndpoint | null,
  ): AsyncResult<EInvoiceEndpoint | null>;
  /** The participant ids of an invoice's seller and buyer. */
  eInvoiceEndpoints(invoiceId: string): AsyncResult<EInvoiceEndpoints>;
  /** The delivery log, newest first. */
  eInvoiceDeliveries(
    organizationId: string,
    options?: {
      readonly direction?: "outbound" | "inbound";
      readonly state?: EInvoiceDeliveryState;
      readonly invoiceId?: string;
    },
  ): AsyncResult<readonly EInvoiceDeliveryRecord[]>;
}

export interface ReceiveEInvoicesOptions extends FromUblOptions {
  readonly channel: EInvoiceChannel;
  readonly signal?: AbortSignal;
}

const STATES: readonly EInvoiceDeliveryState[] = [
  "pending",
  "delivered",
  "rejected",
  "received",
  "unmatched",
];

function deliveryOf(value: unknown): EInvoiceDeliveryRecord {
  const row = recordOf(value, "e-invoice delivery");
  const state = STATES.find((s) => s === row["state"]);

  if (state === undefined) {
    throw new TypeError(
      `Unknown e-invoice delivery state: ${String(row["state"])}`,
    );
  }

  return compact<EInvoiceDeliveryRecord>({
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    invoiceId: optionalText(row["invoiceId"]),
    direction: row["direction"] === "inbound" ? "inbound" : "outbound",
    format: optionalText(row["format"]),
    channel: textOf(row["channel"]),
    messageId: textOf(row["messageId"]),
    state,
    reason: optionalText(row["reason"]),
    documentHash: optionalText(row["documentHash"]),
    createdAt: optionalInstant(row["createdAt"]),
    updatedAt: optionalInstant(row["updatedAt"]),
  });
}

function endpointOf(value: unknown): EInvoiceEndpoint | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }

  const row = recordOf(value, "e-invoice endpoint");

  return { scheme: textOf(row["scheme"]), id: textOf(row["id"]) };
}

function endpointsOf(value: unknown): EInvoiceEndpoints {
  const row = recordOf(value, "e-invoice endpoints");
  const seller = endpointOf(row["seller"]);
  const buyer = endpointOf(row["buyer"]);

  return {
    ...(seller === undefined ? {} : { seller }),
    ...(buyer === undefined ? {} : { buyer }),
  };
}

const invalid = (message: string, hint: string): Err =>
  err({ kind: "invalid_input", message, status: 422, hint });

/** The e-invoice delivery methods of the invoices client. */
export function invoiceEDelivery<F extends object>(
  call: BlockCall,
  create: (
    organizationId: string,
    input: InvoiceInput<F>,
    lines: readonly LineInput[],
  ) => AsyncResult<Invoice<F>>,
): InvoiceEDelivery<Invoice<F>> {
  const record = (
    organizationId: string,
    args: Readonly<Record<string, unknown>>,
  ): AsyncResult<{
    readonly created: boolean;
    readonly delivery: EInvoiceDeliveryRecord;
  }> =>
    call(
      "record_e_invoice_delivery",
      { tenant: organizationId, ...args },
      (value) => {
        const row = recordOf(value, "record_e_invoice_delivery");

        return {
          created: row["created"] === true,
          delivery: deliveryOf(row["delivery"]),
        };
      },
    );

  const client: InvoiceEDelivery<Invoice<F>> = {
    sendEInvoice: (invoice, options) =>
      AsyncResult.from(async () => {
        if (invoice.status === "draft" || invoice.status === "void") {
          return invalid(
            `a ${invoice.status} invoice can't be sent as an e-invoice`,
            "EINVOICE_NOT_ISSUED",
          );
        }

        const format = eInvoiceFormatOf(options.format);
        const channel = eInvoiceChannelOf(options.channel);

        const endpoints = await client.eInvoiceEndpoints(invoice.id);

        if (!endpoints.ok) {
          return endpoints;
        }

        const { buyer } = endpoints.data;

        if (buyer === undefined) {
          return invalid(
            "the buyer has no e-invoice participant id; set one with setEInvoiceEndpoint",
            "EINVOICE_NO_RECIPIENT",
          );
        }

        if (options.resend !== true) {
          const sent = await client.eInvoiceDeliveries(invoice.organizationId, {
            direction: "outbound",
            invoiceId: invoice.id,
          });

          if (!sent.ok) {
            return sent;
          }

          if (
            sent.data.some(
              (row) => row.state === "delivered" || row.state === "pending",
            )
          ) {
            return invalid(
              "this invoice was already sent; pass resend to send it again",
              "EINVOICE_ALREADY_SENT",
            );
          }
        }

        const context: EInvoiceContext = {
          organizationId: invoice.organizationId,
          endpoints: endpoints.data,
          ...(options.signal ? { signal: options.signal } : {}),
        };

        if (channel.lookup !== undefined) {
          const reachable = await channel.lookup(buyer, context);

          if (!reachable) {
            return invalid(
              `${buyer.scheme}:${buyer.id} is not on ${channel.key}`,
              "EINVOICE_RECIPIENT_UNREACHABLE",
            );
          }
        }

        const document = await format.render(invoice, context);

        const sent = await channel.send(document, {
          ...context,
          recipient: buyer,
          invoice,
        });

        const logged = await record(invoice.organizationId, {
          direction: "outbound",
          channel: channel.key,
          message_id: sent.messageId,
          format: format.key,
          invoice: invoice.id,
          document_hash: await sha256Hex(document.xml),
        });

        if (!logged.ok) {
          return err({
            ...logged.error,
            message: `${channel.key} accepted the document as ${sent.messageId}, but logging it failed: ${logged.error.message}. Call recordEInvoiceDelivery with that message id instead of sending again.`,
          });
        }

        return ok({ delivery: logged.data.delivery, document });
      }),
    recordEInvoiceDelivery: (invoice, input) =>
      record(invoice.organizationId, {
        direction: "outbound",
        channel: input.channel,
        message_id: input.messageId,
        format: input.format,
        invoice: invoice.id,
      }).map((logged) => logged.delivery),
    syncEInvoices: (organizationId, options) =>
      AsyncResult.from(async () => {
        const channel = eInvoiceChannelOf(options.channel);

        if (channel.status === undefined) {
          return invalid(
            `channel ${channel.key} can't report delivery status`,
            "EINVOICE_CHANNEL_UNSUPPORTED",
          );
        }

        const pending = await client.eInvoiceDeliveries(organizationId, {
          direction: "outbound",
          state: "pending",
        });

        if (!pending.ok) {
          return pending;
        }

        const context: EInvoiceContext = {
          organizationId,
          ...(options.signal ? { signal: options.signal } : {}),
        };

        let checked = 0;
        let delivered = 0;
        let rejected = 0;

        for (const row of pending.data) {
          if (row.channel !== channel.key) {
            continue;
          }

          checked += 1;

          const status = await channel.status(row.messageId, context);

          if (status.state === "pending") {
            continue;
          }

          const moved = await call(
            "set_e_invoice_delivery_state",
            {
              delivery: row.id,
              state: status.state,
              reason: status.reason ?? null,
            },
            deliveryOf,
          );

          if (!moved.ok) {
            return moved;
          }

          if (status.state === "delivered") {
            delivered += 1;
          } else {
            rejected += 1;
          }
        }

        return ok({ checked, delivered, rejected });
      }),
    receiveEInvoices: (organizationId, options) =>
      AsyncResult.from(async () => {
        const channel = eInvoiceChannelOf(options.channel);

        if (channel.receive === undefined) {
          return invalid(
            `channel ${channel.key} can't receive documents`,
            "EINVOICE_CHANNEL_UNSUPPORTED",
          );
        }

        const received = await channel.receive({
          organizationId,
          ...(options.signal ? { signal: options.signal } : {}),
        });

        const created: EInvoiceDeliveryRecord[] = [];
        const unmatched: EInvoiceDeliveryRecord[] = [];
        let skipped = 0;

        for (const item of received) {
          const hash = await sha256Hex(item.xml);

          const logged = await record(organizationId, {
            direction: "inbound",
            channel: channel.key,
            message_id: item.messageId,
            document_hash: hash,
          });

          if (!logged.ok) {
            return logged;
          }

          if (!logged.data.created) {
            skipped += 1;
            continue;
          }

          const outcome = await billOf(
            organizationId,
            item.xml,
            item.sender,
            options,
          );

          if (outcome.kind === "unmatched") {
            const row = await call(
              "set_e_invoice_delivery_state",
              {
                delivery: logged.data.delivery.id,
                state: "unmatched",
                reason: outcome.reason,
              },
              deliveryOf,
            );

            if (!row.ok) {
              return row;
            }

            unmatched.push(row.data);
            continue;
          }

          const bill = await create(
            organizationId,
            // SAFETY: the bill's input carries no extra columns, so it fits InvoiceInput<F>.
            {
              ...outcome.bill.input,
              direction: "purchase",
              company: { type: "company", id: outcome.companyId },
            },
            outcome.bill.lines,
          );

          if (!bill.ok) {
            return bill;
          }

          const row = await call(
            "set_e_invoice_delivery_state",
            {
              delivery: logged.data.delivery.id,
              state: "received",
              invoice: bill.data.id,
            },
            deliveryOf,
          );

          if (!row.ok) {
            return row;
          }

          created.push(row.data);
        }

        return ok({ created, skipped, unmatched });
      }),
    setEInvoiceEndpoint: (organizationId, partyKind, partyId, endpoint) =>
      call(
        "set_invoice_e_endpoint",
        {
          tenant: organizationId,
          party_kind: partyKind,
          party_id: partyId,
          scheme: endpoint?.scheme ?? null,
          endpoint_id: endpoint?.id ?? null,
        },
        (value) => endpointOf(value) ?? null,
      ),
    eInvoiceEndpoints: (invoiceId) =>
      call("invoice_e_endpoints", { invoice: invoiceId }, endpointsOf),
    eInvoiceDeliveries: (organizationId, options = {}) =>
      call(
        "list_e_invoice_deliveries",
        {
          tenant: organizationId,
          direction: options.direction ?? null,
          state: options.state ?? null,
          invoice: options.invoiceId ?? null,
        },
        (value) =>
          value === null || value === undefined
            ? []
            : recordsOf(value, "e-invoice deliveries").map(deliveryOf),
      ),
  };

  async function billOf(
    organizationId: string,
    xml: string,
    sender: EInvoiceEndpoint | undefined,
    options: FromUblOptions,
  ): Promise<
    | {
        readonly kind: "bill";
        readonly bill: UblBill;
        readonly companyId: string;
      }
    | { readonly kind: "unmatched"; readonly reason: string }
  > {
    let bill: UblBill;

    try {
      bill = await fromUbl(xml, options);
    } catch (cause) {
      return {
        kind: "unmatched",
        reason: cause instanceof Error ? cause.message : "unreadable document",
      };
    }

    const supplier = sender ?? bill.seller.endpoint;

    const found = await call(
      "find_e_endpoint_party",
      {
        tenant: organizationId,
        scheme: supplier.scheme,
        endpoint_id: supplier.id,
      },
      (value) =>
        value === null || value === undefined
          ? undefined
          : recordOf(value, "find_e_endpoint_party"),
    );

    const party = found.ok ? found.data : undefined;

    if (party === undefined || party["partyKind"] !== "company") {
      return {
        kind: "unmatched",
        reason: `no company has ${supplier.scheme}:${supplier.id}`,
      };
    }

    return { kind: "bill", bill, companyId: textOf(party["partyId"]) };
  }

  return client;
}
