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
  entities: {
    comment: {
      mutability: "append-only",
      emits: { create: false, delete: false },
    },
  },
  description:
    "Comments on any record as its conversation on the messaging core: whoever reads the record reads them, with replies, mentions and mention groups, anchors, files, edits with history, pins, resolved threads and read markers. The author and the mentioned follow the record and its followers hear of new comments (with notifications), and a comment becomes a work item (with tasks).",
  recipes: ["comment-thread", "record-page", "my-work", "subject-timeline"],
});
