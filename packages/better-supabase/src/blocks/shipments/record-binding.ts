import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type { ShipmentSectionInput } from "./schemas.ts";
import type { Shipment, Shipments } from "./shipments.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";
import { shipmentSectionInputSchema } from "./schemas.ts";

/** The writes of the shipments binding. */
export type ShipmentsWrites = {
  /** Creates a draft shipment for the record, such as an order's parcel. */
  readonly create: RecordBindingWrite<
    Shipments,
    ShipmentSectionInput,
    Shipment
  >;
  /** Cancels one of the record's shipments that hasn't shipped. */
  readonly cancel: RecordBindingWrite<Shipments, RecordRowInput, Shipment>;
};

/** The shipments sent for a record, with their status and tracking. */
export const shipmentsBinding: RecordBinding<
  Shipments,
  readonly Shipment[],
  undefined,
  never,
  ShipmentsWrites
> = defineRecordBinding({
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
      input: recordRowInput,
      run: (client: Shipments, _subject, { id }: RecordRowInput) =>
        client.cancel(id),
    },
  },
});
