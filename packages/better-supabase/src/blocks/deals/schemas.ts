import type { EntitySchema } from "../entity-schema.ts";
import type { DealChange, DealInput } from "./deals.ts";

import { entitySchema, moneyField } from "../entity-schema.ts";

const PARTY = {
  kind: "json",
  description: "A `{ type, id }` reference.",
} as const;

/** What `create` takes, with the bounds the SQL checks. */
export const dealInputSchema: EntitySchema<DealInput> = entitySchema<DealInput>(
  {
    title: "DealInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 300 },
      closeOn: { kind: "plainDate" },
      amount: { ...moneyField, optional: true },
      currency: { kind: "string", optional: true, minLength: 3, maxLength: 3 },
      company: { ...PARTY, optional: true },
      ownerId: { kind: "uuid", optional: true },
      motion: { kind: "string", optional: true },
      priority: { kind: "string", optional: true },
      product: { kind: "string", optional: true },
      seats: { kind: "integer", optional: true, minimum: 0 },
      existingAmount: { ...moneyField, optional: true },
      valuePeriod: {
        kind: "enum",
        values: ["one_time", "monthly", "annual"],
        optional: true,
      },
      pipelineId: { kind: "uuid", optional: true },
      stageId: { kind: "uuid", optional: true },
      probability: {
        kind: "integer",
        optional: true,
        minimum: 0,
        maximum: 100,
      },
      forecast: {
        kind: "enum",
        values: ["commit", "best_case", "pipeline", "omit"],
        optional: true,
      },
      nextStep: { kind: "string", optional: true },
      nextAt: { kind: "instant", optional: true },
      nextKind: { kind: "string", optional: true },
      flags: { kind: "string", optional: true, array: true },
      source: { kind: "string", optional: true },
      note: { kind: "string", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  },
);

/**
 * One edit `update` takes. `field` is a built-in field or an extra column, so
 * any name passes; the SQL rejects an unknown one.
 */
export const dealChangeSchema: EntitySchema<DealChange> =
  entitySchema<DealChange>({
    title: "DealChange",
    fields: {
      dealId: { kind: "uuid" },
      field: { kind: "string", minLength: 1 },
      value: { kind: "unknown", description: "`null` clears the field." },
    },
  });
