import type { BlockOf } from "../define-block.ts";
import type { ShipmentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { shipmentsEvents } from "./events.ts";
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
  events: shipmentsEvents,
  schemas: {
    shipment: { input: shipmentInputSchema },
    shipment_tracking_event: { input: trackingEventInputSchema },
  },
  create: createShipments,
  record: shipmentsBinding,
  category: "commerce",
  entities: {
    shipment: { mutability: "state-machine", emits: { create: true } },
    shipment_package: { mutability: "read-only" },
    shipment_tracking_event: { mutability: "read-only" },
    shipment_line: { mutability: "read-only" },
  },
  description:
    "Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.",
  recipes: ["shipment-tracking"],
  providers: [
    {
      option: "carriers",
      type: "ShippingProvider",
      from: "better-supabase/blocks/shipments",
      required: false,
      description:
        "Quotes, labels and tracks shipments; without one, shipments are recorded by hand.",
      example: "[yourCarrier]",
    },
  ],
});
