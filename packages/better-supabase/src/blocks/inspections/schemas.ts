import type { EntitySchema } from "../entity-schema.ts";

import { entitySchema } from "../entity-schema.ts";

/** The input of `schedule`. */
export interface InspectionInput {
  readonly title: string;
  readonly kind?: string;
  readonly scope?: string;
  readonly criteria?: string;
  readonly programId?: string;
  readonly leadId?: string;
  readonly plannedStart?: Temporal.PlainDate;
  readonly plannedEnd?: Temporal.PlainDate;
}

export const inspectionInputSchema: EntitySchema<InspectionInput> =
  entitySchema<InspectionInput>({
    title: "InspectionInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      kind: { kind: "string", optional: true },
      scope: { kind: "string", optional: true },
      criteria: { kind: "string", optional: true },
      programId: { kind: "uuid", optional: true },
      leadId: { kind: "uuid", optional: true },
      plannedStart: { kind: "plainDate", optional: true },
      plannedEnd: { kind: "plainDate", optional: true },
    },
  });
