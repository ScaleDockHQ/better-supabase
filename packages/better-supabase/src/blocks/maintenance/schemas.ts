import type { EntitySchema } from "../entity-schema.ts";
import type {
  MaintenanceCalibrationInput,
  MaintenancePlanInput,
} from "./maintenance.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `createPlan` takes, with the bounds the SQL checks. */
export const maintenancePlanInputSchema: EntitySchema<MaintenancePlanInput> =
  entitySchema<MaintenancePlanInput>({
    title: "MaintenancePlanInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      kind: { kind: "enum", values: ["time", "meter"] },
      everyDays: {
        kind: "integer",
        optional: true,
        minimum: 1,
        description: "A time plan falls due this many days after the last one.",
      },
      meterId: { kind: "uuid", optional: true },
      everyValue: {
        kind: "string",
        optional: true,
        description:
          "A meter plan falls due this many units after the last one.",
      },
      assetId: { kind: "uuid", optional: true, nullable: true },
      priority: {
        kind: "enum",
        optional: true,
        values: ["low", "normal", "high", "urgent"],
      },
      parts: {
        kind: "json",
        array: true,
        optional: true,
        description: "The spare parts: `{ name, quantity, variantId }`.",
      },
    },
  });

/** What `recordCalibration` takes. */
export const maintenanceCalibrationInputSchema: EntitySchema<MaintenanceCalibrationInput> =
  entitySchema<MaintenanceCalibrationInput>({
    title: "MaintenanceCalibrationInput",
    fields: {
      assetId: { kind: "uuid", optional: true, nullable: true },
      instrument: { kind: "string", minLength: 1, maxLength: 200 },
      performedAt: { kind: "instant" },
      dueAt: { kind: "instant", description: "On or after performedAt." },
      result: { kind: "enum", values: ["pass", "fail", "adjusted"] },
      reference: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 200,
      },
    },
  });
