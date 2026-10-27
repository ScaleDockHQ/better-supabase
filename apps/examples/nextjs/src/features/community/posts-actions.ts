"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Opens the organization's feedback board. */
export const createFeedbackBoard = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "posts.manage"),
  },
  async ({ name }, { db, auth }) => {
    const board = await db.posts.saveBoard({
      key: "feedback",
      name,
      kind: "feedback",
    });

    if (!board.ok) {
      return board;
    }

    await refreshCaller(auth);

    return ok({ id: board.data.id });
  },
);

/** Posts an idea or a question on a board. */
export const createPost = bsb.action(
  {
    input: v.object({
      boardId: Id,
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      body: v.pipe(v.string(), v.maxLength(10_000)),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "posts.write"),
  },
  async ({ boardId, title, body }, { db, auth }) => {
    const post = await db.posts.create(boardId, { title, body });

    if (!post.ok) {
      return post;
    }

    await refreshCaller(auth);

    return ok({ id: post.data.id, moderation: post.data.moderation });
  },
);

/** Sets the caller's vote: 1 up, 0 to clear. */
export const voteOnPost = bsb.action(
  {
    input: v.object({ postId: Id, value: v.picklist([0, 1]) }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "posts.read"),
  },
  async ({ postId, value }, { db, auth }) => {
    const tally = await db.posts.vote(postId, value);

    if (!tally.ok) {
      return tally;
    }

    await refreshCaller(auth);

    return ok(tally.data);
  },
);
