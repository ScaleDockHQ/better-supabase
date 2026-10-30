import type { EntitySchema } from "../entity-schema.ts";
import type { MedicationInput, MedicationOrderInput } from "./medications.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveMedication` takes. */
export const medicationInputSchema: EntitySchema<MedicationInput> =
  entitySchema<MedicationInput>({
    title: "MedicationInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 300 },
      unit: { kind: "string", minLength: 1, maxLength: 50 },
      codeSystem: {
        kind: "enum",
        optional: true,
        values: ["gtin", "hpk", "atc", "rxnorm", "custom"],
      },
      code: { kind: "string", optional: true, maxLength: 100 },
      form: { kind: "string", optional: true, maxLength: 100 },
      strength: { kind: "string", optional: true, maxLength: 100 },
      highRisk: { kind: "boolean", optional: true },
      medicationId: { kind: "uuid", optional: true },
    },
  });

/** What `prescribe` takes. */
export const medicationOrderInputSchema: EntitySchema<MedicationOrderInput> =
  entitySchema<MedicationOrderInput>({
    title: "MedicationOrderInput",
    fields: {
      dose: { kind: "number", minimum: 0 },
      doseUnit: { kind: "string", optional: true, maxLength: 50 },
      route: { kind: "string", optional: true, maxLength: 100 },
      schedule: {
        kind: "json",
        optional: true,
        description:
          "When the doses fall: { times: [HH:MM] } or { everyHours, startTime }, with optional ISO weekdays.",
      },
      asNeeded: { kind: "boolean", optional: true },
      asNeededReason: { kind: "string", optional: true, maxLength: 500 },
      maxPerDay: { kind: "number", optional: true, minimum: 0 },
      startsOn: { kind: "plainDate", optional: true },
      endsOn: { kind: "plainDate", optional: true },
      prescriber: { kind: "string", optional: true, maxLength: 300 },
      requiresDoubleCheck: { kind: "boolean", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });
