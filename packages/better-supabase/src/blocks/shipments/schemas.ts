import type { EntitySchema } from "../entity-schema.ts";
import type { CarrierTrackingEvent } from "./carrier.ts";
import type { ShipmentInput } from "./shipments.ts";

import { entitySchema } from "../entity-schema.ts";
import { TRACKING_STATUSES } from "./statuses.ts";

const address = {
  kind: "json",
  description:
    "`{ line1, city, country, name?, company?, line2?, postalCode?, state?, phone?, email? }`, with a two-letter country.",
} as const;

/** What `create` takes, with the bounds the SQL checks. */
export const shipmentInputSchema: EntitySchema<ShipmentInput> =
  entitySchema<ShipmentInput>({
    title: "ShipmentInput",
    fields: {
      from: address,
      to: address,
      packages: {
        kind: "json",
        array: true,
        description:
          "1 to 50 `{ weightGrams, lengthMm?, widthMm?, heightMm?, reference? }`, in whole grams and millimeters.",
      },
      reference: {
        kind: "string",
        optional: true,
        minLength: 1,
        maxLength: 100,
      },
      fromLocationId: { kind: "uuid", optional: true },
      subject: {
        kind: "json",
        optional: true,
        description: "The record it ships for: `{ type, id }`.",
      },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });

/** What the section's `create` write takes: the record is the subject. */
export type ShipmentSectionInput = Omit<ShipmentInput, "subject" | "fields">;

export const shipmentSectionInputSchema: EntitySchema<ShipmentSectionInput> =
  entitySchema<ShipmentSectionInput>({
    title: "ShipmentSectionInput",
    fields: {
      from: address,
      to: address,
      packages: {
        kind: "json",
        array: true,
        description:
          "1 to 50 `{ weightGrams, lengthMm?, widthMm?, heightMm?, reference? }`.",
      },
      reference: {
        kind: "string",
        optional: true,
        minLength: 1,
        maxLength: 100,
      },
      fromLocationId: { kind: "uuid", optional: true },
    },
  });

/** One event `recordTracking` takes. */
export const trackingEventInputSchema: EntitySchema<CarrierTrackingEvent> =
  entitySchema<CarrierTrackingEvent>({
    title: "TrackingEventInput",
    fields: {
      id: { kind: "string", minLength: 1, maxLength: 200 },
      status: { kind: "enum", values: TRACKING_STATUSES },
      occurredAt: { kind: "instant" },
      description: { kind: "string", optional: true, maxLength: 1000 },
      location: { kind: "string", optional: true, maxLength: 200 },
    },
  });
