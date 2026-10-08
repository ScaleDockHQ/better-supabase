import { createTestMessage } from "@chat-adapter/tests";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { CredentialProvider } from "../../src/credentials/index.ts";

import { createInbox, sqlTransport } from "../../src/blocks/inbox/index.ts";
import {
  createChatInstallations,
  createSupabaseState,
} from "../../src/chat-sdk/index.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { testChatState } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "jobs", "streams", "inbox"];

describe.skipIf(!live)("inbox module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  async function claim(s: BlockSession, queue: string) {
    await s.service();
    return s.rows<{ message: { payload: Record<string, unknown> } }>(
      "select message from better_supabase.claim_jobs($1, 30, 10)",
      [queue],
    );
  }

  it("lets a visitor and staff talk, with notes kept from the visitor", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(MODULES);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const viewer = await s.user("viewer");
      const visitor = await s.user("visitor");
      const org = await s.organization(owner, { member, viewer });
      const inbox = createInbox({ transport: sqlTransport(s.sql) });

      await s.asRole(owner);
      const widget = await inbox.inboxes
        .create({
          tenant: org,
          name: "Help",
          botMode: "bot",
          settings: { widget: true },
        })
        .orThrow();
      expect(widget).toMatchObject({ channel: "in_app", botMode: "bot" });

      await s.asRole(visitor);
      const opened = await inbox.conversations
        .open(widget.id, { message: "Where is my invoice?" })
        .orThrow();
      expect(opened).toMatchObject({
        status: "open",
        botMode: "bot",
        tenant: org,
      });
      expect(opened.threadId).toBe(`inbox:${opened.id}`);
      const [job] = await claim(s, "inbox_bot");
      expect(job?.message.payload).toMatchObject({
        conversation_id: opened.id,
        thread_id: opened.threadId,
      });

      await s.asRole(member);
      const [listed] = await inbox.conversations.list(org).orThrow();
      expect(listed).toMatchObject({ id: opened.id, unread: true });
      expect(await inbox.conversations.counts(org).orThrow()).toMatchObject({
        open: 1,
        unassigned: 1,
      });
      await inbox.messages
        .note(opened.id, "Check the billing page", { mentions: [owner.id] })
        .orThrow();
      const reply = await inbox.messages
        .send(opened.id, { body: "It is under Billing." })
        .orThrow();
      expect(reply).toMatchObject({
        authorType: "agent",
        direction: "outbound",
      });
      expect(
        (await inbox.conversations.get(opened.id).orThrow())?.botMode,
      ).toBe("human");
      expect(await inbox.conversations.typing(opened.id).orThrow()).toBe(true);
      await inbox.conversations.markRead(opened.id).orThrow();
      expect((await inbox.conversations.list(org).orThrow())[0]?.unread).toBe(
        false,
      );

      await s.asRole(visitor);
      const seen = await inbox.messages.list(opened.id).orThrow();
      expect(seen.map((message) => message.kind)).toEqual([
        "message",
        "message",
      ]);
      expect(await inbox.messages.get(reply.id).orThrow()).toMatchObject({
        body: "It is under Billing.",
      });
      const note = await inbox.messages.note(opened.id, "sneaky");
      expect(note.ok ? undefined : note.error.kind).toBe("forbidden");
      await inbox.messages.send(opened.id, { body: "Thanks" }).orThrow();
      const own = await inbox.conversations.list(org).orThrow();
      expect(
        own.map((conversation) => [conversation.id, conversation.inbox]),
      ).toEqual([[opened.id, null]]);

      await s.asRole(viewer);
      expect(await inbox.conversations.get(opened.id).orThrow()).toBeNull();
      const blocked = await inbox.messages.send(opened.id, { body: "hi" });
      expect(blocked.ok).toBe(false);

      await s.asRole(owner);
      const toViewer = await inbox.conversations.assign(opened.id, {
        assigneeId: viewer.id,
      });
      expect(toViewer.ok).toBe(false);
      expect(
        (
          await inbox.conversations
            .assign(opened.id, { assigneeId: member.id })
            .orThrow()
        ).assigneeId,
      ).toBe(member.id);
      await inbox.conversations.resolve(opened.id).orThrow();
      expect(
        (await inbox.conversations.reopen(opened.id).orThrow()).status,
      ).toBe("open");
      const types = (await inbox.conversations.events(opened.id).orThrow()).map(
        (event) => event.type,
      );
      expect(types).toEqual(
        expect.arrayContaining(["opened", "handoff", "assigned", "status"]),
      );

      await s.asRole(member);
      const erase = await inbox.purgeContact(opened.contactId);
      expect(erase.ok ? undefined : erase.error.kind).toBe("forbidden");
      await s.asRole(owner);
      expect(await inbox.purgeContact(opened.contactId).orThrow()).toEqual({
        conversations: 1,
        messages: 4,
        attachments: [],
      });
      expect(await inbox.conversations.get(opened.id).orThrow()).toBeNull();
    } finally {
      await s.close();
    }
  });

  it("records channel messages once and tracks their deliveries", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(MODULES);
      const owner = await s.user("owner");
      const org = await s.organization(owner);
      const inbox = createInbox({ transport: sqlTransport(s.sql) });
      await s.asRole(owner);
      const whatsapp = await inbox.inboxes
        .create({
          tenant: org,
          name: "WhatsApp",
          channel: "whatsapp",
          address: "+3100",
        })
        .orThrow();

      await s.service();
      const stored = await inbox.inbound
        .store({
          adapter: "whatsapp",
          body: '{"a":1}',
          headers: { "x-hub": "1" },
          externalId: "evt-1",
          inboxId: whatsapp.id,
        })
        .orThrow();
      expect(stored.duplicate).toBe(false);
      expect(
        (
          await inbox.inbound
            .store({ adapter: "whatsapp", body: "{}", externalId: "evt-1" })
            .orThrow()
        ).duplicate,
      ).toBe(true);
      const [pending] = await inbox.inbound.pending().orThrow();
      expect(pending).toMatchObject({
        id: stored.id,
        adapter: "whatsapp",
        headers: { "x-hub": "1" },
      });
      await inbox.inbound.setStatus(stored.id, "processed").orThrow();
      expect(await inbox.inbound.pending().orThrow()).toEqual([]);

      const input = {
        inboxId: whatsapp.id,
        threadId: "whatsapp:+3100:+3199",
        contact: { externalId: "+3199", name: "Ada" },
        message: { body: "Hi", externalId: "wamid.in1" },
      };
      const first = await inbox.inbound.record(input).orThrow();
      expect(first).toMatchObject({
        created: true,
        duplicate: false,
        tenant: org,
      });
      expect(await inbox.inbound.record(input).orThrow()).toMatchObject({
        conversationId: first.conversationId,
        duplicate: true,
      });

      await s.asRole(owner);
      const reply = await inbox.messages
        .send(first.conversationId, { body: "Hello Ada" })
        .orThrow();
      const [outbound] = await claim(s, "inbox_outbound");
      expect(outbound?.message.payload).toMatchObject({ message_id: reply.id });

      await s.service();
      await inbox.deliveries
        .record({
          messageId: reply.id,
          channel: "whatsapp",
          externalId: "wamid.out1",
          status: "sent",
        })
        .orThrow();
      expect(
        await inbox.deliveries
          .setStatus({
            channel: "whatsapp",
            externalId: "wamid.out1",
            status: "read",
          })
          .orThrow(),
      ).toBe(1);
      expect(
        (await inbox.messages.get(reply.id).orThrow())?.delivery,
      ).toMatchObject({ status: "read" });

      const mirrored = await inbox.messages
        .send(first.conversationId, {
          body: "sent by the bot",
          deliveredByCaller: true,
        })
        .orThrow();
      expect(mirrored.authorType).toBe("bot");
      expect(await claim(s, "inbox_outbound")).toEqual([]);
      await s.rows(
        "update better_supabase.inbound_events set received_at = now() - interval '2 days'",
      );
      expect(await inbox.inbound.purge({ olderThan: "1 day" }).orThrow()).toBe(
        1,
      );
    } finally {
      await s.close();
    }
  });
});

