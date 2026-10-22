import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createComments } from "./comments.ts";
import { commentsSqlOptions } from "./options.ts";
import { commentsSection } from "./section.ts";

/** The `comments` block's manifest (ADR 0029, ADR 0062). */
export const commentsBlock: BlockOf<
  "comments",
  typeof createComments,
  Record<never, never>,
  Record<never, never>,
  never,
  { readonly comments: typeof commentsSection }
> = defineBlock({
  name: "comments",
  sql: ["comments"],
  options: { comments: commentsSqlOptions },
  create: createComments,
  sections: { comments: commentsSection },
  category: "collaboration",
  recipes: ["comment-thread", "record-page"],
});
