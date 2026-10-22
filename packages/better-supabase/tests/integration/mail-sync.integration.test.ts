import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { MailProvider } from "../../src/blocks/mail-sync/index.ts";
import type { CredentialProvider } from "../../src/credentials/provider.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createMailSync } from "../../src/blocks/mail-sync/index.ts";
import { createParties } from "../../src/blocks/parties/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: withBlockSubjects({}, ["parties"], {}),
};

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "parties",
  "engagements",
  "mail-sync",
];

const credentials: CredentialProvider = {
  apiVersion: 1,
  name: "vault",
  getToken: () =>
    AsyncResult.ok({ token: "t", headers: { authorization: "Bearer t" } }),
  capabilities: () => ({
    userSubjects: true,
    authorization: false,
    revoke: true,
    inbound: false,
  }),
  revoke: () => AsyncResult.ok(true),
};

function gmail(): MailProvider & { sent: unknown[] } {
  const sent: unknown[] = [];

  return {
    apiVersion: 1,
    name: "gmail",
    sent,
    list: (input) =>
      AsyncResult.ok({
        messages:
          input.cursor === undefined
            ? [
                {
                  externalId: "g1",
                  threadId: "gt1",
                  messageId: "<g1@client.test>",
                  from: { address: "ada@client.test", name: "Ada" },
                  to: [{ address: "rep@acme.test" }],
                  cc: [],
                  subject: "Pricing",
                  snippet: "What does it cost?",
                  sentAt: Temporal.Instant.from("2026-10-01T09:00:00Z"),
                },
              ]
            : [],
        cursor: "c1",
        more: false,
      }),
    send: (input) => {
      sent.push(input);

      return AsyncResult.ok({
        externalId: "g2",
        threadId: "gt1",
        messageId: "<g2@acme.test>",
      });
    },
  };
}

describe.skipIf(!live)("mail-sync", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("syncs a mailbox onto the parties it names and sends replies", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      await s.organization(stranger);
      const transport = sqlTransport(s.sql);
      const parties = createParties({ transport });
      const provider = gmail();

      const mail = createMailSync({
        transport,
        credentials,
        providers: [provider],
      });

      await s.as(rep);

      const ada = await parties
        .savePerson(org, { name: "Ada", email: "ada@client.test" })
        .orThrow();

      const person = { type: "person", id: ada.id };

      const account = await mail
        .connect(org, {
          provider: "gmail",
          address: "Rep@Acme.test",
          credentialRef: { provider: "vault", tenant: org, key: "gmail" },
        })
        .orThrow();

      expect(account).toMatchObject({
        address: "rep@acme.test",
        share: "records",
        status: "active",
      });
      expect(
        await mail.connect(org, {
          provider: "gmail",
          address: "rep@acme.test",
          credentialRef: { provider: "vault", tenant: "elsewhere" },
        }),
      ).toMatchObject({ ok: false });

      await s.service();

      const report = await mail.syncDue().orThrow();

      expect(report).toMatchObject({ stored: 1, failed: [] });
      expect(report.accounts).toBeGreaterThanOrEqual(1);

      // The owner reads Ada, so they see the thread logged on her.
      await s.asRole(owner);

      const [thread] = await mail.threadsOf(person).orThrow();

      expect(thread).toMatchObject({
        subject: "Pricing",
        messageCount: 1,
        subjects: [person],
      });
      expect(thread?.engagementId).toBeDefined();
      expect(await mail.link(thread!.id, [person])).toMatchObject({
        ok: false,
      });

      await s.asRole(rep);

      const reply = await mail
        .send(account.id, {
          threadId: thread!.id,
          to: [{ address: "ada@client.test" }],
          subject: "Re: Pricing",
          text: "Here is our offer",
        })
        .orThrow();

      expect(reply).toMatchObject({
        direction: "outbound",
        threadId: thread!.id,
      });
      expect(provider.sent).toHaveLength(1);
      expect(
        (await mail.thread(thread!.id).orThrow())?.messages.map(
          (m) => m.direction,
        ),
      ).toEqual(["inbound", "outbound"]);

      await s.asRole(stranger);
      expect(await mail.thread(thread!.id).orThrow()).toBeUndefined();

      // A private mailbox keeps its threads to its owner.
      await s.asRole(rep);
      await mail.update(account.id, { share: "private" }).orThrow();
      await s.asRole(owner);
      expect(await mail.threadsOf(person).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        `select type from better_supabase.outbox_events
         where organization_id = $1 and type like 'mail_%'
         order by position`,
        [org],
      );

      expect(events.map((event) => event.type)).toEqual([
        "mail_account.connected",
        "mail_message.received",
        "mail_message.sent",
      ]);
    } finally {
      await s.close();
    }
  });
});
