import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createGuests } from "../../src/blocks/guests/index.ts";
import { createRelations } from "../../src/blocks/relations/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "notifications",
  "comments",
  "relations",
  "contacts",
  "guests",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects(
    { client: { table: "rep_it.clients", idType: "uuid" } },
    MODULES,
    {},
  ),
  modules: {
    guests: { options: { representation: { subjects: ["client"] } } },
  },
};

const TABLES = `create schema rep_it;
create table rep_it.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table rep_it.clients enable row level security;
create policy clients_read on rep_it.clients for select to authenticated using (true);
grant usage on schema rep_it to authenticated;
grant select on rep_it.clients to authenticated;`;

describe.skipIf(!live)("representatives", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("lets a representative reach the record they represent as a guest", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      await s.install(MODULES, layout);
      const owner = await s.user("owner");
      const guardian = await s.user("guardian", "guardian.test");
      const tenant = await s.organization(owner);
      const transport = sqlTransport(s.sql);
      const contacts = createContacts({ transport });
      const relations = createRelations({ transport, tenant });
      const guests = createGuests({ transport, tenant });
      const comments = createComments({ transport, tenant });

      await s.service();

      const [row] = await s.rows<{ id: string }>(
        "insert into rep_it.clients (organization_id) values ($1) returning id",
        [tenant],
      );

      const client = { type: "client", id: row!.id };

      await s.asRole(owner);

      const ada = await contacts
        .savePerson({
          organizationId: tenant,
          input: { name: "Ada", email: guardian.email },
        })
        .orThrow();

      const person = { type: "person", id: ada.id };

      expect(
        await relations
          .link({
            source: person,
            target: client,
            input: {
              kind: "represents",
              data: { role: "uncle", authority: "act" },
            },
          })
          .then((r) => (r.ok ? "ok" : r.error.hint)),
      ).toBe("RELATION_DATA_INVALID");
      expect(
        await relations
          .link({
            source: person,
            target: client,
            input: {
              kind: "represents",
              data: {
                role: "guardian",
                authority: "inform",
                valid_from: "2026-12-01",
                valid_until: "2026-01-01",
              },
            },
          })
          .then((r) => (r.ok ? "ok" : r.error.hint)),
      ).toBe("RELATION_DATA_INVALID");
      await relations
        .link({
          source: person,
          target: client,
          input: {
            kind: "represents",
            data: { role: "guardian", authority: "inform" },
          },
        })
        .orThrow();

      const [representative] = await contacts
        .representativesOf({ subjectType: "client", subjectId: client.id })
        .orThrow();

      expect(representative).toMatchObject({
        personId: ada.id,
        name: "Ada",
        role: "guardian",
        authority: "inform",
        active: true,
      });

      const invite = await guests
        .invite({ email: guardian.email, party: person })
        .orThrow();

      await s.asRole(guardian);
      await guests.accept(invite.token!).orThrow();
      expect(await guests.can({ subject: client }).orThrow()).toBe(true);
      expect(
        await guests.can({ subject: client, action: "comment" }).orThrow(),
      ).toBe(false);
      expect(await contacts.representedByMe(tenant).orThrow()).toEqual([
        expect.objectContaining({
          subjectType: "client",
          subjectId: client.id,
          role: "guardian",
          authority: "inform",
        }),
      ]);

      await s.asRole(owner);
      await relations
        .link({
          source: person,
          target: client,
          input: {
            kind: "represents",
            data: { role: "guardian", authority: "act" },
          },
        })
        .orThrow();
      await s.asRole(guardian);
      expect(
        await guests.can({ subject: client, action: "comment" }).orThrow(),
      ).toBe(true);
      await comments
        .create({ subject: client, comment: { body: "Signed for her" } })
        .orThrow();

      await s.asRole(owner);
      await relations
        .link({
          source: person,
          target: client,
          input: {
            kind: "represents",
            data: {
              role: "guardian",
              authority: "act",
              valid_until: "2020-01-01",
            },
          },
        })
        .orThrow();
      expect(
        await contacts
          .representativesOf({ subjectType: "client", subjectId: client.id })
          .orThrow(),
      ).toEqual([expect.objectContaining({ active: false })]);
      await s.asRole(guardian);
      expect(await guests.can({ subject: client }).orThrow()).toBe(false);
      expect(await contacts.representedByMe(tenant).orThrow()).toEqual([]);

      await s.asRole(owner);
      await relations
        .link({
          source: person,
          target: client,
          input: {
            kind: "represents",
            data: { role: "guardian", authority: "inform" },
          },
        })
        .orThrow();
      await relations
        .unlink({
          source: person,
          target: client,
          input: { kind: "represents" },
        })
        .orThrow();
      await s.asRole(guardian);
      expect(await guests.can({ subject: client }).orThrow()).toBe(false);
    } finally {
      await s.close();
    }
  });
});
