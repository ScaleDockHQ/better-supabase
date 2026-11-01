import type { EntitySchema } from "../entity-schema.ts";
import type { CareRuleInput } from "./clinical-decision-support.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveRule` takes, with the bounds the SQL checks. */
export const careRuleInputSchema: EntitySchema<CareRuleInput> =
  entitySchema<CareRuleInput>({
    title: "CareRuleInput",
    fields: {
      id: {
        kind: "uuid",
        optional: true,
        description: "Set to change a rule; leave out to add one.",
      },
      kind: {
        kind: "enum",
        values: ["dose_range", "duplicate_therapy", "interaction"],
      },
      medicationIds: {
        kind: "uuid",
        array: true,
        description:
          "One medication for a dose range, two for an interaction, two or more for a therapy group.",
      },
      minDose: { kind: "number", optional: true, nullable: true },
      maxDose: { kind: "number", optional: true, nullable: true },
      maxPerDay: { kind: "number", optional: true, nullable: true },
      severity: {
        kind: "enum",
        optional: true,
        values: ["info", "warning", "critical"],
      },
      message: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 1000,
      },
      active: { kind: "boolean", optional: true },
    },
  });
