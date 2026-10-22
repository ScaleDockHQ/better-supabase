"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Opens the organization's feedback board. */
export const createFeedbackBoard = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "posts.manage"),
  },
  async ({ name }, { supabase, tenant, auth }) => {
    const board = await blocks(supabase, tenant).posts.saveBoard({
      key: "feedback",
      name,
      kind: "feedback",
    });

    if (!board.ok) {
      return board;
    }

    refreshCaller(auth);

    return ok({ id: board.data.id });
  },
);

/** Posts an idea or a question on a board. */
export const createPost = bs.action(
  {
    input: v.object({
      boardId: Id,
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      body: v.pipe(v.string(), v.maxLength(10_000)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "posts.write"),
  },
  async ({ boardId, title, body }, { supabase, tenant, auth }) => {
    const post = await blocks(supabase, tenant).posts.create(boardId, {
      title,
      body,
    });

    if (!post.ok) {
      return post;
    }

    refreshCaller(auth);

    return ok({ id: post.data.id, moderation: post.data.moderation });
  },
);

/** Sets the caller's vote: 1 up, 0 to clear. */
export const voteOnPost = bs.action(
  {
    input: v.object({ postId: Id, value: v.picklist([0, 1]) }),
    requireTenant: true,
    authorize: (session) => can(session, "posts.read"),
  },
  async ({ postId, value }, { supabase, tenant, auth }) => {
    const tally = await blocks(supabase, tenant).posts.vote(postId, value);

    if (!tally.ok) {
      return tally;
    }

    refreshCaller(auth);

    return ok(tally.data);
  },
);
