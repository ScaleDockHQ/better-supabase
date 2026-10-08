import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/registry.ts";

import { endSessions } from "../../src/server/suspend-account.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

async function teamSchema(s: BlockSession): Promise<string> {
  const schema = `bs_suspend_${crypto.randomUUID().slice(0, 8)}`;
  await s.client.query(`
    create schema ${schema};
    create table ${schema}.team_members (
      organization_id uuid not null,
      user_id uuid not null references auth.users (id) on delete cascade,
      role text not null,
      suspended_at timestamptz,
      primary key (organization_id, user_id)
    );
  `);
  return schema;
}

const layout = (schema: string): ModuleLayout => ({
  modules: {
    access: { schema },
    tenant: {
      schema,
      mode: "adopt",
      tables: { memberships: `${schema}.team_members` },
      columns: {
        memberships: {
          updatedAt: null,
          lastUsedAt: null,
          disabledAt: "suspended_at",
        },
      },
    },
    organizations: { schema },
  },
});

describe.skipIf(!live)("membership suspension", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("keeps the role and takes away every permission until resumed", async () => {
    const s = await BlockSession.open(pool);
    try {
      const schema = await teamSchema(s);
      await s.install(["organizations"], layout(schema));
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      await s.as(owner);
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Suspend", slug: `suspend-${owner.id.slice(0, 8)}` }],
      );
      await s.service();
      await s.client.query(
        `insert into ${schema}.team_members (organization_id, user_id, role) values ($1, $2, 'admin'), ($1, $3, 'member')`,
        [organization, admin.id, member.id],
      );

      await s.as(admin);
      expect(
        await s.value<boolean>(`${schema}.suspend_member($1, $2)`, [
          organization,
          member.id,
        ]),
      ).toBe(true);
      expect(
        await s.value<boolean>(`${schema}.suspend_member($1, $2)`, [
          organization,
          member.id,
        ]),
      ).toBe(false);
      const listed = await s.rows<{
        user_id: string;
        role: string;
        disabled_at: Date | null;
      }>(`select * from ${schema}.list_members($1)`, [organization]);
      const suspended = listed.find((row) => row.user_id === member.id);
      expect(suspended?.role).toBe("member");
      expect(suspended?.disabled_at).toBeInstanceOf(Date);

      await s.as(member);
      expect(
        await s.value<boolean>(
          `${schema}.member_can($1, $2, 'organization.read')`,
          [member.id, organization],
        ),
      ).toBe(false);
      expect(
        await s.rows(
          `select * from ${schema}.tenant_ids_with('organization.read')`,
        ),
      ).toEqual([]);
      expect(
        await s.rows(`select * from ${schema}.member_organization_ids()`),
      ).toEqual([]);
      const mine = await s.rows<{ disabled_at: Date | null }>(
        `select * from ${schema}.list_my_organizations()`,
      );
      expect(mine).toHaveLength(1);
      expect(mine[0]?.disabled_at).toBeInstanceOf(Date);

      await s.as(admin);
      expect(
        await s.value<boolean>(`${schema}.resume_member($1, $2)`, [
          organization,
          member.id,
        ]),
      ).toBe(true);
      await s.as(member);
      expect(
        await s.value<boolean>(
          `${schema}.member_can($1, $2, 'organization.read')`,
          [member.id, organization],
        ),
      ).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("refuses self, the last owner, members above the caller and suspended new owners", async () => {
    const s = await BlockSession.open(pool);
    try {
      const schema = await teamSchema(s);
      await s.install(["organizations"], layout(schema));
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      await s.as(owner);
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Guarded", slug: `guarded-${owner.id.slice(0, 8)}` }],
      );
      await s.service();
      await s.client.query(
        `insert into ${schema}.team_members (organization_id, user_id, role) values ($1, $2, 'admin'), ($1, $3, 'member')`,
        [organization, admin.id, member.id],
      );

      await s.as(owner);
      expect(
        await s.hint(`${schema}.suspend_member($1, $2)`, [
          organization,
          owner.id,
        ]),
      ).toBe("ORGANIZATION_SELF");
      await s.as(admin);
      expect(
        await s.hint(`${schema}.suspend_member($1, $2)`, [
          organization,
          owner.id,
        ]),
      ).toBe("ORGANIZATION_ROLE_CEILING");
      await s.as(member);
      expect(
        await s.hint(`${schema}.suspend_member($1, $2)`, [
          organization,
          admin.id,
        ]),
      ).toBe("ORGANIZATION_FORBIDDEN");

      await s.service();
      expect(
        await s.hint(`${schema}.suspend_member($1, $2)`, [
          organization,
          owner.id,
        ]),
      ).toBe("ORGANIZATION_OWNER_REQUIRED");

      await s.value(`${schema}.suspend_member($1, $2)`, [
        organization,
        member.id,
      ]);
      await s.as(owner);
      expect(
        await s.hint(`${schema}.transfer_ownership($1, $2)`, [
          organization,
          member.id,
        ]),
      ).toBe("ORGANIZATION_MEMBER_SUSPENDED");

      await s.service();
      await s.client.query(
        `update ${schema}.team_members set role = 'owner' where organization_id = $1 and user_id = $2`,
        [organization, member.id],
      );
      await s.client.query("savepoint deferred");
      await s.client.query(
        `update ${schema}.team_members set role = 'admin' where organization_id = $1 and user_id = $2`,
        [organization, owner.id],
      );
      const failure = await s.client
        .query("set constraints all immediate")
        .then(
          () => "no error",
          (error: unknown) => (error as { hint?: string }).hint,
        );
      await s.client.query("rollback to savepoint deferred");
      expect(failure).toBe("ORGANIZATION_OWNER_REQUIRED");
    } finally {
      await s.close();
    }
  });

  it("ends every session and refresh token of a user", async () => {
    const s = await BlockSession.open(pool);
    try {
      const user = await s.user("signed-in");
      const other = await s.user("other");
      for (const owner of [user, user, other]) {
        const session = crypto.randomUUID();
        await s.client.query(
          "insert into auth.sessions (id, user_id, created_at, updated_at) values ($1, $2, now(), now())",
          [session, owner.id],
        );
        await s.client.query(
          "insert into auth.refresh_tokens (instance_id, token, user_id, revoked, session_id, created_at, updated_at) values ('00000000-0000-0000-0000-000000000000', $1, $2, false, $3, now(), now())",
          [crypto.randomUUID(), owner.id, session],
        );
      }
      expect(await endSessions(s.sql, user.id).orThrow()).toEqual({
        userId: user.id,
        ended: 2,
      });
      const left = await s.rows<{ user_id: string }>(
        "select user_id::text from auth.refresh_tokens where user_id in ($1, $2)",
        [user.id, other.id],
      );
      expect(left).toEqual([{ user_id: other.id }]);
    } finally {
      await s.close();
    }
  });
});
