import type { DeliveryChannel } from "./roles.ts";

import { optionalText, recordOf, textOf } from "../shared.ts";
import { DELIVERY_CHANNELS } from "./roles.ts";

/** Payment terms: due days, an early-payment discount and a credit restriction. */
export interface PaymentTerm {
  readonly id: string;
  readonly organizationId: string;
  /** Unique per organization, such as `NET30` or `2-10-NET30`. */
  readonly code: string;
  readonly name: string;
  /** Days from the issue date until an invoice is due. */
  readonly days: number;
  /** The early-payment discount the buyer may deduct, in basis points. */
  readonly discountBps: number;
  /** Days from the issue date during which the discount applies. */
  readonly discountDays: number;
  /**
   * A discount the buyer may deduct in basis points, with the tax computed on
   * the reduced amount.
   */
  readonly creditRestrictionBps: number;
}

/** What `savePaymentTerm` takes. A key that is left out keeps its value. */
export interface PaymentTermInput {
  readonly code: string;
  readonly name: string;
  /** 0 to 3650. Default 30. */
  readonly days?: number;
  /** 0 to 10000. Default 0. */
  readonly discountBps?: number;
  /** 0 to 3650. Default 0. */
  readonly discountDays?: number;
  /** 0 to 10000. Default 0. */
  readonly creditRestrictionBps?: number;
}

/** How a party gets one kind of document. */
export interface DeliveryPreference {
  readonly id: string;
  readonly organizationId: string;
  readonly partyId: string;
  /** The document type, such as `invoice` or `reminder`. */
  readonly documentType: string;
  readonly channel: DeliveryChannel;
  /** How many copies to send, 1 to 20. */
  readonly copies: number;
  /** The address for the email channel; the party's own when unset. */
  readonly email?: string;
}

/** One entry of `setDeliveryPreferences`. */
export interface DeliveryPreferenceInput {
  readonly documentType: string;
  readonly channel: DeliveryChannel;
  readonly copies?: number;
  readonly email?: string;
}

const count = (value: unknown, what: string): number => {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new TypeError(`${what} is not an integer`);
  }

  return value;
};

export function paymentTermOf(value: unknown): PaymentTerm {
  const row = recordOf(value, "payment terms");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    code: textOf(row["code"]),
    name: textOf(row["name"]),
    days: count(row["days"], "payment terms days"),
    discountBps: count(row["discountBps"], "payment terms discount"),
    discountDays: count(row["discountDays"], "payment terms discount days"),
    creditRestrictionBps: count(
      row["creditRestrictionBps"],
      "payment terms credit restriction",
    ),
  };
}

export function deliveryPreferenceOf(value: unknown): DeliveryPreference {
  const row = recordOf(value, "delivery preference");
  const channel = textOf(row["channel"]);
  const email = optionalText(row["email"]);

  const known = DELIVERY_CHANNELS.find((candidate) => candidate === channel);

  if (known === undefined) {
    throw new TypeError(`unknown delivery channel ${channel}`);
  }

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    partyId: textOf(row["partyId"]),
    documentType: textOf(row["documentType"]),
    channel: known,
    copies: count(row["copies"], "delivery copies"),
    ...(email === undefined ? {} : { email }),
  };
}
