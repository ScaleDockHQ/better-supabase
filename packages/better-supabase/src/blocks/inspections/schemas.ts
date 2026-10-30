import type { EntitySchema } from "../entity-schema.ts";
import type {
  InspectionFindingInput,
  InspectionInput,
  InspectionProgramInput,
} from "./inspections.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveProgram` takes. */
export const inspectionProgramInputSchema: EntitySchema<InspectionProgramInput> =
  entitySchema<InspectionProgramInput>({
    title: "InspectionProgramInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      periodStart: { kind: "plainDate" },
      periodEnd: { kind: "plainDate", description: "On or after periodStart." },
      ownerId: { kind: "uuid", optional: true, nullable: true },
      notes: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      programId: { kind: "uuid", optional: true },
    },
  });

/** What `schedule` takes, with the bounds the SQL checks. */
export const inspectionInputSchema: EntitySchema<InspectionInput> =
  entitySchema<InspectionInput>({
    title: "InspectionInput",
    fields: {
      kind: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        description: "One of `options.kinds`.",
      },
      title: { kind: "string", minLength: 1, maxLength: 300 },
      programId: { kind: "uuid", optional: true, nullable: true },
      scope: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      criteria: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      auditee: {
        kind: "json",
        optional: true,
        nullable: true,
        description: "The subject audited: `{ type, id }`.",
      },
      leadId: { kind: "uuid", optional: true, nullable: true },
      plannedStart: { kind: "plainDate", optional: true, nullable: true },
      plannedEnd: { kind: "plainDate", optional: true, nullable: true },
      checklistFormId: { kind: "uuid", optional: true, nullable: true },
      members: {
        kind: "json",
        array: true,
        optional: true,
        description: "The team: `{ userId, role }`.",
      },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });

/** What `addFinding` takes. */
export const inspectionFindingInputSchema: EntitySchema<InspectionFindingInput> =
  entitySchema<InspectionFindingInput>({
    title: "InspectionFindingInput",
    fields: {
      type: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        description: "One of `options.findingTypes`.",
      },
      title: { kind: "string", minLength: 1, maxLength: 300 },
      description: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      clause: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 200,
      },
      controlId: { kind: "uuid", optional: true, nullable: true },
      evidence: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
    },
  });
