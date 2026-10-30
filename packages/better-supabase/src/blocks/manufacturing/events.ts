import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `bom.activated`: a version became its variant's active bill of materials. */
export interface BomActivatedEventData {
  readonly organizationId: string;
  /** The bill of materials version. */
  readonly id: string;
  /** The variant it makes. */
  readonly variantId: string;
  readonly version: number;
  readonly status: string;
}

/** What every `production_order.*` event carries. */
export interface ProductionOrderEventData {
  readonly organizationId: string;
  /** The production order. */
  readonly id: string;
  /** Such as `MO-2026-0001`. */
  readonly number: string;
  /** The variant it makes. */
  readonly variantId: string;
  /** The planned quantity, as decimal text. */
  readonly quantity: string;
  /** Its status after the change. */
  readonly status: string;
}

/** `production_order.completed`. */
export interface ProductionOrderCompletedEventData extends ProductionOrderEventData {
  /** As decimal text. */
  readonly producedQuantity: string;
  /** As decimal text. */
  readonly scrapQuantity: string;
  /** The lot the output went into, for a lot-tracked variant. */
  readonly outputLotId: string | null;
}

/** `production_order.cancelled`. */
export interface ProductionOrderCancelledEventData extends ProductionOrderEventData {
  readonly reason: string | null;
}

/** The events of the `manufacturing` block: type to data. */
export type ManufacturingEvents = {
  readonly "bom.activated": BomActivatedEventData;
  readonly "production_order.released": ProductionOrderEventData;
  readonly "production_order.completed": ProductionOrderCompletedEventData;
  readonly "production_order.cancelled": ProductionOrderCancelledEventData;
};

/** The `manufacturing` block's event types, for its manifest and `onBlockEvent`. */
export const manufacturingEvents: Events<ManufacturingEvents> = defineEvents({
  "bom.activated": event<BomActivatedEventData>(),
  "production_order.released": event<ProductionOrderEventData>(),
  "production_order.completed": event<ProductionOrderCompletedEventData>(),
  "production_order.cancelled": event<ProductionOrderCancelledEventData>(),
});
