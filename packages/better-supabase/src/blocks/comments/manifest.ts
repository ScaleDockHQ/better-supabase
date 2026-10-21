import type { BlockOf } from "../define-block.ts";
import type { CommentsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createComments } from "./comments.ts";
import { commentsEvents } from "./events.ts";
import { commentsSqlOptions } from "./options.ts";
import { commentChangeSchema, commentInputSchema } from "./schemas.ts";
import { commentsSection } from "./section.ts";

/** The `comments` block's manifest (ADR 0029). */
export const commentsBlock: BlockOf<
  "comments",
  typeof createComments,
  CommentsEvents,
  Record<never, never>,
  never,
  { readonly comments: typeof commentsSection }
> = defineBlock({
  name: "comments",
  sql: ["comments"],
  options: { comments: commentsSqlOptions },
  events: commentsEvents,
  schemas: {
    comment: { input: commentInputSchema, change: commentChangeSchema },
  },
  create: createComments,
  sections: { comments: commentsSection },
  category: "collaboration",
  recipes: ["comment-thread", "record-page", "my-work", "subject-timeline"],
});
