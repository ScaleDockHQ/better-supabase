import type { EntitySchema } from "../entity-schema.ts";
import type { ContentEntryInput } from "./content.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `create` takes, with the bounds the SQL checks. */
export const contentEntryInputSchema: EntitySchema<ContentEntryInput> =
  entitySchema<ContentEntryInput>({
    title: "ContentEntryInput",
    fields: {
      type: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        description: "One of `options.types`.",
      },
      locale: {
        kind: "string",
        optional: true,
        minLength: 2,
        maxLength: 35,
        description: "One of `options.locales`; default the first.",
      },
      slug: { kind: "string", minLength: 1, maxLength: 200 },
      title: { kind: "string", minLength: 1, maxLength: 300 },
      summary: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 2000,
      },
      body: {
        kind: "json",
        optional: true,
        description: "The editor's JSON document, an object or a list.",
      },
      coverAttachmentId: { kind: "uuid", optional: true, nullable: true },
      translationOf: { kind: "uuid", optional: true },
    },
  });
