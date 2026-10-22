import type { EntitySchema } from "../entity-schema.ts";
import type { PostBoardInput, PostInput } from "./posts.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `saveBoard` takes, with the bounds the SQL checks. */
export const postBoardInputSchema: EntitySchema<PostBoardInput> =
  entitySchema<PostBoardInput>({
    title: "PostBoardInput",
    fields: {
      id: { kind: "uuid", optional: true },
      key: { kind: "string", optional: true, minLength: 1, maxLength: 63 },
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      description: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 2000,
      },
      kind: { kind: "enum", values: ["forum", "feedback"], optional: true },
      archived: { kind: "boolean", optional: true },
    },
  });

/** What `create` takes, with the bounds the SQL checks. */
export const postInputSchema: EntitySchema<PostInput> = entitySchema<PostInput>(
  {
    title: "PostInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 300 },
      body: {
        kind: "string",
        optional: true,
        maxLength: 200_000,
        description: "At most `options.maxBodyLength` characters.",
      },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set, keyed by database name.",
      },
    },
  },
);
