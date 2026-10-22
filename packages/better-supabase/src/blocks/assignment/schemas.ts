import type { EntitySchema } from "../entity-schema.ts";
import type { AssignmentQueueInput } from "./assignment.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveQueue` takes. The SQL checks the territory against the rule fields. */
export const assignmentQueueInputSchema: EntitySchema<AssignmentQueueInput> =
  entitySchema<AssignmentQueueInput>({
    title: "AssignmentQueueInput",
    fields: {
      id: { kind: "uuid", optional: true },
      name: { kind: "string", minLength: 1, maxLength: 200, optional: true },
      subjectType: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        optional: true,
      },
      strategy: {
        kind: "enum",
        values: ["round_robin", "weighted"],
        optional: true,
      },
      conditions: {
        kind: "json",
        optional: true,
        description: "The territory, a FilterQuery over the rule fields.",
      },
      rank: { kind: "integer", optional: true },
      enabled: { kind: "boolean", optional: true },
    },
  });
