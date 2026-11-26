"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Opens the organization's feedback board. */
export const createFeedbackBoard = bsb.blockAction(
  ({ db }) => db.posts,
  "saveBoard",
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    permission: "posts.manage",
    tags: () => [tags.community()],
    refresh: true,
    args: ({ name }) => [{ key: "feedback", name, kind: "feedback" }],
  },
  (board) => ({ id: board.id }),
);

/** Posts an idea or a question on a board. */
export const createPost = bsb.blockAction(
  ({ db }) => db.posts,
  "create",
  {
    input: v.object({
      boardId: Id,
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      body: v.pipe(v.string(), v.maxLength(10_000)),
    }),
    requireTenant: true,
    permission: "posts.write",
    tags: () => [tags.community()],
    refresh: true,
    args: ({ boardId, title, body }) => [{ boardId, input: { title, body } }],
  },
  (post) => ({ id: post.id, moderation: post.moderation }),
);

/** Sets the caller's vote: 1 up, 0 to clear. */
export const voteOnPost = bsb.blockAction(({ db }) => db.posts, "vote", {
  input: v.object({ postId: Id, value: v.picklist([0, 1]) }),
  requireTenant: true,
  permission: "posts.read",
  tags: () => [tags.community()],
  refresh: true,
});
