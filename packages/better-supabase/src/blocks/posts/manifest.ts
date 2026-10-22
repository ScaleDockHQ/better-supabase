import type { BlockOf } from "../define-block.ts";
import type { PostsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { postsEvents } from "./events.ts";
import { postsSqlOptions } from "./options.ts";
import { createPosts } from "./posts.ts";
import { postBoardInputSchema, postInputSchema } from "./schemas.ts";

/** The `posts` block's manifest (ADR 0029). */
export const postsBlock: BlockOf<"posts", typeof createPosts, PostsEvents> =
  defineBlock({
    name: "posts",
    sql: ["posts"],
    options: { posts: postsSqlOptions },
    events: postsEvents,
    schemas: {
      post_board: { input: postBoardInputSchema },
      post: { input: postInputSchema },
    },
    create: createPosts,
    category: "collaboration",
    recipes: ["post-board"],
  });
