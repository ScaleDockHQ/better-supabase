import type { BlockOf } from "../define-block.ts";
import type { TagsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { tagsEvents } from "./events.ts";
import { createTags } from "./tags.ts";

/** The `tags` block's manifest (ADR 0029). */
export const tagsBlock: BlockOf<"tags", typeof createTags, TagsEvents> =
  defineBlock({
    name: "tags",
    sql: ["tags"],
    options: {
      tags: optionKeys(["subjects"]),
    },
    events: tagsEvents,
    create: createTags,
    category: "work",
    recipes: ["tag-input"],
  });
