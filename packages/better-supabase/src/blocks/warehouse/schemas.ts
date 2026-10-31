import type { EntitySchema } from "../entity-schema.ts";
import type {
  CountPlanInput,
  PickListInput,
  PickRecord,
  PickWaveInput,
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
