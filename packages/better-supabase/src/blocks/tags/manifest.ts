import type { BlockOf } from "../define-block.ts";
import type { TagsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { tagsEvents } from "./events.ts";
import { tagsSqlOptions } from "./options.ts";
import { tagsBinding } from "./record-binding.ts";
import { createTags } from "./tags.ts";

/** The `tags` block's manifest (ADR 0029). */
export const tagsBlock: BlockOf<
  "tags",
  typeof createTags,
  TagsEvents,
  Record<never, never>,
  never,
  typeof tagsBinding
> = defineBlock({
  name: "tags",
  sql: ["tags"],
  options: { tags: tagsSqlOptions },
  events: tagsEvents,
  create: createTags,
  record: tagsBinding,
  category: "work",
  entities: {
    tag: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.",
  recipes: ["record-page", "tag-input"],
});
