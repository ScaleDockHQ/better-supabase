import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createComments } from "./comments.ts";
import { commentsSqlOptions } from "./options.ts";
import { commentsBinding } from "./record-binding.ts";

/** The `comments` block's manifest (ADR 0029, ADR 0062). */
export const commentsBlock: BlockOf<
  "comments",
  typeof createComments,
  Record<never, never>,
  { readonly attachments: "optional" },
  never,
  typeof commentsBinding
> = defineBlock({
  name: "comments",
  sql: ["comments"],
  options: { comments: commentsSqlOptions },
  consumes: { attachments: "optional" },
  create: createComments,
  record: commentsBinding,
  category: "collaboration",
  recipes: ["comment-thread", "record-page", "my-work", "subject-timeline"],
});
