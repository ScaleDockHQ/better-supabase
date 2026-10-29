import type { EntitySchema } from "../entity-schema.ts";
import type {
  QualificationGrantInput,
  QualificationTypeInput,
} from "./qualifications.ts";

import { entitySchema } from "../entity-schema.ts";

const HOLDER_TYPES = ["member", "company", "asset"] as const;

/** What `saveType` takes. */
export const qualificationTypeInputSchema: EntitySchema<QualificationTypeInput> =
  entitySchema<QualificationTypeInput>({
    title: "QualificationTypeInput",
    fields: {
      key: { kind: "string", minLength: 1, maxLength: 64 },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      holderTypes: { kind: "enum", values: HOLDER_TYPES, array: true },
      validForMonths: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 240,
      },
      evidenceRequired: { kind: "boolean", optional: true },
      courseId: { kind: "uuid", optional: true },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      typeId: { kind: "uuid", optional: true },
    },
  });

/** What `grant` takes. */
export const qualificationGrantInputSchema: EntitySchema<QualificationGrantInput> =
  entitySchema<QualificationGrantInput>({
    title: "QualificationGrantInput",
    fields: {
      typeKey: { kind: "string", minLength: 1, maxLength: 64 },
      holderType: { kind: "enum", values: HOLDER_TYPES },
      holderId: { kind: "string", minLength: 1, maxLength: 200 },
      grantedOn: { kind: "plainDate", optional: true },
      evidenceAttachmentId: { kind: "uuid", optional: true },
      evidenceNote: { kind: "string", optional: true, maxLength: 10_000 },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });
