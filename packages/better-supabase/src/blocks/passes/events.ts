import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `pass.issued`. */
export interface PassIssuedEventData {
  readonly organizationId: string;
  /** The pass. */
  readonly id: string;
  readonly kind: string;
  readonly holderUserId: string | null;
  readonly bookingId: string | null;
}

/** `pass.revoked`. */
export interface PassRevokedEventData {
  readonly organizationId: string;
  readonly id: string;
}

/** `pass.admitted`: a scan that admitted the holder. */
export interface PassAdmittedEventData {
  readonly organizationId: string;
  /** The pass. */
  readonly id: string;
  readonly checkInId: string;
  readonly resourceId: string | null;
  readonly bookingId: string | null;
}

/** `pass.rejected`: a scan that turned the holder away. */
export interface PassRejectedEventData extends PassAdmittedEventData {
  /** Why, such as `expired` or `full`. */
  readonly reason: string;
}

/** `pass.credit_used` and `pass.credit_refunded`: a class-credit movement. */
export interface PassCreditEventData {
  readonly organizationId: string;
  /** The pass. */
  readonly id: string;
  /** The ledger entry. */
  readonly entryId: string;
  readonly bookingId: string | null;
}

/** The events of the `passes` block: type to data. */
export type PassesEvents = {
  readonly "pass.issued": PassIssuedEventData;
  readonly "pass.revoked": PassRevokedEventData;
  readonly "pass.admitted": PassAdmittedEventData;
  readonly "pass.rejected": PassRejectedEventData;
  readonly "pass.credit_used": PassCreditEventData;
  readonly "pass.credit_refunded": PassCreditEventData;
};

/** The `passes` block's event types, for its manifest and `onBlockEvent`. */
export const passesEvents: Events<PassesEvents> = defineEvents({
  "pass.issued": event<PassIssuedEventData>(),
  "pass.revoked": event<PassRevokedEventData>(),
  "pass.admitted": event<PassAdmittedEventData>(),
  "pass.rejected": event<PassRejectedEventData>(),
  "pass.credit_used": event<PassCreditEventData>(),
  "pass.credit_refunded": event<PassCreditEventData>(),
});
