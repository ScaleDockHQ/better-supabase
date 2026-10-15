import type { CommerceEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `promotions` block: type to data. */
export type PromotionsEvents = {
  readonly "promotion.redeemed": CommerceEventData;
};

/** The `promotions` block's event types, for its manifest and `onBlockEvent`. */
export const promotionsEvents: Events<PromotionsEvents> = defineEvents({
  "promotion.redeemed": event<CommerceEventData>(),
});
