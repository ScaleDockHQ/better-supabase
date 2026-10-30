import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `accounting_entry.posted`: an entry was posted to the books. */
export interface AccountingEntryPostedEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly journalId: string;
  /**
   * The entry's number in its journal and fiscal year, such as
   * `SAL-2026-00001`.
   */
  readonly number: string;
  /** `YYYY-MM-DD`. */
  readonly entryDate: string;
  readonly sourceType: string | null;
  readonly sourceId: string | null;
  /** The entry this one reverses, for a reversal. */
  readonly reversesId: string | null;
  /**
   * The sum of the debits in minor units of the functional currency, as a
   * decimal string.
   */
  readonly total: string;
}

/** `accounting_entry.reversed`: a posted entry was reversed by a new entry. */
export interface AccountingEntryReversedEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly journalId: string;
  readonly number: string;
  readonly sourceType: string | null;
  readonly sourceId: string | null;
  /** The entry that reverses it. */
  readonly reversalId: string;
}

/** `accounting_period.closed` and `accounting_period.reopened`. */
export interface AccountingPeriodEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly fiscalYear: number;
  readonly number: number;
  /** `YYYY-MM-DD`. */
  readonly startsOn: string;
  /** `YYYY-MM-DD`. */
  readonly endsOn: string;
}

/** `accounting_period.reopened`: a closed period was opened again. */
export interface AccountingPeriodReopenedEventData extends AccountingPeriodEventData {
  readonly reason: string;
}

/** `fiscal_year.closed`: a fiscal year was closed into retained earnings. */
export interface FiscalYearClosedEventData {
  readonly organizationId: string;
  readonly fiscalYear: number;
  /** The closing entry, or null when the year had no income or expenses. */
  readonly closingEntryId: string | null;
}

/** The events of the `accounting` block: type to data. */
export type AccountingEvents = {
  readonly "accounting_entry.posted": AccountingEntryPostedEventData;
  readonly "accounting_entry.reversed": AccountingEntryReversedEventData;
  readonly "accounting_period.closed": AccountingPeriodEventData;
  readonly "accounting_period.reopened": AccountingPeriodReopenedEventData;
  readonly "fiscal_year.closed": FiscalYearClosedEventData;
};

/** The `accounting` block's event types, for its manifest and `onBlockEvent`. */
export const accountingEvents: Events<AccountingEvents> = defineEvents({
  "accounting_entry.posted": event<AccountingEntryPostedEventData>(),
  "accounting_entry.reversed": event<AccountingEntryReversedEventData>(),
  "accounting_period.closed": event<AccountingPeriodEventData>(),
  "accounting_period.reopened": event<AccountingPeriodReopenedEventData>(),
  "fiscal_year.closed": event<FiscalYearClosedEventData>(),
});
