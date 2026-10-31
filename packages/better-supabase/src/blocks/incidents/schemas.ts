import type { EntitySchema } from "../entity-schema.ts";
import type {
  IncidentChanges,
  IncidentInput,
  PostmortemInput,
  StatusComponentInput,
  StatusPageInput,
} from "./incidents.ts";

import { entitySchema } from "../entity-schema.ts";

const SEVERITIES = ["sev1", "sev2", "sev3", "sev4"] as const;

const fields = {
  kind: "json",
  optional: true,
  description: "The extra columns, keyed by database name.",
} as const;

/** What `open` takes. */
export const incidentInputSchema: EntitySchema<IncidentInput> =
  entitySchema<IncidentInput>({
    title: "IncidentInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      severity: { kind: "enum", values: SEVERITIES, optional: true },
      public: { kind: "boolean", optional: true },
      commanderId: { kind: "uuid", optional: true },
      message: { kind: "string", optional: true, maxLength: 10_000 },
      impacts: {
        kind: "json",
        optional: true,
        array: true,
        description: "The affected components: `[{ componentId, impact }]`.",
      },
      fields,
    },
  });

/** What `update` takes. */
export const incidentChangesSchema: EntitySchema<IncidentChanges> =
  entitySchema<IncidentChanges>({
    title: "IncidentChanges",
    fields: {
      title: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 10_000 },
      severity: { kind: "enum", values: SEVERITIES, optional: true },
      public: { kind: "boolean", optional: true },
      commanderId: { kind: "uuid", optional: true },
      fields,
    },
  });

/** What `saveComponent` takes. */
export const statusComponentInputSchema: EntitySchema<StatusComponentInput> =
  entitySchema<StatusComponentInput>({
    title: "StatusComponentInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 2000 },
      group: { kind: "string", optional: true, maxLength: 200 },
      public: { kind: "boolean", optional: true },
      position: { kind: "integer", optional: true },
      componentId: { kind: "uuid", optional: true },
    },
  });

/** What `savePostmortem` takes. */
export const postmortemInputSchema: EntitySchema<PostmortemInput> =
  entitySchema<PostmortemInput>({
    title: "PostmortemInput",
    fields: {
      summary: { kind: "string", optional: true, maxLength: 10_000 },
      impact: { kind: "string", optional: true, maxLength: 10_000 },
      rootCause: { kind: "string", optional: true, maxLength: 10_000 },
      resolution: { kind: "string", optional: true, maxLength: 10_000 },
    },
  });

/** What `saveStatusPage` takes. */
export const statusPageInputSchema: EntitySchema<StatusPageInput> =
  entitySchema<StatusPageInput>({
    title: "StatusPageInput",
    fields: {
      slug: { kind: "string", minLength: 2, maxLength: 63 },
      title: { kind: "string", minLength: 1, maxLength: 200 },
      description: { kind: "string", optional: true, maxLength: 2000 },
      published: { kind: "boolean", optional: true },
    },
  });
