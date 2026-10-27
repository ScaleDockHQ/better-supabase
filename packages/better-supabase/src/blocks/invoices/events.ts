import type { InvoiceEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `invoices` block: type to data. */
export type InvoicesEvents = {
  readonly "invoice.created": InvoiceEventData;
  readonly "invoice.issued": InvoiceEventData;
  readonly "invoice.payment_recorded": InvoiceEventData;
  readonly "invoice.paid": InvoiceEventData;
  readonly "invoice.credited": InvoiceEventData;
  readonly "invoice.voided": InvoiceEventData;
  readonly "invoice.uncollected": InvoiceEventData;
  readonly "invoice.charged": InvoiceEventData;
};

/** The `invoices` block's event types, for its manifest and `onBlockEvent`. */
export const invoicesEvents: Events<InvoicesEvents> = defineEvents({
  "invoice.created": event<InvoiceEventData>(),
  "invoice.issued": event<InvoiceEventData>(),
  "invoice.payment_recorded": event<InvoiceEventData>(),
  "invoice.paid": event<InvoiceEventData>(),
  "invoice.credited": event<InvoiceEventData>(),
  "invoice.voided": event<InvoiceEventData>(),
  "invoice.uncollected": event<InvoiceEventData>(),
  "invoice.charged": event<InvoiceEventData>(),
});
