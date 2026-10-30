import type { EntitySchema } from "../entity-schema.ts";
import type {
  ShiftAvailabilityInput,
  ShiftInput,
  ShiftTemplateInput,
} from "./shifts.ts";

import { entitySchema } from "../entity-schema.ts";

const TIME = "A time of day, HH:MM.";

/** What `saveTemplate` takes. */
export const shiftTemplateInputSchema: EntitySchema<ShiftTemplateInput> =
  entitySchema<ShiftTemplateInput>({
    title: "ShiftTemplateInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      startsTime: {
        kind: "string",
        minLength: 5,
        maxLength: 8,
        description: TIME,
      },
      endsTime: {
        kind: "string",
        minLength: 5,
        maxLength: 8,
        description: TIME,
      },
      weekdays: {
        kind: "integer",
        optional: true,
        array: true,
        minimum: 1,
        maximum: 7,
      },
      teamId: { kind: "string", optional: true, maxLength: 64 },
      locationId: { kind: "uuid", optional: true },
      breakMinutes: { kind: "integer", optional: true, minimum: 0 },
      headcount: { kind: "integer", optional: true, minimum: 1, maximum: 1000 },
      requiredQualifications: { kind: "string", optional: true, array: true },
      templateId: { kind: "uuid", optional: true },
    },
  });

/** What `upsert` takes. */
export const shiftInputSchema: EntitySchema<ShiftInput> =
  entitySchema<ShiftInput>({
    title: "ShiftInput",
    fields: {
      startsAt: { kind: "instant" },
      endsAt: { kind: "instant" },
      teamId: { kind: "string", optional: true, maxLength: 64 },
      locationId: { kind: "uuid", optional: true },
      breakMinutes: { kind: "integer", optional: true, minimum: 0 },
      headcount: { kind: "integer", optional: true, minimum: 1, maximum: 1000 },
      requiredQualifications: { kind: "string", optional: true, array: true },
      note: { kind: "string", optional: true, maxLength: 10_000 },
      shiftId: { kind: "uuid", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });

/** What `setAvailability` takes. */
export const shiftAvailabilityInputSchema: EntitySchema<ShiftAvailabilityInput> =
  entitySchema<ShiftAvailabilityInput>({
    title: "ShiftAvailabilityInput",
    fields: {
      onDate: { kind: "plainDate" },
      kind: { kind: "enum", values: ["available", "unavailable", "preferred"] },
      fromTime: {
        kind: "string",
        optional: true,
        minLength: 5,
        maxLength: 8,
        description: TIME,
      },
      untilTime: {
        kind: "string",
        optional: true,
        minLength: 5,
        maxLength: 8,
        description: TIME,
      },
      note: { kind: "string", optional: true, maxLength: 10_000 },
      userId: { kind: "uuid", optional: true },
    },
  });
