import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createComments } from "../../src/blocks/comments/index.ts";
import { createGuests, sqlTransport } from "../../src/blocks/guests/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: withBlockSubjects(
    { doc: { table: "guests_it.docs", idType: "uuid" } },
    ["comments"],
    {},
  ),
};

const TABLES = `create schema guests_it;
create table guests_it.docs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);
alter table guests_it.docs enable row level security;
create policy docs_read on guests_it.docs for select to authenticated using (true);
grant usage on schema guests_it to authenticated;
grant select on guests_it.docs to authenticated;`;

describe.skipIf(!live)("guests", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("invites a guest who comments on the one record they were granted", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.client.query(TABLES);
      await s.install(
        ["organizations", "outbox", "comments", "guests"],
        layout,
      );
      const owner = await s.user("owner");
      const client = await s.user("client", "client.test");
      const intruder = await s.user("intruder");
      const tenant = await s.organization(owner);

      const guests = createGuests({ transport: sqlTransport(s.sql), tenant });

      const comments = createComments({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.service();

      const [shared, other] = await s.rows<{ id: string }>(
        "insert into guests_it.docs (organization_id) values ($1), ($1) returning id",
        [tenant],
      );

      const doc = { type: "doc", id: shared!.id };

      await s.asRole(owner);

      const invite = await guests
        .invite({ email: client.email, name: "Client" })
        .orThrow();

      expect(invite).toMatchObject({ status: "invited", email: client.email });
      expect(invite.token).toMatch(/^[0-9a-f]{64}$/u);

      await s.asRole(intruder);
      expect(
        await guests.accept(invite.token!).then((r) => !r.ok && r.error.hint),
      ).toBe("GUEST_EMAIL_MISMATCH");

      await s.asRole(client);
      expect(await guests.accept(invite.token!).orThrow()).toMatchObject({
        status: "active",
        userId: client.id,
      });
      expect(await guests.can(doc).orThrow()).toBe(false);

      await s.asRole(owner);

      const grant = await guests
        .grant(invite.id, doc, { actions: ["comment"] })
        .orThrow();

      expect(grant.actions).toEqual(["read", "comment"]);
      expect(
        (await guests.grants(doc).orThrow()).map((row) => row.guest.email),
      ).toEqual([client.email]);

      await s.asRole(client);
      expect(await guests.can(doc, "comment").orThrow()).toBe(true);
      expect(await guests.can(doc, "upload").orThrow()).toBe(false);
      await comments.create(doc, { body: "Looks good to me" }).orThrow();
      expect(
        (await comments.list(doc).orThrow()).map((row) => row.body),
      ).toEqual(["Looks good to me"]);
      expect(
        await comments
          .create({ type: "doc", id: other!.id }, { body: "Not mine" })
          .then((r) => r.ok),
      ).toBe(false);

      const [membership] = await guests.mine().orThrow();

      expect(membership?.grants.map((row) => row.subject)).toEqual([doc]);
      expect(await guests.list().then((r) => !r.ok && r.error.hint)).toBe(
        "GUEST_FORBIDDEN",
      );

      await s.asRole(owner);
      await guests.revoke(invite.id).orThrow();
      await s.asRole(client);
      expect(await guests.can(doc).orThrow()).toBe(false);
      expect(await guests.mine().orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'guest%' order by position",
        [tenant],
      );

      expect(new Set(events.map((event) => event.type))).toEqual(
        new Set([
          "guest.invited",
          "guest.accepted",
          "guest_grant.created",
          "guest.revoked",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
