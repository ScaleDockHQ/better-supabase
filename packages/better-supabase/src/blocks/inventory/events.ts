import type {
  CommerceEventData,
  CommerceSubjectEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `inventory` block: type to data. */
export type InventoryEvents = {
  readonly "stock.adjusted": CommerceEventData;
  readonly "stock.reorder_point_reached": CommerceSubjectEventData;
  readonly "reservation.created": CommerceEventData;
  readonly "reservation.committed": CommerceEventData;
  readonly "reservation.released": CommerceEventData;
  readonly "transfer.shipped": CommerceEventData;
  readonly "transfer.received": CommerceEventData;
  readonly "transfer.cancelled": CommerceEventData;
  readonly "purchase_order.placed": CommerceEventData;
  readonly "purchase_order.received": CommerceEventData;
  readonly "purchase_order.cancelled": CommerceEventData;
};

/** The `inventory` block's event types, for its manifest and `onBlockEvent`. */
export const inventoryEvents: Events<InventoryEvents> = defineEvents({
  "stock.adjusted": event<CommerceEventData>(),
  "stock.reorder_point_reached": event<CommerceSubjectEventData>(),
  "reservation.created": event<CommerceEventData>(),
  "reservation.committed": event<CommerceEventData>(),
  "reservation.released": event<CommerceEventData>(),
  "transfer.shipped": event<CommerceEventData>(),
  "transfer.received": event<CommerceEventData>(),
  "transfer.cancelled": event<CommerceEventData>(),
  "purchase_order.placed": event<CommerceEventData>(),
  "purchase_order.received": event<CommerceEventData>(),
  "purchase_order.cancelled": event<CommerceEventData>(),
});
