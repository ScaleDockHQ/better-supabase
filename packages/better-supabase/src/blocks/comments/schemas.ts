import type { EntitySchema } from "../entity-schema.ts";
import type { CommentEdit, NewComment } from "./comments.ts";

import { entitySchema } from "../entity-schema.ts";
import { messageChangeSchema } from "../messaging/schemas.ts";

/**
 * What `create` takes after the subject. The body's length limit is
 * `blocks.messaging.options.maxBodyLength`, so the SQL checks it.
 */
export const commentInputSchema: EntitySchema<NewComment> =
  entitySchema<NewComment>({
    title: "NewComment",
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
        description: "Where on the record the comment points.",
      },
      mentionIds: { kind: "uuid", optional: true, array: true },
      parentId: { kind: "uuid", optional: true },
      attachmentIds: { kind: "uuid", optional: true, array: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set, keyed by database name.",
      },
    },
  });

/** What `edit` takes: a message edit. */
export const commentChangeSchema: EntitySchema<CommentEdit> =
  messageChangeSchema;
