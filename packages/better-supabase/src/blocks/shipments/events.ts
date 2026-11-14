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

/** `shipment.proof_recorded`: who received the delivered parcel was recorded. */
export interface ShipmentProofRecordedEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly deliveredTo: string | null;
}

/** `shipment.cancelled`. */
export interface ShipmentCancelledEventData {
  readonly organizationId: string;
  readonly id: string;
  /** Set when the shipment had a label the carrier voided. */
  readonly trackingNumber: string | null;
}

/** `shipment.return_received`: stock came back on a shipment that left. */
export interface ShipmentReturnReceivedEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The return lines received in this call. */
  readonly lines: number;
  /** Their total quantity, as a decimal string. */
  readonly quantity: string;
}

/** The events of the `shipments` block: type to data. */
export type ShipmentsEvents = {
  readonly "shipment.created": ShipmentCreatedEventData;
  readonly "shipment.labeled": ShipmentLabeledEventData;
  readonly "shipment.status_changed": ShipmentStatusChangedEventData;
  readonly "shipment.cancelled": ShipmentCancelledEventData;
  readonly "shipment.proof_recorded": ShipmentProofRecordedEventData;
  readonly "shipment.return_received": ShipmentReturnReceivedEventData;
};

/** The `shipments` block's event types, for its manifest and `onBlockEvent`. */
export const shipmentsEvents: Events<ShipmentsEvents> = defineEvents({
  "shipment.created": event<ShipmentCreatedEventData>({ public: true }),
  "shipment.labeled": event<ShipmentLabeledEventData>({ public: true }),
  "shipment.status_changed": event<ShipmentStatusChangedEventData>({
    public: true,
  }),
  "shipment.cancelled": event<ShipmentCancelledEventData>({ public: true }),
  "shipment.proof_recorded": event<ShipmentProofRecordedEventData>({
    public: true,
  }),
  "shipment.return_received": event<ShipmentReturnReceivedEventData>({
    public: true,
  }),
});
