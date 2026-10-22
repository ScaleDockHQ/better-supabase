import type { EntitySchema } from "../entity-schema.ts";
import type { MessageEdition, NewMessage } from "./messaging.ts";

import { entitySchema } from "../entity-schema.ts";

const FIELDS = {
  kind: "json",
  optional: true,
  description: "The extra columns to set, keyed by database name.",
} as const;

/**
 * What `send` takes after the conversation. The body's length limit is
 * `options.maxBodyLength`, so the SQL checks it; a message with files may have
 * an empty body.
 */
export const messageInputSchema: EntitySchema<NewMessage> =
  entitySchema<NewMessage>({
    title: "NewMessage",
    fields: {
      body: { kind: "string" },
      document: {
        kind: "unknown",
        optional: true,
        description: "A rich-text document (any JSON).",
      },
      anchor: {
        kind: "unknown",
        optional: true,
        description: "Where on the record a top-level message points.",
      },
      mentionIds: { kind: "uuid", optional: true, array: true },
      parentId: { kind: "uuid", optional: true },
      broadcast: { kind: "boolean", optional: true },
      scheduledFor: { kind: "instant", optional: true },
      attachmentIds: { kind: "uuid", optional: true, array: true },
      fields: FIELDS,
    },
  });

/** What `edit` takes. */
export const messageChangeSchema: EntitySchema<MessageEdition> =
  entitySchema<MessageEdition>({
    title: "MessageEdition",
    fields: {
      body: { kind: "string", minLength: 1 },
      document: {
        kind: "unknown",
        optional: true,
        description: "`null` removes the document.",
      },
      mentionIds: { kind: "uuid", optional: true, array: true },
      fields: FIELDS,
    },
  });
