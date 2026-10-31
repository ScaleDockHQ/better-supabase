import type { EntitySchema } from "../entity-schema.ts";
import type { LimsMethodInput, LimsSampleInput } from "./lims.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `registerSample` takes, with the bounds the SQL checks. */
export const limsSampleInputSchema: EntitySchema<LimsSampleInput> =
  entitySchema<LimsSampleInput>({
    title: "LimsSampleInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 200 },
      kind: { kind: "string", optional: true, nullable: true, maxLength: 100 },
      lot: { kind: "string", optional: true, nullable: true, maxLength: 100 },
      receivedOn: { kind: "plainDate", optional: true },
      notes: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 4000,
      },
    },
  });

/** What `saveMethod` takes, with the bounds the SQL checks. */
export const limsMethodInputSchema: EntitySchema<LimsMethodInput> =
  entitySchema<LimsMethodInput>({
    title: "LimsMethodInput",
    fields: {
      key: {
        kind: "string",
        minLength: 1,
        maxLength: 41,
        description:
          "Lowercase letters, digits and underscores, starting with a letter.",
      },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      unit: { kind: "string", optional: true, nullable: true, maxLength: 40 },
      lowerLimit: { kind: "number", optional: true, nullable: true },
      upperLimit: { kind: "number", optional: true, nullable: true },
      formId: { kind: "uuid", optional: true, nullable: true },
    },
  });
