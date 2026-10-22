import type { BlockOf } from "../define-block.ts";
import type { ShipmentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { shipmentsEvents } from "./events.ts";
import { shipmentsSqlOptions } from "./options.ts";
import { shipmentInputSchema, trackingEventInputSchema } from "./schemas.ts";
import { shipmentsSection } from "./section.ts";
import { createShipments } from "./shipments.ts";

/** The `shipments` block's manifest (ADR 0029). */
export const shipmentsBlock: BlockOf<
  "shipments",
  typeof createShipments,
  ShipmentsEvents,
  Record<never, never>,
  never,
  { readonly shipments: typeof shipmentsSection }
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
  sections: { shipments: shipmentsSection },
  category: "commerce",
  recipes: ["shipment-tracking"],
});
