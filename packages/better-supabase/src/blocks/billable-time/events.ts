import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `time_entry.invoiced`: unbilled time became a draft invoice. */
export interface TimeInvoicedEventData {
  readonly organizationId: string;
  readonly invoiceId: string;
  /** The time entries the invoice billed. */
  readonly entryIds: readonly string[];
  readonly currency: string;
  /** The invoice's lines before discounts and tax, in minor units as text. */
  readonly total: string;
}

/** The events of the `billable-time` block: type to data. */
export type BillableTimeEvents = {
  readonly "time_entry.invoiced": TimeInvoicedEventData;
};

/** The `billable-time` block's event types, for its manifest and `onBlockEvent`. */
export const billableTimeEvents: Events<BillableTimeEvents> = defineEvents({
  "time_entry.invoiced": event<TimeInvoicedEventData>(),
});
