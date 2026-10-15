import type { Events, QuoteEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `quotes` block: type to data. */
export type QuotesEvents = {
  readonly "quote.created": QuoteEventData;
  readonly "quote.updated": QuoteEventData;
  readonly "quote.sent": QuoteEventData;
  readonly "quote.viewed": QuoteEventData;
  readonly "quote.accepted": QuoteEventData;
  readonly "quote.rejected": QuoteEventData;
  readonly "quote.changes_requested": QuoteEventData;
  readonly "quote.expired": QuoteEventData;
  readonly "quote.revised": QuoteEventData;
};

/** The `quotes` block's event types, for its manifest and `onBlockEvent`. */
export const quotesEvents: Events<QuotesEvents> = defineEvents({
  "quote.created": event<QuoteEventData>(),
  "quote.updated": event<QuoteEventData>(),
  "quote.sent": event<QuoteEventData>(),
  "quote.viewed": event<QuoteEventData>(),
  "quote.accepted": event<QuoteEventData>(),
  "quote.rejected": event<QuoteEventData>(),
  "quote.changes_requested": event<QuoteEventData>(),
  "quote.expired": event<QuoteEventData>(),
  "quote.revised": event<QuoteEventData>(),
});
