import type { EntitySchema } from "../entity-schema.ts";
import type { DamUsageRightInput } from "./dam.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `grantRight` takes, with the bounds the SQL checks. */
export const damUsageRightInputSchema: EntitySchema<DamUsageRightInput> =
  entitySchema<DamUsageRightInput>({
    title: "DamUsageRightInput",
    fields: {
      nodeId: { kind: "uuid", description: "The drive file." },
      licensee: { kind: "string", minLength: 1, maxLength: 200 },
      territory: {
        kind: "string",
        optional: true,
        nullable: true,
        description: "Without one the right covers every territory.",
      },
      channel: {
        kind: "string",
        optional: true,
        nullable: true,
        description: "Without one the right covers every channel.",
      },
      startsOn: { kind: "plainDate", optional: true },
      expiresOn: {
        kind: "plainDate",
        optional: true,
        nullable: true,
        description: "On or after startsOn. Without one the right never ends.",
      },
      note: { kind: "string", optional: true, nullable: true, maxLength: 2000 },
    },
  });
