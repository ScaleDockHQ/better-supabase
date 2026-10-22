import type { EntitySchema, EntitySchemaSpec } from "../entity-schema.ts";
import type { EngagementInput } from "./activities.ts";

import { entitySchema } from "../entity-schema.ts";

type EngagementLog = EngagementInput & {
  readonly type: string;
  readonly title: string;
};

const CHANGE: EntitySchemaSpec<EngagementInput>["fields"] = {
  type: { kind: "string", optional: true, minLength: 1 },
  title: { kind: "string", optional: true, minLength: 1, maxLength: 500 },
  body: { kind: "string", optional: true, nullable: true },
  outcome: { kind: "string", optional: true, nullable: true },
  ownerId: { kind: "uuid", optional: true, nullable: true },
  dueAt: { kind: "instant", optional: true, nullable: true },
  doneAt: { kind: "instant", optional: true, nullable: true },
  durationSeconds: {
    kind: "integer",
    optional: true,
    nullable: true,
    minimum: 0,
  },
  externalRef: { kind: "string", optional: true, nullable: true },
  fields: {
    kind: "json",
    optional: true,
    description: "Values for the extra columns, by column name.",
  },
};

/** What `log` takes: a type and a title, with the bounds the SQL checks. */
export const engagementInputSchema: EntitySchema<EngagementLog> =
  entitySchema<EngagementLog>({
    title: "EngagementInput",
    fields: {
      ...CHANGE,
      type: { kind: "string", minLength: 1 },
      title: { kind: "string", minLength: 1, maxLength: 500 },
    },
  });

/** What `update` takes: left out keeps the value, `null` clears it. */
export const engagementChangeSchema: EntitySchema<EngagementInput> =
  entitySchema<EngagementInput>({ title: "EngagementChange", fields: CHANGE });
