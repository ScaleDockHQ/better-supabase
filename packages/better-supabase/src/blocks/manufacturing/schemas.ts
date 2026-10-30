import type { EntitySchema } from "../entity-schema.ts";
import type {
  BomInput,
  ProductionOrderInput,
  WorkCenterInput,
} from "./manufacturing.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveBom` takes, with the bounds the SQL checks. */
export const bomInputSchema: EntitySchema<BomInput> = entitySchema<BomInput>({
  title: "BomInput",
  fields: {
    quantity: {
      kind: "number",
      optional: true,
      description: "How many units the components make. Default 1.",
    },
    components: {
      kind: "json",
      array: true,
      description:
        "At least one: `{ variantId, quantity, scrapBps, operation }`.",
    },
    operations: {
      kind: "json",
      array: true,
      optional: true,
      description:
        "The routing: `{ sequence, workCenterId, title, setupMinutes, runMinutesPerUnit, instructionsNodeId, inspectionTemplate }`.",
    },
    note: { kind: "string", optional: true, maxLength: 10_000 },
  },
});

/** What `saveWorkCenter` takes. */
export const workCenterInputSchema: EntitySchema<WorkCenterInput> =
  entitySchema<WorkCenterInput>({
    title: "WorkCenterInput",
    fields: {
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      assetId: { kind: "uuid", optional: true, nullable: true },
      hoursPerDay: { kind: "number", optional: true },
      costRate: {
        kind: "json",
        optional: true,
        description: "Per hour, as `Money`.",
      },
      archived: { kind: "boolean", optional: true },
    },
  });

/** What `createOrder` takes. */
export const productionOrderInputSchema: EntitySchema<ProductionOrderInput> =
  entitySchema<ProductionOrderInput>({
    title: "ProductionOrderInput",
    fields: {
      variantId: { kind: "uuid" },
      quantity: { kind: "number", description: "More than zero." },
      locationId: { kind: "uuid", optional: true },
      dueOn: { kind: "plainDate", optional: true },
      bomId: { kind: "uuid", optional: true },
      note: { kind: "string", optional: true, maxLength: 10_000 },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });
