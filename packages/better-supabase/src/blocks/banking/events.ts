import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `bank_statement.imported`: a statement or a feed's transactions arrived. */
export interface BankStatementImportedEventData {
  readonly organizationId: string;
  /** The statement. */
  readonly id: string;
  /** The bank account. */
  readonly accountId: string;
  readonly reference: string | null;
  /** How many transactions the import added; replays add none. */
  readonly imported: number;
}

/** What every `bank_transaction.*` event carries. */
export interface BankTransactionEventData {
  readonly organizationId: string;
  /** The bank transaction. */
  readonly id: string;
  /** The bank account. */
  readonly accountId: string;
  /** Minor units of currency as decimal text, negative for money out. */
  readonly amount: string;
  readonly currency: string;
  /** Its status after the change. */
  readonly status: string;
}

/** `bank_transaction.matched`. */
export interface BankTransactionMatchedEventData extends BankTransactionEventData {
  /** What it was matched to. */
  readonly matches: readonly {
    readonly targetType: string;
    readonly targetId: string;
    /** Minor units as decimal text. */
    readonly amount: string;
  }[];
  /** The bank rule that matched it, or null for a manual match. */
  readonly ruleId: string | null;
}

/** The events of the `banking` block: type to data. */
export type BankingEvents = {
  readonly "bank_statement.imported": BankStatementImportedEventData;
  readonly "bank_transaction.matched": BankTransactionMatchedEventData;
  readonly "bank_transaction.unmatched": BankTransactionEventData;
};

/** The `banking` block's event types, for its manifest and `onBlockEvent`. */
export const bankingEvents: Events<BankingEvents> = defineEvents({
  "bank_statement.imported": event<BankStatementImportedEventData>(),
  "bank_transaction.matched": event<BankTransactionMatchedEventData>(),
  "bank_transaction.unmatched": event<BankTransactionEventData>(),
});
