import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `till.*` event carries. */
export interface TillEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly name: string;
  readonly currency: string;
}

/** What every `till_session.*` event carries. */
export interface TillSessionEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly tillId: string;
  /** `open` or `closed`. */
  readonly status: string;
}

/** What `till_movement.recorded` carries. */
export interface TillMovementEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly sessionId: string;
  /** `cash_sale`, `cash_refund`, `cash_in` or `cash_out`. */
  readonly kind: string;
  /** In minor units, as text. */
  readonly amount: string;
}

/** What every `till_deposit.*` event carries. */
export interface TillDepositEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly sessionId: string;
  /** In minor units, as text. */
  readonly amount: string;
  /** `pending` or `reconciled`. */
  readonly status: string;
  /** The matched bank transaction; set on `till_deposit.reconciled`. */
  readonly bankTransactionId: string | null;
}

/** The events of the `tills` block: type to data. */
export type TillsEvents = {
  readonly "till.created": TillEventData;
  readonly "till.updated": TillEventData;
  readonly "till_session.opened": TillSessionEventData;
  readonly "till_session.closed": TillSessionEventData;
  readonly "till_movement.recorded": TillMovementEventData;
  readonly "till_deposit.recorded": TillDepositEventData;
  readonly "till_deposit.reconciled": TillDepositEventData;
};

/** The `tills` block's event types, for its manifest and `onBlockEvent`. */
export const tillsEvents: Events<TillsEvents> = defineEvents({
  "till.created": event<TillEventData>(),
  "till.updated": event<TillEventData>(),
  "till_session.opened": event<TillSessionEventData>(),
  "till_session.closed": event<TillSessionEventData>(),
  "till_movement.recorded": event<TillMovementEventData>(),
  "till_deposit.recorded": event<TillDepositEventData>(),
  "till_deposit.reconciled": event<TillDepositEventData>(),
});
