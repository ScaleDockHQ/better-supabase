import "server-only";
import type {
  PostBoardKind,
  PostModeration,
  PostStatus,
} from "better-supabase/blocks/posts";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

export interface PostRow {
  readonly id: string;
  readonly title: string;
  readonly body: string;
  readonly status: PostStatus;
  readonly moderation: PostModeration;
  readonly pinned: boolean;
  readonly locked: boolean;
  readonly replyCount: number;
  readonly score: number;
  /** The caller's vote: 1, -1 or 0. */
  readonly vote: number;
}

export interface BoardView {
  readonly id: string;
  readonly name: string;
  readonly kind: PostBoardKind;
  readonly posts: readonly PostRow[];
}

/** `null` board: the organization has none yet. */
async function loadBoard(): Promise<{ board: BoardView | null } | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { posts } = db;
  const [board] = await posts.boards().orThrow();

  if (board === undefined) {
    return { board: null };
  }

  const rows = await posts
    .list({
      boardId: board.id,
      sort: board.kind === "feedback" ? "top" : "active",
    })
    .orThrow();

  return {
    board: {
      id: board.id,
      name: board.name,
      kind: board.kind,
      posts: rows.map((post) => ({
        id: post.id,
        title: post.title,
        body: post.body,
        status: post.status,
        moderation: post.moderation,
        pinned: post.pinnedAt !== undefined,
        locked: post.lockedAt !== undefined,
        replyCount: post.replyCount,
        score: post.votes.score,
        vote: post.votes.vote,
      })),
    },
  };
}

export async function getBoard(): Promise<Loaded<BoardView | null>> {
  try {
    const loaded = await loadBoard();

    return loaded === null
      ? { kind: "no-organization" }
      : { kind: "ok", data: loaded.board };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
