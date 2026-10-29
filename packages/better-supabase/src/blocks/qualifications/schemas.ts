import type { EntitySchema } from "../entity-schema.ts";

import { entitySchema } from "../entity-schema.ts";

/** The input of `saveType`. */
export interface QualificationTypeInput {
  readonly key: string;
  readonly name: string;
  readonly description?: string;
  readonly holderTypes?: readonly string[];
  readonly validForMonths?: number;
  readonly evidenceRequired?: boolean;
}

export const qualificationTypeInputSchema: EntitySchema<QualificationTypeInput> =
  entitySchema<QualificationTypeInput>({
    title: "QualificationTypeInput",
    fields: {
      key: { kind: "string", minLength: 1, maxLength: 41 },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true },
      holderTypes: { kind: "string", optional: true, array: true },
      validForMonths: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 240,
      },
      evidenceRequired: { kind: "boolean", optional: true },
    },
  });
