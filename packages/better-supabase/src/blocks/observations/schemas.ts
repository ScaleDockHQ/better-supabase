import type { EntitySchema } from "../entity-schema.ts";
import type {
  ObservationDefinitionInput,
  ObservationInput,
} from "./observations.ts";

import { entitySchema } from "../entity-schema.ts";

const VALUE_TYPES = [
  "number",
  "integer",
  "boolean",
  "code",
  "text",
  "components",
] as const;

const range = { kind: "number", optional: true } as const;

/** What `saveDefinition` takes. */
export const observationDefinitionInputSchema: EntitySchema<ObservationDefinitionInput> =
  entitySchema<ObservationDefinitionInput>({
    title: "ObservationDefinitionInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      valueType: { kind: "enum", values: VALUE_TYPES },
      unit: { kind: "string", optional: true, maxLength: 64 },
      codeSystem: { kind: "string", optional: true, maxLength: 200 },
      code: { kind: "string", optional: true, maxLength: 64 },
      components: {
        kind: "json",
        optional: true,
        array: true,
        description:
          "For `components`: each with a key, a title, a code, a unit, decimals, optional and ranges.",
      },
      decimals: { kind: "integer", optional: true, minimum: 0, maximum: 6 },
      validLow: range,
      validHigh: range,
      referenceLow: range,
      referenceHigh: range,
      criticalLow: range,
      criticalHigh: range,
    },
  });

/** What `record` takes. */
export const observationInputSchema: EntitySchema<ObservationInput> =
  entitySchema<ObservationInput>({
    title: "ObservationInput",
    fields: {
      subjectType: { kind: "string", minLength: 1, maxLength: 64 },
      subjectId: { kind: "string", minLength: 1, maxLength: 200 },
      definitionKey: { kind: "string", minLength: 1, maxLength: 63 },
      value: {
        kind: "unknown",
        description:
          "A number, true or false, a string, or the component values by key.",
      },
      observedAt: { kind: "instant", optional: true },
      method: { kind: "string", optional: true, maxLength: 200 },
      device: { kind: "string", optional: true, maxLength: 200 },
      note: { kind: "string", optional: true, maxLength: 4000 },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });
