import type { InvoiceEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `invoices` block: type to data. */
export type InvoicesEvents = {
  readonly "invoice.created": InvoiceEventData;
  readonly "invoice.updated": InvoiceEventData;
  readonly "invoice.deleted": InvoiceEventData;
  readonly "invoice.issued": InvoiceEventData;
  readonly "invoice.payment_recorded": InvoiceEventData;
  readonly "invoice.paid": InvoiceEventData;
  readonly "invoice.credited": InvoiceEventData;
  readonly "invoice.voided": InvoiceEventData;
  readonly "invoice.uncollected": InvoiceEventData;
  readonly "invoice.charged": InvoiceEventData;
  readonly "invoice.charge_removed": InvoiceEventData;
  readonly "invoice.payment_reversed": InvoiceEventData;
  readonly "invoice.match_checked": InvoiceEventData;
  readonly "invoice.credit_applied": InvoiceEventData;
  readonly "invoice.dunning_escalated": InvoiceEventData;
  readonly "invoice.dunning_paused": InvoiceEventData;
  readonly "invoice.collection_started": InvoiceEventData;
  readonly "invoice.allocated": InvoiceEventData;
  readonly "invoice.unallocated": InvoiceEventData;
  readonly "invoice.discount_applied": InvoiceEventData;
  readonly "invoice.approved": InvoiceEventData;
};

/** The `invoices` block's event types, for its manifest and `onBlockEvent`. */
export const invoicesEvents: Events<InvoicesEvents> = defineEvents({
  "invoice.created": event<InvoiceEventData>(),
  "invoice.updated": event<InvoiceEventData>(),
  "invoice.deleted": event<InvoiceEventData>(),
  "invoice.issued": event<InvoiceEventData>(),
  "invoice.payment_recorded": event<InvoiceEventData>(),
  "invoice.paid": event<InvoiceEventData>(),
  "invoice.credited": event<InvoiceEventData>(),
  "invoice.voided": event<InvoiceEventData>(),
  "invoice.uncollected": event<InvoiceEventData>(),
  "invoice.charged": event<InvoiceEventData>(),
  "invoice.charge_removed": event<InvoiceEventData>(),
  "invoice.payment_reversed": event<InvoiceEventData>(),
  "invoice.match_checked": event<InvoiceEventData>(),
  "invoice.credit_applied": event<InvoiceEventData>(),
  "invoice.dunning_escalated": event<InvoiceEventData>(),
  "invoice.dunning_paused": event<InvoiceEventData>(),
  "invoice.collection_started": event<InvoiceEventData>(),
  "invoice.allocated": event<InvoiceEventData>(),
  "invoice.unallocated": event<InvoiceEventData>(),
  "invoice.discount_applied": event<InvoiceEventData>(),
  "invoice.approved": event<InvoiceEventData>(),
});
