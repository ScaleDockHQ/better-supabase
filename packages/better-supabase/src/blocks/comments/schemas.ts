import type { EntitySchema } from "../entity-schema.ts";
import type { CommentEdit, NewComment } from "./comments.ts";

import { entitySchema } from "../entity-schema.ts";

const FIELDS = {
  kind: "json",
  optional: true,
  description: "The extra columns to set, keyed by database name.",
} as const;

/**
 * What `create` takes. The body's length limit is `options.maxBody`, so the SQL
 * checks it.
 */
export const commentInputSchema: EntitySchema<NewComment> =
  entitySchema<NewComment>({
    title: "NewComment",
    fields: {
      organizationId: { kind: "uuid" },
      subjectType: { kind: "string", minLength: 1 },
      subjectId: { kind: "string", minLength: 1, maxLength: 200 },
      body: { kind: "string", minLength: 1 },
      document: {
        kind: "unknown",
        optional: true,
        description: "A rich-text document (any JSON).",
      },
      mentions: { kind: "uuid", optional: true, array: true },
      parentId: { kind: "uuid", optional: true },
      fields: FIELDS,
    },
  });

/** What `edit` takes. */
export const commentChangeSchema: EntitySchema<CommentEdit> =
  entitySchema<CommentEdit>({
    title: "CommentEdit",
    fields: {
      body: { kind: "string", minLength: 1 },
      document: {
        kind: "unknown",
        optional: true,
        description: "`null` removes the document.",
      },
      mentions: { kind: "uuid", optional: true, array: true },
      fields: FIELDS,
    },
  });
