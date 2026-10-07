import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/registry.ts";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/** An adopted memberships table in its own schema, with text roles. */
async function teamSchema(s: BlockSession): Promise<string> {
  const schema = `bs_team_${crypto.randomUUID().slice(0, 8)}`;
  await s.client.query(`
    create schema ${schema};
    create table ${schema}.team_members (
      organization_id uuid not null,
      user_id uuid not null references auth.users (id) on delete cascade,
      role text not null,
      primary key (organization_id, user_id)
    );
  `);
  return schema;
}

function adopted(
  schema: string,
  organizations: Record<string, unknown> = {},
): ModuleLayout {
  return {
    modules: {
      access: { schema },
      tenant: {
        schema,
        mode: "adopt",
        tables: { memberships: `${schema}.team_members` },
        columns: { memberships: { updatedAt: null, lastUsedAt: null } },
      },
      organizations: { schema, ...organizations },
    },
  };
}

describe.skipIf(!live)("organizations member guards", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("checks the own-role rule and can_assign in update_member_role under an external guard", async () => {
    const s = await BlockSession.open(pool);
    try {
      const schema = await teamSchema(s);
      // An external guard that, like PermDock's assignment triggers, checks
      // client writes only, so it never sees a security definer function's.
      await s.client.query(`
        create function ${schema}.client_guard() returns trigger language plpgsql as $$
        begin
          if current_user not in ('anon', 'authenticated') then
            return new;
          end if;
          raise exception 'clients may not write memberships';
        end;
        $$;
        create trigger client_guard before insert or update on ${schema}.team_members
          for each row execute function ${schema}.client_guard();
      `);
      await s.install(
        ["organizations"],
        adopted(schema, { options: { assignmentGuard: "external" } }),
      );
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      await s.as(owner);
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Guarded", slug: `guarded-${owner.id.slice(0, 8)}` }],
      );
      await s.client.query(
        `insert into ${schema}.team_members (organization_id, user_id, role) values ($1, $2, 'admin'), ($1, $3, 'member')`,
        [organization, admin.id, member.id],
      );
      const role = (user: { id: string }) =>
        s.value<string>(
          `(select role from ${schema}.team_members where organization_id = $1 and user_id = $2)`,
          [organization, user.id],
        );

      await s.as(admin);
      expect(
        await s.hint(`${schema}.update_member_role($1, $2, 'member')`, [
          organization,
          owner.id,
        ]),
      ).toBe("ORGANIZATION_ROLE_CEILING");
      expect(
        await s.hint(`${schema}.update_member_role($1, $2, 'owner')`, [
          organization,
          member.id,
        ]),
      ).toBe("ORGANIZATION_ROLE_CEILING");
      expect(
        await s.hint(`${schema}.update_member_role($1, $2, 'member')`, [
          organization,
          admin.id,
        ]),
      ).toBe("ORGANIZATION_SELF_ROLE");
      expect(await role(owner)).toBe("owner");
      await s.value(`${schema}.update_member_role($1, $2, 'viewer')`, [
        organization,
        member.id,
      ]);
      expect(await role(member)).toBe("viewer");

      await s.as(owner);
      expect(
        await s.hint(`${schema}.update_member_role($1, $2, 'admin')`, [
          organization,
          owner.id,
        ]),
      ).toBe("ORGANIZATION_SELF_ROLE");
      await s.value(`${schema}.update_member_role($1, $2, 'owner')`, [
        organization,
        member.id,
      ]);
      expect(await role(member)).toBe("owner");
    } finally {
      await s.close();
    }
  });

  it("checks client writes only, so the app's own security definer functions write memberships", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations"]);
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      const newcomer = await s.user("newcomer");
      const organization = await s.organization(owner, { admin, member });
      const schema = `bs_app_${crypto.randomUUID().slice(0, 8)}`;
      await s.client.query(`
        create schema ${schema};
        grant usage on schema ${schema} to authenticated;
        create function ${schema}.seat(organization uuid, member uuid, role text) returns void
        language sql security definer set search_path = '' as $$
          insert into better_supabase.memberships (organization_id, user_id, role)
          values (organization, member, role)
        $$;
        grant execute on function ${schema}.seat(uuid, uuid, text) to authenticated;
        grant update on better_supabase.memberships to authenticated;
        create policy bs_test_update on better_supabase.memberships for update to authenticated
          using (true) with check (true);
      `);
      const role = (user: { id: string }) =>
        s.value<string>(
          "(select role from better_supabase.memberships where organization_id = $1 and user_id = $2)",
          [organization, user.id],
        );

      await s.asRole(admin);
      await s.value(`${schema}.seat($1, $2, 'owner')`, [
        organization,
        newcomer.id,
      ]);
      const update = (user: { id: string }, value: string) =>
        s.hint(
          "update better_supabase.memberships set role = $3 where organization_id = $1 and user_id = $2",
          [organization, user.id, value],
        );
      expect(await update(owner, "member")).toBe("ORGANIZATION_ROLE_CEILING");
      expect(await update(admin, "viewer")).toBe("ORGANIZATION_SELF_ROLE");
      expect(await update(member, "viewer")).toBe("no error");
      await s.service();
      expect(await role(newcomer)).toBe("owner");
      expect(await role(member)).toBe("viewer");
      expect(await role(owner)).toBe("owner");
    } finally {
      await s.close();
    }
  });
});
