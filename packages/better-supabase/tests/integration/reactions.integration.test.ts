import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  createReactions,
  sqlTransport,
} from "../../src/blocks/reactions/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: withBlockSubjects(
    { doc: { table: "reactions_it.docs", idType: "uuid" } },
    ["comments", "messaging"],
    {},
  ),
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

      const reactions = createReactions({
        transport: sqlTransport(s.sql),
        tenant,
      });

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.service();

      const doc = (
        await s.rows<{ id: string }>(
          "insert into reactions_it.docs (organization_id) values ($1) returning id",
          [tenant],
        )
      )[0]!.id;

      await s.asRole(member);
      expect(
        await reactions.react({ type: "doc", id: doc }, "👍").orThrow(),
      ).toEqual([
        { emoji: "👍", count: 1, reacted: true, actors: [member.id] },
      ]);
      await s.asRole(owner);
      await reactions.react({ type: "doc", id: doc }, "👍").orThrow();
      await reactions.react({ type: "doc", id: doc }, "👍").orThrow();

      const after = await reactions
        .react({ type: "doc", id: doc }, "🎉")
        .orThrow();

      expect(after.map((row) => [row.emoji, row.count])).toEqual([
        ["👍", 2],
        ["🎉", 1],
      ]);
      expect(
        await reactions
          .react({ type: "doc", id: doc }, ":ship-it:")
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_INVALID");
      await reactions
        .saveCustomEmoji({
          shortcode: "ship-it",
          url: "https://cdn.test/ship.png",
        })
        .orThrow();
      await reactions.react({ type: "doc", id: doc }, ":ship-it:").orThrow();

      await s.asRole(member);
      expect(
        await reactions
          .saveCustomEmoji({
            shortcode: "nope",
            url: "https://cdn.test/nope.png",
          })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");

      const removed = await reactions
        .react({ type: "doc", id: doc }, "👍", { present: false })
        .orThrow();

      expect(removed.find((row) => row.emoji === "👍")).toMatchObject({
        count: 1,
        reacted: false,
      });
      expect(
        await reactions
          .react({ type: "missing", id: doc }, "👍")
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");

      const comment = await comments
        .create({ type: "doc", id: doc }, { body: "Looks good" })
        .orThrow();

      await reactions
        .react({ type: "message", id: comment.id }, "👀")
        .orThrow();

      const summary = await reactions
        .summary([
          { type: "message", id: comment.id },
          { type: "message", id: "00000000-0000-4000-8000-000000000000" },
        ])
        .orThrow();

      expect(summary[`message:${comment.id}`]).toEqual([
        { emoji: "👀", count: 1, reacted: true, actors: [member.id] },
      ]);
      expect(summary["message:00000000-0000-4000-8000-000000000000"]).toEqual(
        [],
      );

      await s.asRole(stranger);
      expect(
        await reactions
          .react({ type: "doc", id: doc }, "👍")
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");
      expect(
        (await reactions.summary([{ type: "doc", id: doc }]).orThrow())[
          `doc:${doc}`
        ],
      ).toEqual([]);

      await s.asRole(owner);
      const [emoji] = await reactions.customEmoji().orThrow();
      expect(emoji).toMatchObject({ shortcode: "ship-it" });
      expect(await reactions.deleteCustomEmoji(emoji!.id).orThrow()).toBe(true);
      expect(
        (await reactions.summary([{ type: "doc", id: doc }]).orThrow())[
          `doc:${doc}`
        ]
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

  it("stores inbox reactions on the core message subject", async () => {
    const s = await BlockSession.open(pool);

    try {
      const modules = ["organizations", "jobs", "streams", "outbox", "inbox"];
      await s.install(modules);
      const owner = await s.user("owner");
      const visitor = await s.user("visitor");
      const tenant = await s.organization(owner);
      const inbox = createInbox({ transport: sqlTransport(s.sql) });

      const reactions = createReactions({
        transport: sqlTransport(s.sql),
        tenant,
      });

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

      const missing = await inbox.messages.react(reply.id, "👍");
      expect(missing.ok ? undefined : missing.error).toMatchObject({
        hint: "INBOX_REACTIONS_MISSING",
      });
      await s.service();
      await s.install([...modules, "reactions"]);
      await s.asRole(owner);
      await inbox.messages.react(reply.id, "👍").orThrow();
      expect(
        await s.rows<{ subject_type: string; actor: string; emoji: string }>(
          "select subject_type, actor, emoji from better_supabase.reactions where subject_id = $1",
          [reply.id],
        ),
      ).toEqual([{ subject_type: "message", actor: owner.id, emoji: "👍" }]);

      const counts = await reactions
        .react({ type: "message", id: reply.id }, "🎉")
        .orThrow();

      expect(counts.map((row) => row.emoji).toSorted()).toEqual(["🎉", "👍"]);
      await s.service();

      const byBot = await inbox.messages
        .react(reply.id, "👍", { actor: "bot" })
        .orThrow();

      expect(
        byBot.find((row) => row.emoji === "👍")?.actors.toSorted(),
      ).toEqual([owner.id, "bot"].toSorted());
      await s.asRole(owner);
      expect(
        (
          await inbox.messages
            .react(reply.id, "👍", { present: false })
            .orThrow()
        ).map((row) => [row.emoji, row.actors]),
      ).toEqual([
        ["🎉", [owner.id]],
        ["👍", ["bot"]],
      ]);
      expect(
        (await inbox.messages.get(reply.id).orThrow())?.reactions.map((row) => [
          row.emoji,
          row.count,
          row.reacted,
        ]),
      ).toEqual([
        ["🎉", 1, true],
        ["👍", 1, false],
      ]);
      await s.asRole(visitor);
      expect(
        (await inbox.messages.react(reply.id, "❤️").orThrow()).map(
          (row) => row.emoji,
        ),
      ).toContain("❤️");
    } finally {
      await s.close();
    }
  });
});
