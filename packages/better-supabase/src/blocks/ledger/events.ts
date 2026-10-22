import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `ledger_account.opened` and `ledger_account.closed`. */
export interface LedgerAccountEventData {
  readonly organizationId: string;
  /** The account. */
  readonly id: string;
  /** What the account is for, such as `credit`, `stock` or `leave`. */
  readonly kind: string;
  /** Unique per organization, such as `credit:<party id>`. */
  readonly code: string;
  /** An ISO 4217 code, or a custom unit such as `item`, `days` or `points`. */
  readonly unit: string;
  /** Who or what the account belongs to, when it says. */
  readonly holderType: string | null;
  readonly holderId: string | null;
}

/** `ledger_transaction.posted` and `ledger_transaction.reversed`. */
export interface LedgerTransactionEventData {
  readonly organizationId: string;
  /** The transaction. */
  readonly id: string;
  /** What the transaction records, such as `stock.sale` or `credit.grant`. */
  readonly kind: string;
  readonly referenceType: string | null;
  readonly referenceId: string | null;
  /** The transaction this one reverses, when it does. */
  readonly reverses: string | null;
  /** How many entries the transaction has (two or more). */
  readonly entries: number;
}

/** `ledger_hold.placed`, `ledger_hold.captured` and `ledger_hold.released`. */
export interface LedgerHoldEventData {
  readonly organizationId: string;
  /** The hold. */
  readonly id: string;
  readonly accountId: string;
  /** In the account's unit, as text. */
  readonly amount: string;
  /** `active`, `captured`, `released` or `expired`. */
  readonly status: string;
  /** The transaction a capture posted. */
  readonly transactionId: string | null;
}

/** The events of the `ledger` block: type to data. */
export type LedgerEvents = {
  readonly "ledger_account.opened": LedgerAccountEventData;
  readonly "ledger_account.closed": LedgerAccountEventData;
  readonly "ledger_transaction.posted": LedgerTransactionEventData;
  readonly "ledger_transaction.reversed": LedgerTransactionEventData;
  readonly "ledger_hold.placed": LedgerHoldEventData;
  readonly "ledger_hold.captured": LedgerHoldEventData;
  readonly "ledger_hold.released": LedgerHoldEventData;
};

/** The `ledger` block's event types, for its manifest and `onBlockEvent`. */
export const ledgerEvents: Events<LedgerEvents> = defineEvents({
  "ledger_account.opened": event<LedgerAccountEventData>(),
  "ledger_account.closed": event<LedgerAccountEventData>(),
  "ledger_transaction.posted": event<LedgerTransactionEventData>(),
  "ledger_transaction.reversed": event<LedgerTransactionEventData>(),
  "ledger_hold.placed": event<LedgerHoldEventData>(),
  "ledger_hold.captured": event<LedgerHoldEventData>(),
  "ledger_hold.released": event<LedgerHoldEventData>(),
});
