import type { Section, SectionRowInput, SectionWrite } from "../sections.ts";
import type { ShipmentSectionInput } from "./schemas.ts";
import type { Shipment, Shipments } from "./shipments.ts";

import { defineSection, sectionRowInput } from "../sections.ts";
import { shipmentSectionInputSchema } from "./schemas.ts";

/** The writes of the shipments section. */
export type ShipmentsWrites = {
  /** Creates a draft shipment for the record, such as an order's parcel. */
  readonly create: SectionWrite<Shipments, ShipmentSectionInput, Shipment>;
  /** Cancels one of the record's shipments that hasn't shipped. */
  readonly cancel: SectionWrite<Shipments, SectionRowInput, Shipment>;
};

/** The shipments sent for a record, with their status and tracking. */
export const shipmentsSection: Section<
  Shipments,
  readonly Shipment[],
  undefined,
  never,
  ShipmentsWrites
> = defineSection({
  permissions: { read: "read", write: "manage" },
  module: "shipments",
  load: (client: Shipments, subject) => client.list({ subject }),
  events: ["shipment.*"],
  writes: {
    create: {
      input: shipmentSectionInputSchema,
      run: (client: Shipments, subject, input: ShipmentSectionInput) =>
        client.create({ ...input, subject }),
    },
    cancel: {
      input: sectionRowInput,
      run: (client: Shipments, _subject, { id }: SectionRowInput) =>
        client.cancel(id),
    },
  },
});
