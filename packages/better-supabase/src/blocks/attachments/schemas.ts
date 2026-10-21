import type { EntitySchema } from "../entity-schema.ts";
import type { NewAttachment } from "./attachments.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `upload` takes, with the bounds the SQL checks. */
export const attachmentInputSchema: EntitySchema<NewAttachment> =
  entitySchema<NewAttachment>({
    title: "NewAttachment",
    fields: {
      organizationId: {
        kind: "uuid",
        nullable: true,
        description: "`null` for a subject type with `tenant: false`.",
      },
      name: { kind: "string", minLength: 1, maxLength: 255 },
      mimeType: { kind: "string", minLength: 1 },
      size: { kind: "integer", minimum: 0 },
      subjectType: { kind: "string", optional: true, minLength: 1 },
      subjectId: {
        kind: "string",
        optional: true,
        minLength: 1,
        maxLength: 200,
      },
      metadata: { kind: "json", optional: true },
    },
  });
