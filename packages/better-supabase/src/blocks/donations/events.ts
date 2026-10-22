import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A gift as its events carry it. */
export interface DonationEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly donorType: string;
  readonly donorId: string;
  readonly fundId: string | null;
  readonly pledgeId: string | null;
  /** Minor units, as text. */
  readonly amount: string;
  readonly currency: string;
  readonly status: "pending" | "posted" | "failed" | "refunded";
}

/** A pledge as its events carry it. */
export interface PledgeEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly donorType: string;
  readonly donorId: string;
  readonly fundId: string | null;
  /** Minor units per period, as text. */
  readonly amount: string;
  readonly currency: string;
  readonly frequency: "weekly" | "monthly" | "quarterly" | "yearly";
  readonly status: "active" | "paused" | "ended";
}

/** A tax receipt as its events carry it. */
export interface DonationReceiptEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly number: string;
  readonly kind: "gift" | "yearly";
  readonly donorType: string;
  readonly donorId: string;
  readonly amount: string;
  readonly currency: string;
}

/** The events of the `donations` block: type to data. */
export type DonationsEvents = {
  readonly "donation.received": DonationEventData;
  readonly "donation.failed": DonationEventData;
  readonly "donation.refunded": DonationEventData;
  readonly "pledge.created": PledgeEventData;
  readonly "pledge.updated": PledgeEventData;
  readonly "donation_receipt.issued": DonationReceiptEventData;
  readonly "donation_receipt.voided": DonationReceiptEventData;
};

/** The `donations` block's event types, for its manifest and `onBlockEvent`. */
export const donationsEvents: Events<DonationsEvents> = defineEvents({
  "donation.received": event<DonationEventData>(),
  "donation.failed": event<DonationEventData>(),
  "donation.refunded": event<DonationEventData>(),
  "pledge.created": event<PledgeEventData>(),
  "pledge.updated": event<PledgeEventData>(),
  "donation_receipt.issued": event<DonationReceiptEventData>(),
  "donation_receipt.voided": event<DonationReceiptEventData>(),
});
