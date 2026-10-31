import type { EntitySchema } from "../entity-schema.ts";
import type { NewAttachment } from "./attachments.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `upload` takes after the subject, with the bounds the SQL checks. */
export const attachmentInputSchema: EntitySchema<NewAttachment> =
  entitySchema<NewAttachment>({
    title: "NewAttachment",
    fields: {
      name: { kind: "string", minLength: 1, maxLength: 255 },
      mimeType: { kind: "string", minLength: 1 },
      size: { kind: "integer", minimum: 0 },
      metadata: { kind: "json", optional: true },
      width: { kind: "integer", minimum: 1, optional: true },
      height: { kind: "integer", minimum: 1, optional: true },
      pages: { kind: "integer", minimum: 1, optional: true },
      documentType: { kind: "string", minLength: 1, optional: true },
      source: { kind: "string", minLength: 1, maxLength: 100, optional: true },
      externalId: { kind: "string", minLength: 1, optional: true },
      sourcePath: { kind: "string", minLength: 1, optional: true },
    },
  });
