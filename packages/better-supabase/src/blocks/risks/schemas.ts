import type { EntitySchema } from "../entity-schema.ts";
import type {
  RiskAssessmentInput,
  RiskInput,
  RiskMatrixInput,
} from "./risks.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveMatrix` takes. */
export const riskMatrixInputSchema: EntitySchema<RiskMatrixInput> =
  entitySchema<RiskMatrixInput>({
    title: "RiskMatrixInput",
    fields: {
      key: { kind: "string", minLength: 1, maxLength: 64 },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      likelihoodLevels: {
        kind: "json",
        array: true,
        description: "2 to 10 levels `{ value, label }`, values 1 to n.",
      },
      impactLevels: {
        kind: "json",
        array: true,
        description: "2 to 10 levels `{ value, label }`, values 1 to n.",
      },
      bands: {
        kind: "json",
        array: true,
        description:
          "Bands `{ key, label, min, max }` that cover every score without gaps.",
      },
      scoring: { kind: "enum", optional: true, values: ["product", "sum"] },
      isDefault: { kind: "boolean", optional: true },
      matrixId: { kind: "uuid", optional: true },
    },
  });

/** What `create` takes, with the bounds the SQL checks. */
export const riskInputSchema: EntitySchema<RiskInput> = entitySchema<RiskInput>(
  {
    title: "RiskInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 300 },
      category: {
        kind: "string",
        minLength: 1,
        maxLength: 64,
        description: "One of `options.categories`.",
      },
      description: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      cause: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      consequence: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      ownerId: { kind: "uuid", optional: true, nullable: true },
      matrixId: { kind: "uuid", optional: true },
      reviewIntervalMonths: {
        kind: "integer",
        optional: true,
        nullable: true,
        minimum: 1,
        maximum: 120,
      },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  },
);

/** What `assess` takes. */
export const riskAssessmentInputSchema: EntitySchema<RiskAssessmentInput> =
  entitySchema<RiskAssessmentInput>({
    title: "RiskAssessmentInput",
    fields: {
      inherent: {
        kind: "json",
        description: "`{ likelihood, impact }` before controls.",
      },
      residual: {
        kind: "json",
        description: "`{ likelihood, impact }` after controls.",
      },
      rationale: { kind: "string", optional: true, maxLength: 10_000 },
    },
  });
