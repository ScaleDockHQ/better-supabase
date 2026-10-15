import type { CommerceEventData, Events } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `promotions` block: type to data. */
export type PromotionsEvents = {
  readonly "promotion.redeemed": CommerceEventData;
};

/** The `promotions` block's event types, for its manifest and `onBlockEvent`. */
export const promotionsEvents: Events<PromotionsEvents> = defineEvents({
  "promotion.redeemed": event<CommerceEventData>(),
});
