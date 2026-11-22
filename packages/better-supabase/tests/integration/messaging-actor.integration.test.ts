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
  "queue",
  "messaging",
];

describe.skipIf(!live)("messaging actor labels", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("stores who acted on a message and carries it on message.sent", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES);
      const owner = await s.user("owner");
      const organization = await s.organization(owner);

      const messaging = createMessaging({
        transport: sqlTransport(s.sql),
        tenant: () => organization,
      });

      await s.asRole(owner);

      const channel = await messaging
        .open({ kind: "channel", title: "ops" })
        .orThrow();

      const plain = await messaging
        .send({ conversationId: channel.id, message: { body: "by hand" } })
        .orThrow();

      const labelled = await messaging
        .send({
          conversationId: channel.id,
          message: {
            body: "by agent",
            actor: { kind: "agent", name: "Scout" },
          },
        })
        .orThrow();

      expect(plain).toMatchObject({ authorKind: "user" });
      expect(plain.authorName).toBeUndefined();
      expect(labelled).toMatchObject({
        authorKind: "agent",
        authorName: "Scout",
      });

      await s.service();

      const events = await s.rows<{ payload: Record<string, unknown> }>(
        "select payload from better_supabase.outbox_events where type = 'message.sent' and payload ->> 'messageId' = $1",
        [labelled.id],
      );

      expect(events[0]?.payload).toMatchObject({
        actorKind: "agent",
        actorName: "Scout",
      });
    } finally {
      await s.close();
    }
  });
});
