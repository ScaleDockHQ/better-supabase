import type { BlockOf } from "../define-block.ts";
import type { TagsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { tagsEvents } from "./events.ts";
import { tagsSqlOptions } from "./options.ts";
import { tagsSection } from "./section.ts";
import { createTags } from "./tags.ts";

/** The `tags` block's manifest (ADR 0029). */
export const tagsBlock: BlockOf<
  "tags",
  typeof createTags,
  TagsEvents,
  Record<never, never>,
  never,
  { readonly tags: typeof tagsSection }
> = defineBlock({
  name: "tags",
  sql: ["tags"],
  options: { tags: tagsSqlOptions },
  events: tagsEvents,
  create: createTags,
  sections: { tags: tagsSection },
  category: "work",
  recipes: ["record-page", "tag-input"],
});
