import type { DealEventData, Events } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `deals` block: type to data. */
export type DealsEvents = {
  readonly "deal.created": DealEventData;
  readonly "deal.updated": DealEventData;
  readonly "deal.closed": DealEventData;
  readonly "deal.reopened": DealEventData;
  readonly "deal.archived": DealEventData;
  readonly "deal.deleted": DealEventData;
};

/** The `deals` block's event types, for its manifest and `onBlockEvent`. */
export const dealsEvents: Events<DealsEvents> = defineEvents({
  "deal.created": event<DealEventData>(),
  "deal.updated": event<DealEventData>(),
  "deal.closed": event<DealEventData>(),
  "deal.reopened": event<DealEventData>(),
  "deal.archived": event<DealEventData>(),
  "deal.deleted": event<DealEventData>(),
});
