import type { BlockOf } from "../define-block.ts";
import type { ShipmentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { shipmentsEvents } from "./events.ts";
import { shipmentsSqlOptions } from "./options.ts";
import { shipmentsBinding } from "./record-binding.ts";
import { shipmentInputSchema, trackingEventInputSchema } from "./schemas.ts";
import { createShipments } from "./shipments.ts";

/** The `shipments` block's manifest (ADR 0029). */
export const shipmentsBlock: BlockOf<
  "shipments",
  typeof createShipments,
  ShipmentsEvents,
  Record<never, never>,
  never,
  typeof shipmentsBinding
> = defineBlock({
  name: "shipments",
  sql: ["shipments"],
  options: { shipments: shipmentsSqlOptions },
  events: shipmentsEvents,
  schemas: {
    shipment: { input: shipmentInputSchema },
    shipment_tracking_event: { input: trackingEventInputSchema },
  },
  create: createShipments,
  record: shipmentsBinding,
  category: "commerce",
  recipes: ["shipment-tracking"],
});
