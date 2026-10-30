import type { CommerceEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `catalog` block: type to data. */
export type CatalogEvents = {
  readonly "product.created": CommerceEventData;
  readonly "product.updated": CommerceEventData;
  readonly "product.status_changed": CommerceEventData;
  readonly "product.deleted": CommerceEventData;
  readonly "product_variant.created": CommerceEventData;
  readonly "product_variant.updated": CommerceEventData;
  readonly "product_variant.deleted": CommerceEventData;
  readonly "catalog.price_changed": CommerceEventData;
  readonly "storefront.published": CommerceEventData;
  readonly "storefront.unpublished": CommerceEventData;
};

/** The `catalog` block's event types, for its manifest and `onBlockEvent`. */
export const catalogEvents: Events<CatalogEvents> = defineEvents({
  "product.created": event<CommerceEventData>(),
  "product.updated": event<CommerceEventData>(),
  "product.status_changed": event<CommerceEventData>(),
  "product.deleted": event<CommerceEventData>(),
  "product_variant.created": event<CommerceEventData>(),
  "product_variant.updated": event<CommerceEventData>(),
  "product_variant.deleted": event<CommerceEventData>(),
  "catalog.price_changed": event<CommerceEventData>(),
  "storefront.published": event<CommerceEventData>(),
  "storefront.unpublished": event<CommerceEventData>(),
});
