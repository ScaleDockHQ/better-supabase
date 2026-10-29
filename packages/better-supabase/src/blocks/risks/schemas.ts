import type { EntitySchema } from "../entity-schema.ts";

import { entitySchema } from "../entity-schema.ts";

/** The input of `create`. */
export interface RiskInput {
  readonly title: string;
  readonly description?: string;
  readonly category?: string;
  readonly cause?: string;
  readonly consequence?: string;
  readonly ownerId?: string;
  readonly matrixId?: string;
  readonly reviewIntervalMonths?: number;
}

export const riskInputSchema: EntitySchema<RiskInput> = entitySchema<RiskInput>({
  title: "RiskInput",
  fields: {
    title: { kind: "string", minLength: 1, maxLength: 200 },
    description: { kind: "string", optional: true },
    category: { kind: "string", optional: true },
    cause: { kind: "string", optional: true },
    consequence: { kind: "string", optional: true },
    ownerId: { kind: "uuid", optional: true },
    matrixId: { kind: "uuid", optional: true },
    reviewIntervalMonths: {
      kind: "integer",
      optional: true,
      minimum: 1,
      maximum: 120,
    },
  },
});
