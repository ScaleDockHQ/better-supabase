export {
  createShipments,
  type Shipment,
  type ShipmentInput,
  type ShipmentLabelChoice,
  type ShipmentListOptions,
  type ShipmentPackage,
  type Shipments,
  type ShipmentsOptions,
  type TrackingEvent,
  type TrackingIngested,
  type TrackingRecorded,
} from "./shipments.ts";

export {
  flatRateCarrier,
  invalidShipmentRequest,
  shipmentCarrierOf,
  trackingUpdatesOf,
  type CarrierCallOptions,
  type CarrierCancelInput,
  type CarrierTrackingEvent,
  type CarrierTrackingUpdate,
  type FlatRateCarrierOptions,
  type FlatRateService,
  type ShipmentAddress,
  type ShipmentCarrier,
  type ShipmentLabel,
  type ShipmentLabelRequest,
  type ShipmentParcel,
  type ShipmentRate,
  type ShipmentRateRequest,
} from "./carrier.ts";

export {
  LABEL_FORMATS,
  SHIPMENT_STATUSES,
  TRACKING_STATUSES,
  type LabelFormat,
  type ShipmentStatus,
  type TrackingStatus,
} from "./statuses.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { shipmentsBlock } from "./manifest.ts";

export { shipmentsSqlOptions, type ShipmentsSqlOptions } from "./options.ts";

export { shipmentsSection, type ShipmentsWrites } from "./section.ts";

export {
  shipmentInputSchema,
  shipmentSectionInputSchema,
  trackingEventInputSchema,
  type ShipmentSectionInput,
} from "./schemas.ts";

export { shipmentsEvents } from "./events.ts";

export type {
  ShipmentCancelledEventData,
  ShipmentCreatedEventData,
  ShipmentLabeledEventData,
  ShipmentsEvents,
  ShipmentStatusChangedEventData,
} from "./events.ts";
