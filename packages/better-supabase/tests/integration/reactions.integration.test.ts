import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import { createInbox } from "../../src/blocks/inbox/index.ts";
import {
  createReactions,
  sqlTransport,
} from "../../src/blocks/reactions/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
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
        await reactions
          .react({ subject: { type: "doc", id: doc }, emoji: "👍" })
          .orThrow(),
      ).toEqual([
        { emoji: "👍", count: 1, reacted: true, actors: [member.id] },
      ]);
      await s.asRole(owner);
      await reactions
        .react({ subject: { type: "doc", id: doc }, emoji: "👍" })
        .orThrow();
      await reactions
        .react({ subject: { type: "doc", id: doc }, emoji: "👍" })
        .orThrow();

      const after = await reactions
        .react({ subject: { type: "doc", id: doc }, emoji: "🎉" })
        .orThrow();

      expect(after.map((row) => [row.emoji, row.count])).toEqual([
        ["👍", 2],
        ["🎉", 1],
      ]);
      expect(
        await reactions
          .react({ subject: { type: "doc", id: doc }, emoji: ":ship-it:" })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_INVALID");
      await reactions
        .saveCustomEmoji({
          shortcode: "ship-it",
          url: "https://cdn.test/ship.png",
        })
        .orThrow();
      await reactions
        .react({ subject: { type: "doc", id: doc }, emoji: ":ship-it:" })
        .orThrow();

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
        .react({
          subject: { type: "doc", id: doc },
          emoji: "👍",
          present: false,
        })
        .orThrow();

      expect(removed.find((row) => row.emoji === "👍")).toMatchObject({
        count: 1,
        reacted: false,
      });
      expect(
        await reactions
          .react({ subject: { type: "missing", id: doc }, emoji: "👍" })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");

      const comment = await comments
        .create({
          subject: { type: "doc", id: doc },
          comment: { body: "Looks good" },
        })
        .orThrow();

      await reactions
        .react({ subject: { type: "message", id: comment.id }, emoji: "👀" })
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
          .react({ subject: { type: "doc", id: doc }, emoji: "👍" })
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

  it("votes up and down with one vote per actor and a score on the subject", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      await s.install(["organizations", "outbox", "reactions"], layout);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const stranger = await s.user("stranger");
      const tenant = await s.organization(owner, { member });
      await s.organization(stranger);

      const reactions = createReactions({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.service();

      const [first, second] = await s.rows<{ id: string }>(
        "insert into reactions_it.docs (organization_id) values ($1), ($1) returning id",
        [tenant],
      );

      const doc = { type: "doc", id: first!.id };
      const other = { type: "doc", id: second!.id };

      await s.asRole(member);
      expect(
        await reactions.vote({ subject: doc, value: 1 }).orThrow(),
      ).toEqual({ score: 1, up: 1, down: 0, vote: 1 });
      expect(
        await reactions.vote({ subject: doc, value: 1 }).orThrow(),
      ).toMatchObject({ score: 1 });
      await reactions.react({ subject: doc, emoji: "👍" }).orThrow();

      await s.asRole(owner);
      expect(
        await reactions.vote({ subject: doc, value: -1 }).orThrow(),
      ).toEqual({ score: 0, up: 1, down: 1, vote: -1 });
      await reactions.vote({ subject: other, value: 1 }).orThrow();
      expect(
        (await reactions.summary([doc]).orThrow())[`doc:${doc.id}`]?.map(
          (row) => row.emoji,
        ),
      ).toEqual(["👍"]);

      await s.asRole(member);
      expect(
        await reactions.vote({ subject: doc, value: -1 }).orThrow(),
      ).toEqual({ score: -2, up: 0, down: 2, vote: -1 });
      expect(await reactions.votes([doc, other]).orThrow()).toEqual({
        [`doc:${doc.id}`]: { score: -2, up: 0, down: 2, vote: -1 },
        [`doc:${other.id}`]: { score: 1, up: 1, down: 0, vote: 0 },
      });
      expect(
        await reactions
          .vote({ subject: doc, value: 2 as 1 })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_INVALID");
      expect(
        await reactions.vote({ subject: doc, value: 0 }).orThrow(),
      ).toEqual({ score: -1, up: 0, down: 1, vote: 0 });

      await s.asRole(stranger);
      expect(
        await reactions
          .vote({ subject: doc, value: 1 })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("REACTION_FORBIDDEN");
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.reaction_scores)",
        ),
      ).toBe(0);

      await s.service();
      expect(
        await reactions
          .vote({ subject: other, value: -1, actor: "importer" })
          .orThrow(),
      ).toMatchObject({ score: 0, up: 1, down: 1 });
      await s.asRole(owner);
      await reactions.vote({ subject: other, value: 0 }).orThrow();

      await s.service();

      const byId = (
        a: { subject_id: string },
        b: { subject_id: string },
      ): number => a.subject_id.localeCompare(b.subject_id);

      expect(
        (
          await s.rows<{ subject_id: string; score: number }>(
            "select subject_id, score from better_supabase.reaction_scores where tenant_id = $1",
            [tenant],
          )
        ).toSorted(byId),
      ).toEqual(
        [
          { subject_id: other.id, score: -1 },
          { subject_id: doc.id, score: -1 },
        ].toSorted(byId),
      );

      const events = await s.rows<{ type: string; kind: string }>(
        "select type, payload ->> 'kind' as kind from better_supabase.outbox_events where organization_id = $1 and type like 'reaction.%'",
        [tenant],
      );

      expect(
        new Set(events.map((event) => `${event.type}:${event.kind}`)),
      ).toEqual(
        new Set([
          "reaction.added:vote",
          "reaction.removed:vote",
          "reaction.added:emoji",
        ]),
      );
    } finally {
      await s.close();
    }
  });

  it("upgrades version 1 reactions to emoji rows with a kind in the key", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(`create schema reactions_up;
create table reactions_up.reactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  subject_type text not null,
  subject_id text not null,
  actor text not null,
  user_id uuid,
  emoji text not null check (length(emoji) between 1 and 64),
  created_at timestamptz not null default now(),
  unique (subject_type, subject_id, actor, emoji)
);
insert into reactions_up.reactions (tenant_id, subject_type, subject_id, actor, emoji)
values (gen_random_uuid(), 'doc', 'd1', 'u1', '👍');`);

      const [plan] = upgradePlan([{ module: "reactions", version: 1 }], {
        modules: { reactions: { schema: "reactions_up" } },
      });

      for (const step of plan!.steps) {
        await s.client.query(step.sql);
      }

      expect(
        await s.rows<{ kind: string; value: number }>(
          "select kind, value from reactions_up.reactions",
        ),
      ).toEqual([{ kind: "emoji", value: 1 }]);
      expect(
        await s.rows<{ conname: string }>(
          "select conname from pg_constraint where conrelid = 'reactions_up.reactions'::regclass and contype = 'u'",
        ),
      ).toEqual([]);
      await s.client.query(
        "insert into reactions_up.reactions (tenant_id, subject_type, subject_id, actor, kind, emoji, value) values (gen_random_uuid(), 'doc', 'd1', 'u1', 'vote', 'vote', -1)",
      );
      await expect(
        s.client.query(
          "insert into reactions_up.reactions (tenant_id, subject_type, subject_id, actor, emoji, value) values (gen_random_uuid(), 'doc', 'd1', 'u2', '👍', -1)",
        ),
      ).rejects.toThrow(/reactions_check/);
    } finally {
      await s.close();
    }
  });

  it("stores inbox reactions on the core message subject", async () => {
    const s = await BlockSession.open(pool);

    try {
      const modules = ["organizations", "queue", "streams", "outbox", "inbox"];
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
        .open({ inboxId: widget.id, input: { message: "Hello" } })
        .orThrow();

      await s.asRole(owner);

      const reply = await inbox.messages
        .send({ conversationId: opened.id, input: { body: "Hi there" } })
        .orThrow();

      const missing = await inbox.messages.react({
        messageId: reply.id,
        emoji: "👍",
      });

      expect(missing.ok ? undefined : missing.error).toMatchObject({
        hint: "INBOX_REACTIONS_MISSING",
      });
      await s.service();
      await s.install([...modules, "reactions"]);
      await s.asRole(owner);
      await inbox.messages
        .react({ messageId: reply.id, emoji: "👍" })
        .orThrow();
      expect(
        await s.rows<{ subject_type: string; actor: string; emoji: string }>(
          "select subject_type, actor, emoji from better_supabase.reactions where subject_id = $1",
          [reply.id],
        ),
      ).toEqual([{ subject_type: "message", actor: owner.id, emoji: "👍" }]);

      const counts = await reactions
        .react({ subject: { type: "message", id: reply.id }, emoji: "🎉" })
        .orThrow();

      expect(counts.map((row) => row.emoji).toSorted()).toEqual(["🎉", "👍"]);
      await s.service();

      const byBot = await inbox.messages
        .react({ messageId: reply.id, emoji: "👍", actor: "bot" })
        .orThrow();

      expect(
        byBot.find((row) => row.emoji === "👍")?.actors.toSorted(),
      ).toEqual([owner.id, "bot"].toSorted());
      await s.asRole(owner);
      expect(
        (
          await inbox.messages
            .react({ messageId: reply.id, emoji: "👍", present: false })
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
        (
          await inbox.messages
            .react({ messageId: reply.id, emoji: "❤️" })
            .orThrow()
        ).map((row) => row.emoji),
      ).toContain("❤️");
    } finally {
      await s.close();
    }
  });
});
