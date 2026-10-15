import type { BlockOf } from "../define-block.ts";
import type { CommentsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createComments } from "./comments.ts";
import { commentsEvents } from "./events.ts";

/** The `comments` block's manifest (ADR 0029). */
export const commentsBlock: BlockOf<
  "comments",
  typeof createComments,
  CommentsEvents
> = defineBlock({
  name: "comments",
  sql: ["comments"],
  options: {
    comments: optionKeys([
      "subjects",
      "maxBodyLength",
      "documentSchema",
      "notify",
      "follow",
      "mentionGroups",
    ]),
  },
  events: commentsEvents,
  create: createComments,
  category: "collaboration",
  recipes: ["comment-thread"],
});