describe.skipIf(!live)("chat-sdk-state module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("passes the StateAdapter kit as the service role", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["chat-sdk-state"]);
      await s.service();
      const state = createSupabaseState({ transport: sqlTransport(s.sql) });
      const report = await testChatState(state, { message: createTestMessage });
      expect(report.checks.filter((check) => !check.ok)).toEqual([]);
      expect(await state.purge()).toBeGreaterThanOrEqual(0);
    } finally {
      await s.close();
    }
  });

  it("revokes the credentials an install drops", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "chat-sdk-state"]);
      const owner = await s.user("owner");
      const org = await s.organization(owner);
      await s.service();
      const revoked: unknown[] = [];
      const credentials: CredentialProvider = {
        apiVersion: 1,
        name: "fake",
        getToken: () => AsyncResult.ok({ token: "t", headers: {} }),
        capabilities: () => ({
          userSubjects: false,
          authorization: false,
          revoke: true,
          inbound: false,
        }),
        revoke: (ref) => {
          revoked.push(ref);
          return AsyncResult.ok(true);
        },
      };
      const installations = createChatInstallations({
        transport: sqlTransport(s.sql),
        credentials,
      });
      const ref = (secret: string) => ({ provider: "vault", secret });
      await installations
        .install({
          adapter: "slack",
          externalId: "T1",
          tenant: org,
          credentialRef: ref("a"),
        })
        .orThrow();
      await installations
        .install({
          adapter: "slack",
          externalId: "T1",
          tenant: org,
          credentialRef: ref("b"),
        })
        .orThrow();
      expect(revoked).toEqual([ref("a")]);
      expect(
        (await installations.get("slack", "T1").orThrow())?.credentialRef,
      ).toEqual(ref("b"));
      expect(await installations.uninstallTenant(org).orThrow()).toBe(1);
      expect(revoked).toEqual([ref("a"), ref("b")]);
      expect(await installations.list({ tenant: org }).orThrow()).toEqual([]);
      expect(
        await installations
          .list({ tenant: org, includeUninstalled: true })
          .orThrow(),
      ).toHaveLength(1);
      expect(await installations.uninstall("slack", "T1").orThrow()).toBe(
        false,
      );
    } finally {
      await s.close();
    }
  });
});
