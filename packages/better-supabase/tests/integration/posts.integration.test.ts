import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import { createModeration } from "../../src/blocks/moderation/index.ts";
import { createPosts } from "../../src/blocks/posts/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = { subjects: withBlockSubjects({}, ["posts"], {}) };

describe.skipIf(!live)("posts module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let tenant: string;
  let board: string;
  let dark: string;

  const postsFor = (organizationId: string) =>
    createPosts({
      transport: sqlTransport(session.sql),
      tenant: organizationId,
    });

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      [
        "organizations",
        "outbox",
        "subjects",
        "messaging",
        "comments",
        "reactions",
        "moderation",
        "posts",
      ],
      layout,
    );
    owner = await session.user("posts-owner");
    member = await session.user("posts-member");
    outsider = await session.user("posts-outsider");
    tenant = await session.organization(owner, { member });
    await session.organization(outsider);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("opens boards and publishes posts as moderation items", async () => {
    await session.as(owner);
    const posts = postsFor(tenant);

    const opened = await posts
      .saveBoard({ key: "ideas", name: "Ideas", kind: "feedback" })
      .orThrow();

    board = opened.id;
    expect(opened).toMatchObject({ key: "ideas", kind: "feedback" });
    expect(
      (await posts.saveBoard({ key: "Bad Key", name: "Bad" })).error?.hint,
    ).toBe("POST_INVALID");
    expect(await posts.boards().orThrow()).toEqual([
      expect.objectContaining({ id: board }),
    ]);

    await session.as(member);
    const mine = postsFor(tenant);

    expect(
      (await mine.saveBoard({ key: "mine", name: "Mine" })).error?.hint,
    ).toBe("POST_FORBIDDEN");

    const post = await mine
      .create(board, { title: "Dark mode", body: "Please" })
      .orThrow();

    dark = post.id;
    expect(post).toMatchObject({
      title: "Dark mode",
      status: "open",
      moderation: "visible",
      mine: true,
      replyCount: 0,
      votes: { score: 0, up: 0, down: 0, vote: 0 },
    });
    expect(
      (await mine.create(crypto.randomUUID(), { title: "x" })).error?.hint,
    ).toBe("POST_BOARD_NOT_FOUND");

    const updated = await mine
      .update(dark, { body: "Please add it" })
      .orThrow();

    expect(updated.body).toBe("Please add it");

    await session.as(owner);

    const item = await createModeration({
      transport: sqlTransport(session.sql),
      tenant,
    })
      .item({ type: "post", id: dark })
      .orThrow();

    expect(item).toMatchObject({ status: "visible" });
  });

  it("counts votes and replies, and lets moderators set the state", async () => {
    await session.as(member);
    const mine = postsFor(tenant);

    expect(await mine.vote(dark, 1).orThrow()).toEqual({
      score: 1,
      up: 1,
      down: 0,
      vote: 1,
    });
    await createComments({ transport: sqlTransport(session.sql), tenant })
      .create({ type: "post", id: dark }, { body: "Agreed" })
      .orThrow();
    expect((await mine.get(dark).orThrow())?.replyCount).toBe(1);
    expect((await mine.setState(dark, { pinned: true })).error?.hint).toBe(
      "POST_FORBIDDEN",
    );

    await session.as(owner);
    const posts = postsFor(tenant);

    expect((await posts.vote(dark, 1).orThrow()).score).toBe(2);

    const planned = await posts
      .setState(dark, { status: "planned", locked: true })
      .orThrow();

    expect(planned.status).toBe("planned");
    expect(planned.lockedAt).toBeDefined();

    await session.as(member);
    expect((await mine.update(dark, { title: "Dark theme" })).ok).toBe(false);
  });

  it("merges duplicates and follows the moderation item", async () => {
    await session.as(member);

    const night = await postsFor(tenant)
      .create(board, { title: "Night theme" })
      .orThrow();

    await postsFor(tenant).vote(night.id, 1).orThrow();

    await session.as(owner);
    const posts = postsFor(tenant);
    const merged = await posts.merge(night.id, dark).orThrow();

    expect(merged.votes.score).toBe(2);
    expect((await posts.get(night.id).orThrow())?.mergedIntoId).toBe(dark);
    expect(
      (await posts.list({ sort: "top" }).orThrow()).map((post) => post.id),
    ).toEqual([dark]);
    expect(await posts.list({ merged: true }).orThrow()).toHaveLength(2);

    const moderation = createModeration({
      transport: sqlTransport(session.sql),
      tenant,
    });

    const item = await moderation.item({ type: "post", id: dark }).orThrow();

    await moderation
      .decide(item!.id, "hide", { reason: "off topic" })
      .orThrow();
    expect((await posts.get(dark).orThrow())?.moderation).toBe("hidden");

    await session.as(member);
    expect((await postsFor(tenant).vote(dark, -1)).error?.hint).toBe(
      "POST_NOT_FOUND",
    );
  });

  it("keeps other organizations and banned members out", async () => {
    await session.asRole(outsider);
    expect(await postsFor(tenant).list({ merged: true }).orThrow()).toEqual([]);
    expect(await postsFor(tenant).get(dark).orThrow()).toBeNull();

    await session.as(owner);
    await createModeration({ transport: sqlTransport(session.sql), tenant })
      .ban(member.id, { reason: "spam" })
      .orThrow();

    await session.as(member);
    const mine = postsFor(tenant);

    expect((await mine.create(board, { title: "Again" })).error?.hint).toBe(
      "POST_FORBIDDEN",
    );

    const night = (await mine.list({ merged: true }).orThrow()).find(
      (post) => post.mine && post.id !== dark,
    );

    expect(await mine.delete(night!.id).orThrow()).toBe(true);
    expect(await mine.delete(night!.id).orThrow()).toBe(false);
  });
});
