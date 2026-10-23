import type { EntitySchema } from "../entity-schema.ts";
import type { PassInput } from "./passes.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `issue` takes, with the bounds the SQL checks. */
export const passInputSchema: EntitySchema<PassInput> = entitySchema<PassInput>(
  {
    title: "PassInput",
    fields: {
      kind: { kind: "string", optional: true, minLength: 1, maxLength: 40 },
      holderUserId: { kind: "uuid", optional: true },
      holderName: {
        kind: "string",
        optional: true,
        minLength: 1,
        maxLength: 200,
      },
      holderEmail: {
        kind: "string",
        optional: true,
        minLength: 3,
        maxLength: 320,
      },
      subject: {
        kind: "json",
        optional: true,
        description: "The record the pass is for: `{ type, id }`.",
      },
      bookingId: { kind: "uuid", optional: true },
      resourceId: { kind: "uuid", optional: true },
      usesAllowed: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 100_000,
      },
      validFrom: { kind: "instant", optional: true },
      validUntil: { kind: "instant", optional: true },
    },
  },
);

/** What the section's `issue` write takes: the record is the pass's subject. */
export type PassSectionInput = Omit<PassInput, "subject">;

export const passSectionInputSchema: EntitySchema<PassSectionInput> =
  entitySchema<PassSectionInput>({
    title: "PassSectionInput",
    fields: {
      kind: { kind: "string", optional: true, minLength: 1, maxLength: 40 },
      holderUserId: { kind: "uuid", optional: true },
      holderName: {
        kind: "string",
        optional: true,
        minLength: 1,
        maxLength: 200,
      },
      holderEmail: {
        kind: "string",
        optional: true,
        minLength: 3,
        maxLength: 320,
      },
      bookingId: { kind: "uuid", optional: true },
      resourceId: { kind: "uuid", optional: true },
      usesAllowed: {
        kind: "integer",
        optional: true,
        minimum: 1,
        maximum: 100_000,
      },
      validFrom: { kind: "instant", optional: true },
      validUntil: { kind: "instant", optional: true },
    },
  });
