import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "notifications",
  "contacts",
];

const layout: BlockSqlLayout = {
  modules: { contacts: { options: { extraColumns: { segment: "text" } } } },
};

describe.skipIf(!live)("parties", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("keeps companies, people and who works where", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const parties = createContacts({ transport: sqlTransport(s.sql) });

      await s.as(rep);

      const acme = await parties
        .saveCompany(org, {
          name: "Acme",
          domain: "Acme.com ",
          ownerId: rep.id,
          fields: { segment: "smb" },
        })
        .orThrow();

      expect(acme).toMatchObject({
        name: "Acme",
        domain: "acme.com",
        lifecycle: "lead",
      });
      expect(acme.fields).toEqual({ segment: "smb" });
      expect(
        await parties
          .saveCompany(org, { name: "Acme again", domain: "acme.com" })
          .then((r) => (r.ok ? "ok" : r.error.hint)),
      ).toBe("PARTY_DOMAIN_TAKEN");
      expect(
        await parties
          .saveCompany(org, { name: "Bad", lifecycle: "vip" })
          .then((r) => (r.ok ? "ok" : r.error.hint)),
      ).toBe("PARTY_LIFECYCLE_INVALID");

      const ada = await parties
        .savePerson(org, { name: "Ada", email: "ADA@acme.com", title: "CTO" })
        .orThrow();

      const bob = await parties
        .savePerson(org, { name: "Bob", email: "bob@acme.com" })
        .orThrow();

      await parties
        .linkPerson(acme.id, ada.id, { role: "Champion", primary: true })
        .orThrow();
      await parties.linkPerson(acme.id, bob.id, { primary: true }).orThrow();
      const people = await parties.peopleOf(acme.id).orThrow();
      expect(people.map((person) => [person.name, person.primary])).toEqual([
        ["Bob", true],
        ["Ada", false],
      ]);

      const updated = await parties
        .saveCompany(org, { id: acme.id, lifecycle: "customer", website: null })
        .orThrow();

      expect(updated).toMatchObject({ name: "Acme", lifecycle: "customer" });

      const page = await parties
        .listPeople(org, { search: "acme", limit: 1 })
        .orThrow();

      expect(page.items.map((person) => person.name)).toEqual(["Ada"]);

      const next = await parties
        .listPeople(org, {
          search: "acme",
          limit: 1,
          ...(page.next ? { cursor: page.next } : {}),
        })
        .orThrow();

      expect(next.items.map((person) => person.name)).toEqual(["Bob"]);

      expect(
        await parties
          .mergePeople(ada.id, bob.id)
          .then((r) => (r.ok ? "ok" : r.error.hint)),
      ).toBe("PARTY_FORBIDDEN");
      await s.as(owner);
      const kept = await parties.mergePeople(ada.id, bob.id).orThrow();
      expect(kept.email).toBe("ada@acme.com");
      expect(
        (await parties.peopleOf(acme.id).orThrow()).map(
          (person) => person.name,
        ),
      ).toEqual(["Ada"]);
      expect(
        await s.value<string>(
          "(select merged_into::text from better_supabase.people where id = $1)",
          [bob.id],
        ),
      ).toBe(ada.id);

      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.notification_subscriptions where subject_type = 'company' and subject_id = $1 and user_id = $2)",
          [acme.id, rep.id],
        ),
      ).toBe(1);

      await s.asRole(stranger);
      expect(
        await s.rows("select 1 from better_supabase.companies where id = $1", [
          acme.id,
        ]),
      ).toHaveLength(0);
      await s.as(stranger);
      expect(
        await parties
          .saveCompany(org, { name: "Intruder" })
          .then((r) => (r.ok ? "ok" : r.error.hint)),
      ).toBe("PARTY_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});

describe.skipIf(!live)("parties merge", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("moves the dropped company's comments to the kept one", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install([...MODULES, "comments"], {
        subjects: withBlockSubjects({}, ["contacts", "comments"], {}),
      });
      const org = await s.organization(owner);
      const parties = createContacts({ transport: sqlTransport(s.sql) });

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant: org,
      });

      await s.as(owner);

      const keep = await parties.saveCompany(org, { name: "Acme" }).orThrow();

      const drop = await parties
        .saveCompany(org, { name: "Acme Inc" })
        .orThrow();

      await comments
        .create({ type: "company", id: drop.id }, { body: "Called them" })
        .orThrow();
      await parties.mergeCompanies(keep.id, drop.id).orThrow();

      expect(
        (await comments.list({ type: "company", id: keep.id }).orThrow()).map(
          (row) => row.body,
        ),
      ).toEqual(["Called them"]);
      expect(
        await comments.list({ type: "company", id: drop.id }).orThrow(),
      ).toEqual([]);
    } finally {
      await s.close();
    }
  });
});

describe.skipIf(!live)("parties and the inbox", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("keeps a person's addresses and finds the person by one", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(
        ["organizations", "queue", "streams", "inbox", "contacts"],
        {},
      );
      const org = await s.organization(owner);
      const parties = createContacts({ transport: sqlTransport(s.sql) });
      await s.as(owner);

      const ada = await parties
        .savePerson(org, { name: "Ada", email: "ada@acme.com" })
        .orThrow();

      const bo = await parties.savePerson(org, { name: "Bo" }).orThrow();

      const added = await parties
        .addIdentity(ada.id, {
          channel: "whatsapp",
          address: " +3161 ",
          verified: true,
        })
        .orThrow();

      expect(added).toMatchObject({
        personId: ada.id,
        channel: "whatsapp",
        address: "+3161",
      });
      expect(added.verifiedAt).toBeDefined();
      expect(
        (await parties.findByIdentity(org, "whatsapp", "+3161").orThrow())?.id,
      ).toBe(ada.id);

      const taken = await parties.addIdentity(bo.id, {
        channel: "whatsapp",
        address: "+3161",
      });

      expect(taken.ok ? "ok" : taken.error.hint).toBe("PARTY_IDENTITY_TAKEN");

      expect(await parties.identities(ada.id).orThrow()).toHaveLength(1);
      expect(await parties.removeIdentity(added.id).orThrow()).toBe(true);
      expect(await parties.removeIdentity(added.id).orThrow()).toBe(false);
      expect(
        await parties.findByIdentity(org, "whatsapp", "+3161").orThrow(),
      ).toBeUndefined();
    } finally {
      await s.close();
    }
  });
});
