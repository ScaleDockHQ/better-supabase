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

/** Where a line's stock goes: out to the recipient, or back from them. */
export const LINE_DIRECTIONS = ["outbound", "return"] as const;

export type LineDirection = (typeof LINE_DIRECTIONS)[number];

/**
 * What happens to returned stock: `restock` puts it back in sellable stock,
 * `hold` puts it in a hold bin for inspection and `scrap` writes it off.
 */
export const RETURN_DISPOSITIONS = ["restock", "hold", "scrap"] as const;

export type ReturnDisposition = (typeof RETURN_DISPOSITIONS)[number];
