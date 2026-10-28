import type { EntitySchema } from "../entity-schema.ts";

import { entitySchema } from "../entity-schema.ts";

/** The input of `assign`. */
export interface AcknowledgementAssignmentInput {
  readonly dueInDays?: number;
}

export const acknowledgementAssignmentInputSchema: EntitySchema<
  AcknowledgementAssignmentInput
> = entitySchema<AcknowledgementAssignmentInput>({
  title: "AcknowledgementAssignmentInput",
  fields: {
    dueInDays: {
      kind: "number",
      optional: true,
      minimum: 1,
      maximum: 365,
      description: "Days after the version is created that it is due.",
    },
  },
});
