import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type {
  ThreadSummarizer,
  ThreadSummaryInput,
} from "../../src/blocks/messaging/index.ts";
import type { BlockTransport } from "../../src/core/block-transport.ts";

import {
  createMessaging,
  recordMention,
  sqlTransport,
} from "../../src/blocks/messaging/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

// A subject whose rows only their author reads, so a channel member can see a
// mention of a record they can't open.
const MEMOS = `create table if not exists public.messaging_test_memos (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  author uuid not null,
  title text not null
);
alter table public.messaging_test_memos enable row level security;
grant select on public.messaging_test_memos to authenticated;
create policy memos_author on public.messaging_test_memos for select to authenticated
  using (author = (select auth.uid()));`;

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "profiles",
  "reactions",
  "attachments",
  "queue",
  "messaging",
];

describe.skipIf(!live)("messaging", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("opens channels and direct messages, threads replies and notifies mentions", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const member2 = await s.user("member2");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");

      const organization = await s.organization(owner, {
        member,
        member2,
        viewer,
      });

      const messaging = createMessaging({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(owner);

      const channel = await messaging
        .open({ kind: "channel", title: "launch", memberIds: [member.id] })
        .orThrow();

      expect(channel).toMatchObject({
        organizationId: organization,
        kind: "channel",
        access: "members",
        title: "launch",
        createdBy: owner.id,
      });

      // An outsider can't be added: they can't read messages in the tenant.
      expect(
        await messaging.open({
          kind: "channel",
          title: "leak",
          memberIds: [outsider.id],
        }),
      ).toMatchObject({ ok: false });

      const first = await messaging
        .send(channel.id, {
          body: `Ship it @[Member](${member.id}) @[Two](${member2.id})`,
        })
        .orThrow();

      expect(first).toMatchObject({
        conversationId: channel.id,
        authorId: owner.id,
        threadId: undefined,
        replyCount: 0,
      });
      expect(first.sentAt).toBeDefined();
      expect([...first.mentionIds].toSorted()).toEqual(
        [member.id, member2.id].toSorted(),
      );

      await s.asRole(member);

      const reply = await messaging
        .send(channel.id, { body: "On it", parentId: first.id })
        .orThrow();

      expect(reply).toMatchObject({ parentId: first.id, threadId: first.id });

      // One level of threads: a reply to a reply joins the root.
      const nested = await messaging
        .send(channel.id, { body: "Nested", parentId: reply.id })
        .orThrow();

      expect(nested).toMatchObject({ parentId: first.id, threadId: first.id });

      const root = await messaging.get(first.id).orThrow();

      expect(root).toMatchObject({ replyCount: 2 });
      expect(root?.replyUserIds).toEqual([member.id]);

      const top = await messaging.list(channel.id).orThrow();

      expect(top.map((message) => message.id)).toEqual([first.id]);

      const replies = await messaging.replies(first.id).orThrow();

      // One transaction fixes `now()`, so both replies share a send time.
      expect(replies.map((message) => message.id).toSorted()).toEqual(
        [reply.id, nested.id].toSorted(),
      );

      expect(
        await messaging.edit(first.id, { body: "Not mine" }),
      ).toMatchObject({ ok: false });

      const edited = await messaging
        .edit(reply.id, { body: "On it, today" })
        .orThrow();

      expect(edited.editedAt).toBeDefined();
      expect(
        (await messaging.edits(reply.id).orThrow()).map((edit) => edit.body),
      ).toEqual(["On it"]);

      // member2 isn't in the private channel: no read, no send.
      await s.asRole(member2);
      expect(await messaging.list(channel.id).orThrow()).toEqual([]);
      expect(
        await messaging.send(channel.id, { body: "Let me in" }),
      ).toMatchObject({ ok: false });

      await s.asRole(owner);

      const summaries = await messaging.conversations().orThrow();
      const summary = summaries.find((entry) => entry.id === channel.id);

      // The member's top-level messages count; the owner's own don't.
      expect(summary).toMatchObject({ unread: 0, notify: "all" });

      await s.asRole(member);

      const unread = await messaging.unreadCounts().orThrow();

      expect(unread[channel.id]).toMatchObject({ unread: 1, mentions: 1 });

      await messaging.markRead(channel.id).orThrow();
      expect(
        (await messaging.unreadCounts().orThrow())[channel.id],
      ).toBeUndefined();

      await s.service();

      const notified = await s.rows<{ user_id: string; type: string }>(
        `select r.user_id, e.type from better_supabase.notification_recipients r
         join better_supabase.notification_events e on e.id = r.event_id
         where e.organization_id = $1 order by e.type, r.user_id`,
        [organization],
      );

      // member2 is mentioned but can't read the channel, so nothing reaches
      // them; the owner follows the thread they started.
      expect(notified).toContainEqual({
        user_id: member.id,
        type: "message.mentioned",
      });
      expect(notified).toContainEqual({
        user_id: owner.id,
        type: "message.replied",
      });
      expect(notified.map((row) => row.user_id)).not.toContain(member2.id);

      await s.asRole(owner);

      const direct = await messaging.openDirect([member.id]).orThrow();
      const again = await messaging.openDirect([member.id]).orThrow();

      expect(direct.kind).toBe("dm");
      expect(again.id).toBe(direct.id);

      await messaging.send(direct.id, { body: "Hi" }).orThrow();

      await s.service();
      expect(
        await s.rows<{ user_id: string }>(
          `select r.user_id from better_supabase.notification_recipients r
           join better_supabase.notification_events e on e.id = r.event_id
           where e.type = 'message.direct' and e.organization_id = $1`,
          [organization],
        ),
      ).toEqual([{ user_id: member.id }]);

      await s.asRole(owner);

      const pinned = await messaging.pin(first.id).orThrow();

      expect(pinned.pinnedBy).toBe(owner.id);
      expect(
        (await messaging.pinned(channel.id).orThrow()).map((m) => m.id),
      ).toEqual([first.id]);
      expect((await messaging.resolve(first.id).orThrow()).resolvedBy).toBe(
        owner.id,
      );

      expect(await messaging.remove(first.id).orThrow()).toBe(true);

      const removed = await messaging.get(first.id).orThrow();

      expect(removed).toMatchObject({ body: "", mentionIds: [] });
      expect(removed?.deletedAt).toBeDefined();

      // A viewer holds no messages keys.
      await s.asRole(viewer);
      expect(
        await messaging.open({ kind: "channel", title: "viewers" }),
      ).toMatchObject({ ok: false });

      await s.service();

      const events = await s.rows<{ type: string }>(
        `select type from better_supabase.outbox_events
         where organization_id = $1 and (type like 'message.%' or type like 'conversation.%')
         order by position`,
        [organization],
      );

      expect(new Set(events.map((event) => event.type))).toEqual(
        new Set([
          "conversation.created",
          "message.sent",
          "message.edited",
          "message.pinned",
          "message.resolved",
          "message.deleted",
        ]),
      );
    } finally {
      await s.close();
    }
  });

  it("joins tenant channels on send, schedules messages and publishes them when due", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const messaging = createMessaging({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(owner);

      const general = await messaging
        .open({ kind: "channel", title: "general", access: "tenant" })
        .orThrow();

      await s.asRole(member);
      // A tenant channel is readable before joining, and sending joins it.
      expect(await messaging.list(general.id).orThrow()).toEqual([]);
      await messaging.send(general.id, { body: "Hello" }).orThrow();
      expect(
        (await messaging.conversations().orThrow()).map((entry) => entry.id),
      ).toContain(general.id);

      const later = await messaging
        .send(general.id, {
          body: "Later",
          scheduledFor: Temporal.Now.instant().add({ hours: 1 }),
        })
        .orThrow();

      expect(later.sentAt).toBeUndefined();

      // Only the author sees a scheduled message.
      expect(
        (await messaging.list(general.id).orThrow()).map((m) => m.body),
      ).toEqual(["Hello", "Later"]);

      await s.asRole(owner);
      expect(
        (await messaging.list(general.id).orThrow()).map((m) => m.body),
      ).toEqual(["Hello"]);

      await s.service();
      await s.rows(
        "update better_supabase.messages set scheduled_for = now() - interval '1 minute' where id = $1",
        [later.id],
      );
      expect(await messaging.publishDue().orThrow()).toBe(1);

      await s.asRole(owner);

      // Inside one transaction `now()` is fixed, so both share a `sentAt`.
      const published = await messaging.list(general.id).orThrow();

      expect(published.map((m) => m.body).toSorted()).toEqual([
        "Hello",
        "Later",
      ]);
      expect(published.every((m) => m.sentAt !== undefined)).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("lists record mentions as backlinks for the record's readers", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(MEMOS);
      await s.install([...MODULES, "subjects"], {
        subjects: {
          memo: {
            table: "public.messaging_test_memos",
            idType: "uuid",
            title: "title",
            url: "/memos/{id}",
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });

      const messaging = createMessaging({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.service();

      const [memo] = await s.rows<{ id: string }>(
        "insert into public.messaging_test_memos (organization_id, author, title) values ($1, $2, 'Plan') returning id",
        [organization, owner.id],
      );

      await s.asRole(owner);

      const channel = await messaging
        .open({ kind: "channel", title: "plans", memberIds: [member.id] })
        .orThrow();

      const message = await messaging
        .send(channel.id, {
          body: `See ${recordMention("Plan", { type: "memo", id: memo!.id })}`,
        })
        .orThrow();

      const memoRef = { type: "memo", id: memo!.id };
      const backlinks = await messaging.recordMentions(memoRef).orThrow();

      expect(backlinks).toHaveLength(1);
      expect(backlinks[0]?.message.id).toBe(message.id);
      expect(backlinks[0]?.conversation).toMatchObject({
        id: channel.id,
        kind: "channel",
        title: "plans",
      });

      // The member reads the channel but not the memo.
      await s.asRole(member);
      expect(await messaging.recordMentions(memoRef).orThrow()).toEqual([]);

      await s.asRole(owner);
      await messaging.edit(message.id, { body: "Never mind" }).orThrow();
      expect(await messaging.recordMentions(memoRef).orThrow()).toEqual([]);
    } finally {
      await s.close();
    }
  });

  it("summarizes conversations and threads, saves them as the service role and marks them stale", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member });

      const transport = sqlTransport(s.sql);
      let caller = owner;

      const service: BlockTransport = {
        async call(schema, fn, args) {
          await s.service();

          try {
            return await transport.call(schema, fn, args);
          } finally {
            await s.asRole(caller);
          }
        },
      };

      const messaging = createMessaging({
        transport,
        service,
        tenant: () => organization,
      });

      const seen: ThreadSummaryInput[] = [];

      const summarizer: ThreadSummarizer = {
        apiVersion: 1,
        summarize(input) {
          seen.push(input);

          return Promise.resolve({
            summary: `${String(input.messages.length)} messages`,
            model: "test/model",
          });
        },
      };

      await s.asRole(owner);

      const channel = await messaging
        .open({ kind: "channel", title: "launch", memberIds: [member.id] })
        .orThrow();

      const root = await messaging
        .send(channel.id, { body: "Ship on Friday?" })
        .orThrow();

      await messaging
        .send(channel.id, { body: "Friday works", parentId: root.id })
        .orThrow();

      // The authenticated transport can't write a summary.
      const spoofed = await createMessaging({
        transport,
        tenant: () => organization,
      }).summarize({ conversationId: channel.id }, summarizer);

      expect(spoofed.error?.kind).toBe("forbidden");

      const summary = await messaging
        .summarize({ conversationId: channel.id }, summarizer)
        .orThrow();

      expect(summary).toMatchObject({
        conversationId: channel.id,
        summary: "1 messages",
        model: "test/model",
        messageCount: 1,
        stale: false,
      });

      // A current summary is returned without calling the model again.
      seen.length = 0;
      await messaging
        .summarize({ conversationId: channel.id }, summarizer)
        .orThrow();
      expect(seen).toEqual([]);

      const thread = await messaging
        .summarize({ threadId: root.id }, summarizer)
        .orThrow();

      expect(thread).toMatchObject({
        conversationId: channel.id,
        threadId: root.id,
        summary: "2 messages",
      });

      caller = member;
      await s.asRole(member);
      expect(
        (await messaging.summary({ threadId: root.id }).orThrow())?.summary,
      ).toBe("2 messages");

      await s.asRole(outsider);
      expect(
        await messaging.summary({ conversationId: channel.id }).orThrow(),
      ).toBeUndefined();

      // The session is one transaction, so age the summary to let a later
      // message land after it.
      await s.client.query(
        "reset role; update better_supabase.thread_summaries set through_at = now() - interval '1 minute'",
      );
      caller = owner;
      await s.asRole(owner);
      await messaging.send(channel.id, { body: "Or Monday" }).orThrow();
      expect(
        (await messaging.summary({ conversationId: channel.id }).orThrow())
          ?.stale,
      ).toBe(true);
    } finally {
      await s.close();
    }
  });
});
