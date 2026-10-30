import type {
  CommerceEventData,
  CommerceSubjectEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `inventory` block: type to data. */
export type InventoryEvents = {
  readonly "stock.adjusted": CommerceEventData;
  readonly "stock.reorder_point_reached": CommerceSubjectEventData;
  readonly "reservation.created": CommerceEventData;
  readonly "reservation.committed": CommerceEventData;
  readonly "reservation.released": CommerceEventData;
  readonly "allocation.created": CommerceEventData;
  readonly "allocation.filled": CommerceEventData;
  readonly "allocation.released": CommerceEventData;
  readonly "transfer.shipped": CommerceEventData;
  readonly "transfer.received": CommerceEventData;
  readonly "transfer.cancelled": CommerceEventData;
  readonly "purchase_order.placed": CommerceEventData;
  readonly "purchase_order.received": CommerceEventData;
  readonly "purchase_order.cancelled": CommerceEventData;
  readonly "purchase_requisition.created": CommerceEventData;
  readonly "purchase_requisition.approved": CommerceEventData;
  readonly "inventory_receipt.created": CommerceEventData;
};

/** The `inventory` block's event types, for its manifest and `onBlockEvent`. */
export const inventoryEvents: Events<InventoryEvents> = defineEvents({
  "stock.adjusted": event<CommerceEventData>(),
  "stock.reorder_point_reached": event<CommerceSubjectEventData>(),
  "reservation.created": event<CommerceEventData>(),
  "reservation.committed": event<CommerceEventData>(),
  "reservation.released": event<CommerceEventData>(),
  "allocation.created": event<CommerceEventData>(),
  "allocation.filled": event<CommerceEventData>(),
  "allocation.released": event<CommerceEventData>(),
  "transfer.shipped": event<CommerceEventData>(),
  "transfer.received": event<CommerceEventData>(),
  "transfer.cancelled": event<CommerceEventData>(),
  "purchase_order.placed": event<CommerceEventData>(),
  "purchase_order.received": event<CommerceEventData>(),
  "purchase_order.cancelled": event<CommerceEventData>(),
  "purchase_requisition.created": event<CommerceEventData>(),
  "purchase_requisition.approved": event<CommerceEventData>(),
  "inventory_receipt.created": event<CommerceEventData>(),
});
