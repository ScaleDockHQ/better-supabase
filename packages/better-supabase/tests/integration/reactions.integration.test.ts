import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  createReactions,
  sqlTransport,
} from "../../src/blocks/reactions/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: { doc: { table: "reactions_it.docs", idType: "uuid" } },
};

const TABLES = `create schema reactions_it;
create table reactions_it.docs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table reactions_it.docs enable row level security;
create policy docs_read on reactions_it.docs for select to authenticated using (true);
grant usage on schema reactions_it to authenticated;
grant select on reactions_it.docs to authenticated;`;

describe.skipIf(!live)("reactions", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("reacts to subjects and comments under their read rules, with custom emoji", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      await s.install(
        ["organizations", "outbox", "comments", "reactions"],
        layout,
      );
      const owner = await s.user("owner");
      const member = await s.user("member");
      const stranger = await s.user("stranger");
      const tenant = await s.organization(owner, { member });
      await s.organization(stranger);
      const reactions = createReactions({ transport: sqlTransport(s.sql) });
      const comments = createComments({ transport: sqlTransport(s.sql) });

      await s.service();

      const doc = (
        await s.rows<{ id: string }>(
          "insert into reactions_it.docs (organization_id) values ($1) returning id",
          [tenant],
        )
      )[0]!.id;

      await s.asRole(member);
      expect(await reactions.react(tenant, "doc", doc, "👍").orThrow()).toEqual(
        [{ emoji: "👍", count: 1, reacted: true, actors: [member.id] }],
      );
      await s.asRole(owner);
      await reactions.react(tenant, "doc", doc, "👍").orThrow();
      await reactions.react(tenant, "doc", doc, "👍").orThrow();
      const after = await reactions.react(tenant, "doc", doc, "🎉").orThrow();
      expect(after.map((row) => [row.emoji, row.count])).toEqual([
        ["👍", 2],
        ["🎉", 1],
      ]);
      expect(
        await reactions
          .react(tenant, "doc", doc, ":ship-it:")
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_INVALID");
      await reactions
        .saveCustomEmoji(tenant, {
          shortcode: "ship-it",
          url: "https://cdn.test/ship.png",
        })
        .orThrow();
      await reactions.react(tenant, "doc", doc, ":ship-it:").orThrow();

      await s.asRole(member);
      expect(
        await reactions
          .saveCustomEmoji(tenant, {
            shortcode: "nope",
            url: "https://cdn.test/nope.png",
          })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");

      const removed = await reactions
        .react(tenant, "doc", doc, "👍", { present: false })
        .orThrow();

      expect(removed.find((row) => row.emoji === "👍")).toMatchObject({
        count: 1,
        reacted: false,
      });
      expect(
        await reactions
          .react(tenant, "missing", doc, "👍")
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");

      const comment = await comments
        .create({
          organizationId: tenant,
          subjectType: "doc",
          subjectId: doc,
          body: "Looks good",
        })
        .orThrow();

      await reactions.react(tenant, "comment", comment.id, "👀").orThrow();

      const summary = await reactions
        .summary(tenant, "comment", [comment.id, "nope"])
        .orThrow();

      expect(summary[comment.id]).toEqual([
        { emoji: "👀", count: 1, reacted: true, actors: [member.id] },
      ]);
      expect(summary["nope"]).toEqual([]);

      await s.asRole(stranger);
      expect(
        await reactions
          .react(tenant, "doc", doc, "👍")
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");
      expect(
        (await reactions.summary(tenant, "doc", [doc]).orThrow())[doc],
      ).toEqual([]);

      await s.asRole(owner);
      const [emoji] = await reactions.customEmoji(tenant).orThrow();
      expect(emoji).toMatchObject({ shortcode: "ship-it" });
      expect(await reactions.deleteCustomEmoji(emoji!.id).orThrow()).toBe(true);
      expect(
        (await reactions.summary(tenant, "doc", [doc]).orThrow())[doc]
          ?.map((row) => row.emoji)
          .toSorted(),
      ).toEqual(["🎉", "👍"]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'reaction.%'",
        [tenant],
      );

      expect(new Set(events.map((event) => event.type))).toEqual(
        new Set(["reaction.added", "reaction.removed"]),
      );
    } finally {
      await s.close();
    }
  });

  it("keeps an inbox message's reactions column as a copy of the table", async () => {
    const s = await BlockSession.open(pool);

    try {
      const modules = ["organizations", "jobs", "streams", "outbox", "inbox"];
      await s.install(modules);
      const owner = await s.user("owner");
      const visitor = await s.user("visitor");
      const tenant = await s.organization(owner);
      const inbox = createInbox({ transport: sqlTransport(s.sql) });
      const reactions = createReactions({ transport: sqlTransport(s.sql) });

      await s.asRole(owner);

      const widget = await inbox.inboxes
        .create({ tenant, name: "Help", settings: { widget: true } })
        .orThrow();

      await s.asRole(visitor);

      const opened = await inbox.conversations
        .open(widget.id, { message: "Hello" })
        .orThrow();

      await s.asRole(owner);

      const reply = await inbox.messages
        .send(opened.id, { body: "Hi there" })
        .orThrow();

      await inbox.messages.react(reply.id, "👍").orThrow();
      await s.service();
      await s.install([...modules, "reactions"]);
      expect(
        await s.rows<{ actor: string; emoji: string }>(
          "select actor, emoji from better_supabase.reactions where subject_id = $1",
          [reply.id],
        ),
      ).toEqual([{ actor: owner.id, emoji: "👍" }]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.outbox_events where type = 'reaction.added' and organization_id = $1)",
          [tenant],
        ),
      ).toBe(0);
      await s.asRole(owner);

      const counts = await reactions
        .react(tenant, "inbox_message", reply.id, "🎉")
        .orThrow();

      expect(counts.map((row) => row.emoji).toSorted()).toEqual(["🎉", "👍"]);
      await s.service();

      const byBot = await inbox.messages
        .react(reply.id, "👍", { actor: "bot" })
        .orThrow();

      expect(byBot["👍"]?.toSorted()).toEqual([owner.id, "bot"].toSorted());
      expect(byBot["🎉"]).toEqual([owner.id]);
      await s.asRole(owner);
      expect(
        await inbox.messages
          .react(reply.id, "👍", { present: false })
          .orThrow(),
      ).toEqual({ "👍": ["bot"], "🎉": [owner.id] });
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.reactions where subject_id = $1)",
          [reply.id],
        ),
      ).toBe(2);
    } finally {
      await s.close();
    }
  });
});
