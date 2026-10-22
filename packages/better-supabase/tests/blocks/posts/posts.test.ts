import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createPosts,
  postBoardInputSchema,
  postInputSchema,
  postsBlock,
  postsEvents,
} from "../../../src/blocks/posts/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const BOARD = {
  id: "b1",
  organizationId: "org",
  key: "ideas",
  name: "Ideas",
  description: null,
  kind: "feedback",
  archivedAt: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const POST = {
  id: "p1",
  organizationId: "org",
  boardId: "b1",
  authorId: "u1",
  mine: true,
  title: "Dark mode",
  body: "Please",
  status: "open",
  moderation: "visible",
  pinnedAt: null,
  lockedAt: null,
  mergedIntoId: null,
  replyCount: 2,
  lastActivityAt: AT,
  votes: { score: 3, up: 4, down: 1, vote: 1 },
  createdAt: AT,
  updatedAt: AT,
  fields: { area: "ui" },
};

const MERGED = {
  ...POST,
  id: "p2",
  authorId: null,
  mine: false,
  body: null,
  status: "closed",
  pinnedAt: AT,
  lockedAt: AT,
  mergedIntoId: "p1",
  replyCount: null,
  votes: null,
  fields: null,
};

describe("createPosts", () => {
  it("manages boards", async () => {
    const { transport, call } = fakeTransport({
      save_post_board: BOARD,
      list_post_boards: [
        { ...BOARD, description: "All ideas", archivedAt: AT, createdBy: null },
      ],
    });

    const posts = createPosts({ transport, tenant: "org" });

    const board = await posts
      .saveBoard({
        key: "ideas",
        name: "Ideas",
        kind: "feedback",
        description: undefined,
      })
      .orThrow();

    expect(board).toMatchObject({
      id: "b1",
      kind: "feedback",
      createdBy: "u1",
    });
    expect(board.description).toBeUndefined();
    expect(board.archivedAt).toBeUndefined();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "save_post_board",
      {
        tenant: "org",
        board: { key: "ideas", name: "Ideas", kind: "feedback" },
      },
    );

    const [archived] = await posts.boards({ archived: true }).orThrow();

    expect(archived?.description).toBe("All ideas");
    expect(archived?.archivedAt?.toString()).toBe(AT);
    expect(archived?.createdBy).toBeUndefined();
    await posts.boards().orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_post_boards",
      { tenant: "org", archived: false },
    );
  });

  it("writes, reads, votes on and moderates posts", async () => {
    const { transport, call } = fakeTransport({
      create_post: POST,
      update_post: POST,
      delete_post: true,
      get_post: MERGED,
      list_posts: [POST, MERGED],
      set_post_state: POST,
      vote_on_post: { score: 1, up: 1, down: 0, vote: 1 },
      merge_posts: POST,
    });

    const posts = createPosts({
      transport,
      tenant: "org",
      fields: v.object({ area: v.optional(v.string()) }),
    });

    const created = await posts
      .create("b1", {
        title: "Dark mode",
        body: "Please",
        fields: { area: "ui" },
      })
      .orThrow();

    expect(created).toMatchObject({
      id: "p1",
      authorId: "u1",
      mine: true,
      replyCount: 2,
      votes: { score: 3, up: 4, down: 1, vote: 1 },
      fields: { area: "ui" },
    });
    expect(call).toHaveBeenLastCalledWith("better_supabase", "create_post", {
      board_id: "b1",
      post: { title: "Dark mode", body: "Please", fields: { area: "ui" } },
    });

    await posts.update("p1", { title: "Dark theme" }).orThrow();
    expect(call).toHaveBeenLastCalledWith("better_supabase", "update_post", {
      post_id: "p1",
      attrs: { title: "Dark theme" },
    });

    const merged = await posts.get("p2").orThrow();

    expect(merged).toMatchObject({
      mine: false,
      body: "",
      status: "closed",
      mergedIntoId: "p1",
      replyCount: 0,
      votes: { score: 0, up: 0, down: 0, vote: 0 },
    });
    expect(merged?.authorId).toBeUndefined();
    expect(merged?.pinnedAt?.toString()).toBe(AT);
    expect(merged?.lockedAt?.toString()).toBe(AT);

    expect(
      await posts.list({ sort: "top", boardId: "b1" }).orThrow(),
    ).toHaveLength(2);
    expect(call).toHaveBeenLastCalledWith("better_supabase", "list_posts", {
      tenant: "org",
      filter: { sort: "top", boardId: "b1" },
    });
    await posts.list().orThrow();

    await posts.setState("p1", { status: "planned", locked: true }).orThrow();
    expect(call).toHaveBeenLastCalledWith("better_supabase", "set_post_state", {
      post_id: "p1",
      attrs: { status: "planned", locked: true },
    });
    expect(await posts.vote("p1", 1).orThrow()).toEqual({
      score: 1,
      up: 1,
      down: 0,
      vote: 1,
    });
    expect((await posts.merge("p2", "p1").orThrow()).id).toBe("p1");
    expect(call).toHaveBeenLastCalledWith("better_supabase", "merge_posts", {
      source_id: "p2",
      target_id: "p1",
    });
    expect(await posts.delete("p1").orThrow()).toBe(true);
  });

  it("returns null for a post the caller can't see", async () => {
    const { transport } = fakeTransport({ get_post: null });

    expect(await createPosts({ transport }).get("p9").orThrow()).toBeNull();
    expect(
      await createPosts({
        transport: fakeTransport({ vote_on_post: null }).transport,
      })
        .vote("p1", 0)
        .orThrow(),
    ).toEqual({ score: 0, up: 0, down: 0, vote: 0 });
  });

  it("refuses extra columns the schema rejects", async () => {
    const { transport, call } = fakeTransport({});

    const posts = createPosts({
      transport,
      fields: v.object({ area: v.picklist(["ui", "api"]) }),
    });

    // SAFETY: the test passes a value the schema must reject.
    const result = await posts.create("b1", {
      title: "x",
      fields: { area: "db" as "ui" },
    });

    expect(result.ok).toBe(false);
    expect(call).not.toHaveBeenCalled();
  });

  it("needs a tenant for the organization's lists", async () => {
    const { transport } = fakeTransport({});

    expect((await createPosts({ transport }).list()).ok).toBe(false);
  });

  it("validates input and declares the block", async () => {
    expect(
      (await postInputSchema["~standard"].validate({ title: "Hi" })).issues,
    ).toBeUndefined();
    expect(
      (await postInputSchema["~standard"].validate({})).issues,
    ).toBeDefined();
    expect(
      (
        await postBoardInputSchema["~standard"].validate({
          key: "ideas",
          name: "Ideas",
        })
      ).issues,
    ).toBeUndefined();
    expect(postsBlock.name).toBe("posts");
    expect(postsEvents.types).toContain("post.merged");
  });
});
