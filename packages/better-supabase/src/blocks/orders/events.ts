import type { CommerceSubjectEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `orders` block: type to data. */
export type OrdersEvents = {
  readonly "order.placed": CommerceSubjectEventData;
  readonly "order.paid": CommerceSubjectEventData;
  readonly "order.cancelled": CommerceSubjectEventData;
  readonly "order.drafted": CommerceSubjectEventData;
  readonly "order.hold_placed": CommerceSubjectEventData;
  readonly "order.hold_released": CommerceSubjectEventData;
  readonly "order.fulfilled": CommerceSubjectEventData;
  readonly "order.completed": CommerceSubjectEventData;
  readonly "order.refunded": CommerceSubjectEventData;
  readonly "fulfillment.shipped": CommerceSubjectEventData;
  readonly "fulfillment.delivered": CommerceSubjectEventData;
  readonly "return.requested": CommerceSubjectEventData;
  readonly "return.received": CommerceSubjectEventData;
  readonly "order.prepared": CommerceSubjectEventData;
  readonly "order.served": CommerceSubjectEventData;
};

/** The `orders` block's event types, for its manifest and `onBlockEvent`. */
export const ordersEvents: Events<OrdersEvents> = defineEvents({
  "order.placed": event<CommerceSubjectEventData>({ public: true }),
  "order.paid": event<CommerceSubjectEventData>({ public: true }),
  "order.cancelled": event<CommerceSubjectEventData>({ public: true }),
  "order.drafted": event<CommerceSubjectEventData>(),
  "order.hold_placed": event<CommerceSubjectEventData>(),
  "order.hold_released": event<CommerceSubjectEventData>(),
  "order.fulfilled": event<CommerceSubjectEventData>({ public: true }),
  "order.completed": event<CommerceSubjectEventData>({ public: true }),
  "order.refunded": event<CommerceSubjectEventData>({ public: true }),
  "fulfillment.shipped": event<CommerceSubjectEventData>({ public: true }),
  "fulfillment.delivered": event<CommerceSubjectEventData>({ public: true }),
  "return.requested": event<CommerceSubjectEventData>({ public: true }),
  "return.received": event<CommerceSubjectEventData>({ public: true }),
  "order.prepared": event<CommerceSubjectEventData>(),
  "order.served": event<CommerceSubjectEventData>(),
});
