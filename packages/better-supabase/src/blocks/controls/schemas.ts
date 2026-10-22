import type { EntitySchema } from "../entity-schema.ts";
import type {
  ControlEvidenceInput,
  ControlFrameworkInput,
  ControlInput,
  EvidenceTaskInput,
  PolicyInput,
} from "./controls.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveFramework` takes. */
export const controlFrameworkInputSchema: EntitySchema<ControlFrameworkInput> =
  entitySchema<ControlFrameworkInput>({
    title: "ControlFrameworkInput",
    fields: {
      key: { kind: "string", minLength: 1, maxLength: 64 },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      version: { kind: "string", optional: true, maxLength: 64 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
    },
  });

/** What `saveControl` takes. */
export const controlInputSchema: EntitySchema<ControlInput> =
  entitySchema<ControlInput>({
    title: "ControlInput",
    fields: {
      frameworkId: { kind: "uuid" },
      code: { kind: "string", minLength: 1, maxLength: 64 },
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      ownerId: { kind: "uuid", optional: true },
      applicable: { kind: "boolean", optional: true },
      controlId: { kind: "uuid", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns, keyed by database name.",
      },
    },
  });

/** What `addEvidence` takes. */
export const controlEvidenceInputSchema: EntitySchema<ControlEvidenceInput> =
  entitySchema<ControlEvidenceInput>({
    title: "ControlEvidenceInput",
    fields: {
      attachmentId: { kind: "uuid", optional: true },
      note: { kind: "string", optional: true, maxLength: 10_000 },
      validUntil: { kind: "plainDate", optional: true },
      evidenceTaskId: { kind: "uuid", optional: true },
    },
  });

/** What `saveEvidenceTask` takes. */
export const evidenceTaskInputSchema: EntitySchema<EvidenceTaskInput> =
  entitySchema<EvidenceTaskInput>({
    title: "EvidenceTaskInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      intervalDays: { kind: "integer", minimum: 1, maximum: 3650 },
      dueOn: { kind: "plainDate", optional: true },
      assigneeId: { kind: "uuid", optional: true },
      active: { kind: "boolean", optional: true },
      evidenceTaskId: { kind: "uuid", optional: true },
    },
  });

/** What `savePolicy` takes. */
export const policyInputSchema: EntitySchema<PolicyInput> =
  entitySchema<PolicyInput>({
    title: "PolicyInput",
    fields: {
      key: { kind: "string", minLength: 1, maxLength: 64 },
      title: { kind: "string", minLength: 1, maxLength: 200 },
      ownerId: { kind: "uuid", optional: true },
      requiresAcknowledgement: { kind: "boolean", optional: true },
      policyId: { kind: "uuid", optional: true },
    },
  });
