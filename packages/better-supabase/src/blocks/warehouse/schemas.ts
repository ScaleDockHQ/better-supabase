import type { EntitySchema } from "../entity-schema.ts";
import type {
  BinSlotInput,
  CountPlanInput,
  PickListInput,
  PickRecord,
  PickWaveInput,
  PutawayRequest,
  PutawayRuleInput,
  SlottingOptions,
} from "./warehouse.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `createPickWave` takes. */
export const pickWaveInputSchema: EntitySchema<PickWaveInput> =
  entitySchema<PickWaveInput>({
    title: "PickWaveInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      locationId: { kind: "uuid" },
    },
  });

/** What `createPickList` takes. */
export const pickListInputSchema: EntitySchema<PickListInput> =
  entitySchema<PickListInput>({
    title: "PickListInput",
    fields: {
      locationId: { kind: "uuid" },
      documentType: { kind: "string", minLength: 1, maxLength: 63 },
      documentId: { kind: "string", minLength: 1, maxLength: 200 },
      waveId: { kind: "uuid", optional: true },
      assigneeId: { kind: "uuid", optional: true },
    },
  });

/** What `recordPick` takes. */
export const pickRecordSchema: EntitySchema<PickRecord> =
  entitySchema<PickRecord>({
    title: "PickRecord",
    fields: {
      quantity: { kind: "number", description: "More than zero." },
      binId: { kind: "uuid", optional: true },
      lotId: { kind: "uuid", optional: true },
      serials: { kind: "string", array: true, optional: true },
    },
  });

/** What `createCountPlan` takes. */
export const countPlanInputSchema: EntitySchema<CountPlanInput> =
  entitySchema<CountPlanInput>({
    title: "CountPlanInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      locationId: { kind: "uuid" },
      everyDays: { kind: "integer", minimum: 1, maximum: 3660 },
      variantIds: { kind: "uuid", array: true, optional: true },
      varianceLimitPct: { kind: "number", optional: true, minimum: 0 },
      startsOn: { kind: "string", optional: true },
    },
  });

/** What `savePutawayRule` takes. */
export const putawayRuleInputSchema: EntitySchema<PutawayRuleInput> =
  entitySchema<PutawayRuleInput>({
    title: "PutawayRuleInput",
    fields: {
      id: { kind: "uuid", optional: true },
      locationId: { kind: "uuid", optional: true },
      binId: { kind: "uuid", optional: true },
      variantId: { kind: "uuid", optional: true },
      priority: {
        kind: "integer",
        optional: true,
        minimum: 0,
        maximum: 10_000,
      },
      maxQuantity: { kind: "number", optional: true },
      active: { kind: "boolean", optional: true },
    },
  });

/** What `saveBinSlot` takes. */
export const binSlotInputSchema: EntitySchema<BinSlotInput> =
  entitySchema<BinSlotInput>({
    title: "BinSlotInput",
    fields: {
      binId: { kind: "uuid" },
      walkRank: {
        kind: "integer",
        optional: true,
        minimum: 0,
        maximum: 100_000,
      },
      capacity: { kind: "number", optional: true },
    },
  });

/** What `suggestPutaway` takes. */
export const putawayRequestSchema: EntitySchema<PutawayRequest> =
  entitySchema<PutawayRequest>({
    title: "PutawayRequest",
    fields: {
      locationId: { kind: "uuid" },
      variantId: { kind: "uuid" },
      quantity: { kind: "number", description: "More than zero." },
    },
  });

/** What `suggestSlotting` takes. */
export const slottingOptionsSchema: EntitySchema<SlottingOptions> =
  entitySchema<SlottingOptions>({
    title: "SlottingOptions",
    fields: {
      locationId: { kind: "uuid" },
      days: { kind: "integer", optional: true, minimum: 1, maximum: 365 },
      limit: { kind: "integer", optional: true, minimum: 1, maximum: 500 },
    },
  });
