import type {
  CommerceSubjectEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `orders` block: type to data. */
export type OrdersEvents = {
  readonly "order.placed": CommerceSubjectEventData;
  readonly "order.paid": CommerceSubjectEventData;
  readonly "order.cancelled": CommerceSubjectEventData;
  readonly "order.fulfilled": CommerceSubjectEventData;
  readonly "order.completed": CommerceSubjectEventData;
  readonly "order.refunded": CommerceSubjectEventData;
  readonly "fulfillment.shipped": CommerceSubjectEventData;
  readonly "fulfillment.delivered": CommerceSubjectEventData;
  readonly "return.requested": CommerceSubjectEventData;
  readonly "return.received": CommerceSubjectEventData;
};

/** The `orders` block's event types, for its manifest and `onBlockEvent`. */
export const ordersEvents: Events<OrdersEvents> = defineEvents({
  "order.placed": event<CommerceSubjectEventData>(),
  "order.paid": event<CommerceSubjectEventData>(),
  "order.cancelled": event<CommerceSubjectEventData>(),
  "order.fulfilled": event<CommerceSubjectEventData>(),
  "order.completed": event<CommerceSubjectEventData>(),
  "order.refunded": event<CommerceSubjectEventData>(),
  "fulfillment.shipped": event<CommerceSubjectEventData>(),
  "fulfillment.delivered": event<CommerceSubjectEventData>(),
  "return.requested": event<CommerceSubjectEventData>(),
  "return.received": event<CommerceSubjectEventData>(),
});
