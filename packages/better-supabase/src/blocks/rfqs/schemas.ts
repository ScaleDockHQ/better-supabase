import type { EntitySchema } from "../entity-schema.ts";
import type { RfqInput } from "./rfqs.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `createRfq` takes, with the bounds the SQL checks. */
export const rfqInputSchema: EntitySchema<RfqInput> = entitySchema<RfqInput>({
  title: "RfqInput",
  fields: {
    title: { kind: "string", minLength: 1, maxLength: 200 },
    currency: {
      kind: "string",
      minLength: 3,
      maxLength: 3,
      description: "An ISO 4217 code such as EUR.",
    },
    dueAt: { kind: "instant", optional: true, nullable: true },
    notes: { kind: "string", optional: true, nullable: true, maxLength: 4000 },
  },
});
