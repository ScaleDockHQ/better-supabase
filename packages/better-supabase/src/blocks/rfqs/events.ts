import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `rfq.*` event carries. */
export interface RfqEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly number: string;
  /** `draft`, `open`, `closed`, `awarded` or `cancelled`. */
  readonly status: string;
  /** The awarded quote; set on `rfq.awarded`. */
  readonly quoteId: string | null;
  /** The purchase order the award created; set on `rfq.awarded`. */
  readonly purchaseOrderId: string | null;
}

/** What every `rfq_quote.*` event carries. */
export interface RfqQuoteEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly rfqId: string;
  readonly invitationId: string;
  /** The quote total in minor units, as text. */
  readonly total: string;
}

/** The events of the `rfqs` block: type to data. */
export type RfqsEvents = {
  readonly "rfq.created": RfqEventData;
  readonly "rfq.updated": RfqEventData;
  readonly "rfq.opened": RfqEventData;
  readonly "rfq.closed": RfqEventData;
  readonly "rfq.awarded": RfqEventData;
  readonly "rfq.cancelled": RfqEventData;
  readonly "rfq_quote.submitted": RfqQuoteEventData;
  readonly "rfq_quote.withdrawn": RfqQuoteEventData;
};

/** The `rfqs` block's event types, for its manifest and `onBlockEvent`. */
export const rfqsEvents: Events<RfqsEvents> = defineEvents({
  "rfq.created": event<RfqEventData>(),
  "rfq.updated": event<RfqEventData>(),
  "rfq.opened": event<RfqEventData>(),
  "rfq.closed": event<RfqEventData>(),
  "rfq.awarded": event<RfqEventData>(),
  "rfq.cancelled": event<RfqEventData>(),
  "rfq_quote.submitted": event<RfqQuoteEventData>(),
  "rfq_quote.withdrawn": event<RfqQuoteEventData>(),
});
