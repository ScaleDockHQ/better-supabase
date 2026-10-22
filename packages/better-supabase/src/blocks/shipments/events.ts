import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `shipment.created`. */
export interface ShipmentCreatedEventData {
  readonly organizationId: string;
  /** The shipment. */
  readonly id: string;
  readonly reference: string;
  readonly subjectType: string | null;
  readonly subjectId: string | null;
}

/** `shipment.labeled`: a label was bought for it. */
export interface ShipmentLabeledEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly carrier: string;
  readonly service: string;
  readonly trackingNumber: string;
}

/** `shipment.status_changed`: its latest tracking event has another status. */
export interface ShipmentStatusChangedEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly from: string;
  readonly to: string;
  readonly trackingNumber: string | null;
}

/** `shipment.cancelled`. */
export interface ShipmentCancelledEventData {
  readonly organizationId: string;
  readonly id: string;
  /** Set when the shipment had a label the carrier voided. */
  readonly trackingNumber: string | null;
}

/** The events of the `shipments` block: type to data. */
export type ShipmentsEvents = {
  readonly "shipment.created": ShipmentCreatedEventData;
  readonly "shipment.labeled": ShipmentLabeledEventData;
  readonly "shipment.status_changed": ShipmentStatusChangedEventData;
  readonly "shipment.cancelled": ShipmentCancelledEventData;
};

/** The `shipments` block's event types, for its manifest and `onBlockEvent`. */
export const shipmentsEvents: Events<ShipmentsEvents> = defineEvents({
  "shipment.created": event<ShipmentCreatedEventData>(),
  "shipment.labeled": event<ShipmentLabeledEventData>(),
  "shipment.status_changed": event<ShipmentStatusChangedEventData>(),
  "shipment.cancelled": event<ShipmentCancelledEventData>(),
});
