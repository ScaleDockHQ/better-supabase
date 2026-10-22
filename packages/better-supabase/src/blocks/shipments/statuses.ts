export const LABEL_FORMATS = ["pdf", "png", "zpl"] as const;

export type LabelFormat = (typeof LABEL_FORMATS)[number];

/** The stages a carrier reports, in the order a parcel goes through them. */
export const TRACKING_STATUSES = [
  "label_created",
  "in_transit",
  "out_for_delivery",
  "delivered",
  "exception",
  "returned",
] as const;

export type TrackingStatus = (typeof TRACKING_STATUSES)[number];

/** Where a shipment is: a draft, then the status of its latest tracking event. */
export const SHIPMENT_STATUSES = [
  "draft",
  "label_created",
  "in_transit",
  "out_for_delivery",
  "delivered",
  "exception",
  "returned",
  "cancelled",
] as const;

export type ShipmentStatus = (typeof SHIPMENT_STATUSES)[number];
