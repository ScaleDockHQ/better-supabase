import type { EntitySchema } from "../entity-schema.ts";
import type { CaseActionInput, CaseInput, CaseKindInput } from "./cases.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveKind` takes. */
export const caseKindInputSchema: EntitySchema<CaseKindInput> =
  entitySchema<CaseKindInput>({
    title: "CaseKindInput",
    fields: {
      key: { kind: "string", minLength: 1, maxLength: 41 },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      prefix: {
        kind: "string",
        minLength: 1,
        maxLength: 6,
        description: "1 to 6 capital letters that start the case numbers.",
      },
      investigationFormId: { kind: "uuid", optional: true, nullable: true },
      effectivenessFormId: { kind: "uuid", optional: true, nullable: true },
      effectivenessAfterDays: {
        kind: "integer",
        optional: true,
        nullable: true,
        minimum: 1,
        maximum: 365,
      },
      requiresRootCause: { kind: "boolean", optional: true },
      requiresActions: { kind: "boolean", optional: true },
      requiresEffectiveness: { kind: "boolean", optional: true },
      requiresRevisions: { kind: "boolean", optional: true },
      kindId: { kind: "uuid", optional: true },
    },
  });

/** What `open` takes, with the bounds the SQL checks. */
export const caseInputSchema: EntitySchema<CaseInput> = entitySchema<CaseInput>(
  {
    title: "CaseInput",
    fields: {
      kind: {
        kind: "string",
        minLength: 1,
        maxLength: 41,
        description: "The key of one of the organization's case kinds.",
      },
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 20_000,
      },
      severity: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 41,
        description: "One of `options.severities`.",
      },
      source: {
        kind: "string",
        optional: true,
        maxLength: 41,
        description: "One of `options.sources`. Default `internal`.",
      },
      occurredAt: { kind: "instant", optional: true, nullable: true },
      ownerId: { kind: "uuid", optional: true, nullable: true },
      dueOn: { kind: "plainDate", optional: true, nullable: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  },
);

/** What `createAction` takes. */
export const caseActionInputSchema: EntitySchema<CaseActionInput> =
  entitySchema<CaseActionInput>({
    title: "CaseActionInput",
    fields: {
      type: {
        kind: "enum",
        values: [
          "containment",
          "correction",
          "corrective",
          "preventive",
          "improvement",
        ],
      },
      title: { kind: "string", minLength: 1, maxLength: 500 },
      assigneeId: { kind: "uuid", optional: true, nullable: true },
      dueAt: { kind: "instant", optional: true, nullable: true },
      required: { kind: "boolean", optional: true },
    },
  });
