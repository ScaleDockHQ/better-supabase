import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createChannels,
  sqlTransport,
} from "../../src/blocks/channels/index.ts";
import { createMessaging } from "../../src/blocks/messaging/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "profiles",
  "reactions",
  "attachments",
  "queue",
  "messaging",
  "channels",
];

describe.skipIf(!live)("channels", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("creates, browses, joins and manages public and private channels", async () => {
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

      const transport = sqlTransport(s.sql);

      const channels = createChannels({
        transport,
        tenant: () => organization,
      });

      const messaging = createMessaging({
        transport,
        tenant: () => organization,
      });

      await s.asRole(member);

      const general = await channels
        .create({ name: " General ", topic: "Everything" })
        .orThrow();

      expect(general).toMatchObject({
        organizationId: organization,
        name: "general",
        visibility: "public",
        topic: "Everything",
        role: "owner",
        memberCount: 1,
        createdBy: member.id,
      });

      const secret = await channels
        .create({ name: "secret", visibility: "private" })
        .orThrow();

      expect(await channels.create({ name: "general" })).toMatchObject({
        ok: false,
        error: { code: "23505" },
      });
      expect(await channels.create({ name: "Not a name" })).toMatchObject({
        ok: false,
      });

      // The channel is a conversation: messages go through messaging.
      await messaging.send(general.id, { body: "Hello" }).orThrow();

      await s.asRole(member2);

      expect(
        (await channels.list({ browse: true }).orThrow()).map((c) => c.name),
      ).toEqual(["general"]);
      expect(await channels.list().orThrow()).toEqual([]);
      expect(await channels.find("secret").orThrow()).toBeUndefined();
      expect(await channels.join(secret.id)).toMatchObject({ ok: false });
      expect(
        await channels.update(general.id, { topic: "Mine" }),
      ).toMatchObject({ ok: false });

      expect(await channels.join(general.id).orThrow()).toBe(true);

      const joined = await channels.get(general.id).orThrow();

      expect(joined).toMatchObject({ role: "member", memberCount: 2 });
      expect(joined?.lastMessageAt).toBeDefined();
      expect(await channels.leave(general.id).orThrow()).toBe(true);
      expect(await channels.leave(general.id).orThrow()).toBe(false);

      // The private channel's owner invites; the invitee then sees it.
      await s.asRole(member);
      expect(await channels.invite(secret.id, [member2.id]).orThrow()).toBe(1);
      expect(await channels.invite(secret.id, [outsider.id])).toMatchObject({
        ok: false,
      });

      await s.asRole(member2);
      expect((await channels.find("secret").orThrow())?.id).toBe(secret.id);

      // The owner of the organization holds channels.manage.
      await s.asRole(owner);

      const renamed = await channels
        .update(general.id, { name: "news", topic: null, purpose: "Company" })
        .orThrow();

      expect(renamed).toMatchObject({
        name: "news",
        topic: undefined,
        purpose: "Company",
      });
      expect(await channels.archive(general.id).orThrow()).toBe(true);
      expect(await channels.list({ browse: true }).orThrow()).toEqual([]);
      expect(
        (
          await channels.list({ browse: true, includeArchived: true }).orThrow()
        ).map((c) => [c.name, c.archivedAt !== undefined]),
      ).toEqual([["news", true]]);

      // A viewer reads channels but creates none.
      await s.asRole(viewer);
      expect(await channels.create({ name: "viewers" })).toMatchObject({
        ok: false,
      });

      await s.asRole(outsider);
      expect(await channels.get(secret.id).orThrow()).toBeUndefined();
      expect(await channels.join(secret.id)).toMatchObject({ ok: false });

      await s.service();

      const events = await s.rows<{ type: string }>(
        `select type from better_supabase.outbox_events
         where organization_id = $1 and type like 'channel.%'
         order by position`,
        [organization],
      );

      expect(events.map((event) => event.type)).toEqual([
        "channel.created",
        "channel.created",
        "channel.updated",
      ]);
    } finally {
      await s.close();
    }
  });
});
