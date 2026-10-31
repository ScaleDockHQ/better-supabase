import type { EntitySchema } from "../entity-schema.ts";
import type { TillInput } from "./tills.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `createTill` takes, with the bounds the SQL checks. */
export const tillInputSchema: EntitySchema<TillInput> = entitySchema<TillInput>(
  {
    title: "TillInput",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 100 },
      currency: {
        kind: "string",
        minLength: 3,
        maxLength: 3,
        description: "An ISO 4217 code such as EUR.",
      },
      accountId: {
        kind: "string",
        optional: true,
        nullable: true,
        description: "The accounting account that holds the till's cash.",
      },
      location: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 200,
      },
    },
  },
);
