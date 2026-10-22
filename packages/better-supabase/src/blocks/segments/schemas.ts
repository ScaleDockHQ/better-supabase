import type { EntitySchema } from "../entity-schema.ts";
import type { SegmentInput } from "./segments.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `upsert` takes. The SQL checks the conditions against the rule fields. */
export const segmentInputSchema: EntitySchema<SegmentInput> =
  entitySchema<SegmentInput>({
    title: "SegmentInput",
    fields: {
      id: { kind: "uuid", optional: true },
      subjectType: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        optional: true,
      },
      name: { kind: "string", minLength: 1, maxLength: 200, optional: true },
      description: { kind: "string", maxLength: 2000, optional: true },
      conditions: {
        kind: "json",
        optional: true,
        description: "A FilterQuery over the subject type's rule fields.",
      },
    },
  });
