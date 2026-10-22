import type { EntitySchema } from "../entity-schema.ts";
import type { SequenceEnrollInput, SequenceInput } from "./sequences.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `upsert` takes, with the bounds the SQL checks. */
export const sequenceInputSchema: EntitySchema<SequenceInput> =
  entitySchema<SequenceInput>({
    title: "SequenceInput",
    fields: {
      id: { kind: "uuid", optional: true },
      key: { kind: "string", optional: true, minLength: 1, maxLength: 63 },
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      description: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 2000,
      },
      status: {
        kind: "enum",
        values: ["draft", "active", "paused", "archived"],
        optional: true,
      },
      exitOnReply: { kind: "boolean", optional: true },
      accountId: { kind: "uuid", optional: true, nullable: true },
      steps: {
        kind: "json",
        optional: true,
        array: true,
        description:
          "Up to 50 email, task and wait steps, each with a unique id.",
      },
    },
  });

/** What `enroll` takes, with the bounds the SQL checks. */
export const sequenceEnrollInputSchema: EntitySchema<SequenceEnrollInput> =
  entitySchema<SequenceEnrollInput>({
    title: "SequenceEnrollInput",
    fields: {
      address: { kind: "string", optional: true, minLength: 3, maxLength: 320 },
      name: { kind: "string", optional: true, maxLength: 200 },
      accountId: { kind: "uuid", optional: true },
      variables: {
        kind: "json",
        optional: true,
        description: "Values for the steps' {{key}} placeholders.",
      },
    },
  });
