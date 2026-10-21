import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createMessaging,
  sqlTransport,
} from "../../src/blocks/messaging/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "profiles",
  "reactions",
  "attachments",
  "jobs",
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
});
