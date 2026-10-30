import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createActivities } from "../../src/blocks/activities/index.ts";
import { createAttachments } from "../../src/blocks/attachments/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts"], {}),
};

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "contacts",
  "activities",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("engagements", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("logs calls and tasks on records and finds the next step", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const other = await s.organization(stranger);
      const transport = sqlTransport(s.sql);
      const parties = createContacts({ transport });
      const engagements = createActivities({ transport });

      await s.as(rep);
      const acme = await parties.saveCompany(org, { name: "Acme" }).orThrow();
      const ada = await parties.savePerson(org, { name: "Ada" }).orThrow();
      const company = { type: "company", id: acme.id };
      const person = { type: "person", id: ada.id };

      const call = await engagements
        .log(
          org,
          {
            type: "call",
            title: "Discovery call",
            outcome: "connected",
            doneAt: Temporal.Now.instant(),
            durationSeconds: 900,
          },
          [company, person],
        )
        .orThrow();

      expect(call.subjects).toEqual([company, person]);
      expect(call.ownerId).toBe(rep.id);

      const later = Temporal.Now.instant().add({ hours: 48 });
      const soon = Temporal.Now.instant().add({ hours: 2 });
      await engagements
        .log(org, { type: "task", title: "Send proposal", dueAt: later }, [
          company,
        ])
        .orThrow();

      const followUp = await engagements
        .log(
          org,
          { type: "meeting", title: "Demo", dueAt: soon, ownerId: owner.id },
          [company],
        )
        .orThrow();

      expect((await engagements.next(company).orThrow())?.id).toBe(followUp.id);
      expect(await engagements.next(person).orThrow()).toBeUndefined();

      const timeline = await engagements.of(company).orThrow();
      expect(timeline.map((item) => item.title)).toEqual([
        "Send proposal",
        "Demo",
        "Discovery call",
      ]);
      expect(
        (await engagements.of(company, { types: ["call"] }).orThrow()).map(
          (item) => item.type,
        ),
      ).toEqual(["call"]);

      expect(
        hint(
          await engagements.log(org, { type: "fax", title: "x" }, [company]),
        ),
      ).toBe("ACTIVITY_TYPE_INVALID");
      const foreign = await s.value<string>("(select gen_random_uuid()::text)");
      expect(
        hint(
          await engagements.log(org, { type: "note", title: "x" }, [
            { type: "company", id: foreign },
          ]),
        ),
      ).toBe("ACTIVITY_SUBJECT_FORBIDDEN");

      await s.as(owner);

      const done = await engagements
        .complete(followUp.id, { outcome: "held" })
        .orThrow();

      expect(done.doneAt).toBeDefined();
      expect(await engagements.open(org).orThrow()).toHaveLength(0);
      await s.as(rep);
      expect(
        (await engagements.open(org).orThrow()).map((item) => item.title),
      ).toEqual(["Send proposal"]);

      const assigned = await s.value<number>(
        "(select count(*)::int from better_supabase.notification_recipients r join better_supabase.notification_events e on e.id = r.event_id where e.type = 'engagement.assigned' and r.user_id = $1)",
        [owner.id],
      );

      expect(assigned).toBe(1);

      await s.as(stranger);
      expect(
        hint(
          await engagements.log(other, { type: "note", title: "x" }, [company]),
        ),
      ).toBe("ACTIVITY_SUBJECT_FORBIDDEN");
      await s.asRole(stranger);
      expect(
        await s.rows(
          "select 1 from better_supabase.engagements where id = $1",
          [call.id],
        ),
      ).toHaveLength(0);
      await s.as(stranger);
      expect(hint(await engagements.update(call.id, { title: "mine" }))).toBe(
        "ACTIVITY_NOT_FOUND",
      );
    } finally {
      await s.close();
    }
  });

  it("keeps files on an engagement task", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.install([...MODULES, "attachments"], {
        subjects: withBlockSubjects({}, ["contacts", "activities"], {}),
      });
      const org = await s.organization(owner, { member: rep });
      await s.organization(stranger);
      const transport = sqlTransport(s.sql);
      const parties = createContacts({ transport });
      const engagements = createActivities({ transport });

      const files = (tenant: string) =>
        createAttachments({
          transport,
          tenant,
          storage: {
            from: () => ({
              createSignedUploadUrl: (path) =>
                Promise.resolve({
                  data: {
                    signedUrl: `https://storage.test/${path}`,
                    token: "t",
                  },
                  error: null,
                }),
              createSignedUrl: (path) =>
                Promise.resolve({
                  data: { signedUrl: `https://storage.test/${path}` },
                  error: null,
                }),
              download: () =>
                Promise.resolve({ data: new Blob([]), error: null }),
              remove: () => Promise.resolve({ data: [], error: null }),
            }),
          },
        });

      await s.asRole(rep);

      const acme = await parties.saveCompany(org, { name: "Acme" }).orThrow();

      const task = await engagements
        .log(org, { type: "task", title: "Send the signed contract" }, [
          { type: "company", id: acme.id },
        ])
        .orThrow();

      const subject = { type: "activity", id: task.id };

      const file = {
        name: "contract.pdf",
        mimeType: "application/pdf",
        size: 10,
      };

      const { attachment } = await files(org).upload(subject, file).orThrow();

      expect(attachment.subject).toEqual(subject);
      expect(
        (await files(org).list(subject).orThrow()).map((item) => item.id),
      ).toEqual([attachment.id]);

      await s.asRole(stranger);

      expect((await files(org).upload(subject, file)).ok).toBe(false);
    } finally {
      await s.close();
    }
  });
});
