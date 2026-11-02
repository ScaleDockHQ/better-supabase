import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable, ROLES, USERS, withCentraKit } from "./stack.ts";

const live = await reachable();

// The old conversations policy let every file_node conversation reach
// can_subject, and can_subject decided visibility. The new policy keeps the
// same decision, but first prunes rows whose subject is not visible at all.
// The baseline below asks can_subject_for, the same question the old policy
// asked, so both policies must return the same conversations for every actor.
describe.skipIf(!live)("conversation visibility on file_node subjects", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("keeps the same visibility for two tenants, a share and anon", async () => {
    await withCentraKit(pool, async (s) => {
      await s.as("service");

      const makeOrganization = async (name: string) =>
        (
          (await s.rows<{ id: string }>(
            "insert into centrakit.organizations (name, slug) values ($1, $2) returning id",
            [name, `${name.toLowerCase()}-${crypto.randomUUID().slice(0, 8)}`],
          )) as [{ id: string }]
        )[0].id;

      const orgA = await makeOrganization("Acme");
      const orgB = await makeOrganization("Beta");

      // A custom role has no keys: the member belongs to Acme but holds no
      // comments.read, so the tenant branch cannot open its conversations.
      const restrictedRole = crypto.randomUUID();
      await s.client.query(
        `insert into centrakit.roles (id, scope, key, name, system)
         values ($1, 'organization', 'restricted', 'Restricted', false)`,
        [restrictedRole],
      );
      await s.client.query(
        `insert into centrakit.organization_users (organization_id, user_id, role_id)
         values ($1, $2, $3), ($1, $4, $5), ($6, $7, $8)`,
        [
          orgA,
          USERS.owner,
          ROLES.owner,
          USERS.member,
          restrictedRole,
          orgB,
          USERS.admin,
          ROLES.admin,
        ],
      );

      const nodes = await s.rows<{ id: string; organization_id: string }>(
        `insert into centrakit.file_node (organization_id, kind, name, created_by)
         values ($1, 'file', 'acme-a', $2), ($1, 'file', 'acme-b', $2),
                ($3, 'file', 'beta-a', $4), ($3, 'file', 'beta-b', $4)
         returning id, organization_id`,
        [orgA, USERS.owner, orgB, USERS.admin],
      );

      const [a1, a2, b1, b2] = nodes;

      // The member reads acme-b through a viewer grant; the support user is
      // in no organization and reads beta-a through a cross-tenant grant.
      await s.client.query(
        `insert into centrakit.file_node_grant (organization_id, file_node_id, user_id, role)
         values ($1, $2, $3, 'viewer'), ($4, $5, $6, 'viewer')`,
        [orgA, a2?.id, USERS.member, orgB, b1?.id, USERS.support],
      );

      const conversations = await s.rows<{ id: string }>(
        `insert into better_supabase.conversations
           (tenant_id, kind, access, subject_type, subject_id, title)
         values
           ($1, 'subject', 'subject', 'file_node', $2, 'acme-a'),
           ($1, 'subject', 'subject', 'file_node', $3, 'acme-b'),
           ($4, 'subject', 'subject', 'file_node', $5, 'beta-a'),
           ($4, 'subject', 'subject', 'file_node', $6, 'beta-b'),
           ($1, 'channel', 'tenant', null, null, 'acme-channel')
         returning id`,
        [orgA, a1?.id, a2?.id, orgB, b1?.id, b2?.id],
      );

      await s.client.query(
        `insert into better_supabase.messages (tenant_id, conversation_id, body, author_id, sent_at)
         select $1, c.id, c.title, $2, now()
         from better_supabase.conversations c where c.id = any ($3::uuid[])`,
        [orgA, USERS.owner, conversations.map((c) => c.id)],
      );

      const ids = (rows: readonly { id: string }[]) =>
        rows.map((row) => row.id).toSorted();

      // The old policy's decision: can_subject for a subject conversation,
      // the tenant's comments.read for a tenant one.
      const baseline = async (user: string) =>
        ids(
          await s.rows<{ id: string }>(
            `select c.id::text as id
             from better_supabase.conversations c
             where case c.access
               when 'subject' then better_supabase.can_subject_for($1, c.subject_type, c.subject_id, 'read')
               when 'tenant' then better_supabase.can_user($1, 'tenant', c.tenant_id, 'comments.read')
               else false
             end`,
            [user],
          ),
        );

      const visible = async (who: "owner" | "member" | "support") => {
        await s.as(who);
        await s.client.query("set local role authenticated");

        try {
          return ids(
            await s.rows<{ id: string }>(
              "select id::text as id from better_supabase.conversations",
            ),
          );
        } finally {
          await s.client.query("reset role");
        }
      };

      // Anon has no select grant on conversations, so it cannot see a row.
      await s.client.query(
        "select set_config('request.jwt.claims', $1, true)",
        [JSON.stringify({ role: "anon" })],
      );
      await s.client.query("set local role anon");

      try {
        expect(
          await s.hint("(select count(*) from better_supabase.conversations)"),
        ).toMatch(/Grant the required privileges|permission denied/i);
      } finally {
        await s.client.query("reset role");
      }

      expect(await visible("owner")).toEqual(
        ids(
          await s.rows<{ id: string }>(
            "select id::text as id from better_supabase.conversations where title in ('acme-a', 'acme-b', 'acme-channel')",
          ),
        ),
      );
      expect(await visible("owner")).toEqual(await baseline(USERS.owner));

      expect(await visible("member")).toEqual(
        ids(
          await s.rows<{ id: string }>(
            "select id::text as id from better_supabase.conversations where title = 'acme-b'",
          ),
        ),
      );
      expect(await visible("member")).toEqual(await baseline(USERS.member));

      expect(await visible("support")).toEqual(
        ids(
          await s.rows<{ id: string }>(
            "select id::text as id from better_supabase.conversations where title = 'beta-a'",
          ),
        ),
      );
      expect(await visible("support")).toEqual(await baseline(USERS.support));

      // A member with no comments.create sees the conversation but cannot
      // comment on its record: the set check is about reading, not writing.
      await s.as("member");
      await s.client.query("set local role authenticated");

      expect(
        await s.value<boolean>(
          "better_supabase.can_subject('file_node', $1, 'comment')",
          [a2?.id],
        ),
      ).toBe(false);
      await s.client.query("reset role");
    });
  });
});
