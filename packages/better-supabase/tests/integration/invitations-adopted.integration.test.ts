import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/registry.ts";

import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

/**
 * An authorization provider's schema: memberships with text roles, declared
 * roles (`owner`, `admin`, `member`) and tenant custom roles, and the
 * functions the provider access model calls.
 */
async function providerSchema(
  s: BlockSession,
  organization: string,
  members: Readonly<Record<string, TestUser>>,
): Promise<string> {
  const schema = `bs_authz_${crypto.randomUUID().slice(0, 8)}`;
  await s.client.query(`
    create schema ${schema};
    create table ${schema}.team_members (
      organization_id uuid not null,
      user_id uuid not null references auth.users (id) on delete cascade,
      role text not null,
      primary key (organization_id, user_id)
    );
    create table ${schema}.custom_roles (organization_id uuid, key text);
    insert into ${schema}.custom_roles values ('${organization}', 'auditor');
    create function ${schema}.permitted_organization_ids(permission text) returns setof uuid
      language sql stable as $$
        select m.organization_id from ${schema}.team_members m
        where m.user_id = auth.uid() and m.role in ('owner', 'admin') $$;
    create function ${schema}.is_platform(permission text) returns boolean
      language sql stable as $$ select false $$;
    create function ${schema}.can_assign(p_role text, p_scope_id text) returns boolean
      language sql stable as $$ select p_role <> 'owner' $$;
    -- Knows only the declared roles.
    create function ${schema}.can_assign_for(p_user uuid, p_role text, p_scope_id text) returns boolean
      language sql stable as $$ select p_role in ('admin', 'member') $$;
    create function ${schema}.can_assign_any_for(p_user uuid, p_role text, p_tenant uuid, p_scope text, p_scope_id text) returns boolean
      language sql stable as $$
        select p_scope = 'organization' and p_scope_id = p_tenant::text
          and (p_role in ('admin', 'member')
            or exists (select 1 from ${schema}.custom_roles r where r.organization_id = p_tenant and r.key = p_role)) $$;
  `);
  for (const [role, user] of Object.entries(members))
    await s.client.query(
      `insert into ${schema}.team_members values ($1, $2, $3)`,
      [organization, user.id, role],
    );
  return schema;
}

const provider = (
  schema: string,
  canAssignFor?: string,
): NonNullable<ModuleLayout["accessProvider"]> => ({
  name: "test",
  scope: "organization",
  idType: "uuid",
  functions: {
    idsWith: `${schema}.permitted_{scope}_ids({permission})`,
    isPlatform: `${schema}.is_platform({permission})`,
    canAssign: `${schema}.can_assign({role}, {tenant}::text)`,
    ...(canAssignFor ? { canAssignFor } : {}),
  },
});

function providerLayout(schema: string, canAssignFor?: string): ModuleLayout {
  return {
    accessProvider: provider(schema, canAssignFor),
    modules: {
      access: { model: "provider" },
      tenant: {
        schema,
        mode: "adopt",
        tables: { memberships: `${schema}.team_members` },
        columns: { memberships: { updatedAt: null, lastUsedAt: null } },
      },
      invitations: { schema },
    },
  };
}

describe.skipIf(!live)("invitations in adopted tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("accepts an invitation to a tenant custom role through the provider's canAssignFor", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const invitee = await s.user("invitee");
      const late = await s.user("late");
      const organization = crypto.randomUUID();
      const schema = await providerSchema(s, organization, { owner });

      await s.install(
        ["invitations"],
        providerLayout(
          schema,
          `${schema}.can_assign_for({user}, {role}, {tenant}::text)`,
        ),
      );
      await s.as(owner);
      const refused = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'auditor')`,
        [organization, late.email],
      );
      await s.as(late);
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [refused.token]),
      ).toBe("INVITATION_INVITER_REVOKED");

      await s.install(
        ["invitations"],
        providerLayout(
          schema,
          `${schema}.can_assign_any_for({user}, {role}, {tenant}, 'organization', {tenant}::text)`,
        ),
      );
      await s.as(owner);
      const invite = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'auditor')`,
        [organization, invitee.email],
      );
      await s.as(invitee);
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [invite.token]),
      ).toBe(organization);
      expect(
        await s.value(
          `(select role from ${schema}.team_members where organization_id = $1 and user_id = $2)`,
          [organization, invitee.id],
        ),
      ).toBe("auditor");
      await s.as(late);
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [refused.token]),
      ).toBe(organization);
    } finally {
      await s.close();
    }
  });

  it("checks the inviter with sql.modules.access.functions.canAssignFor", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const invitee = await s.user("invitee");
      const organization = crypto.randomUUID();
      const schema = await providerSchema(s, organization, { owner });
      const layout = providerLayout(schema);
      await s.install(["invitations"], {
        ...layout,
        modules: {
          ...layout.modules,
          access: {
            model: "provider",
            functions: {
              canAssignFor: `{role} <> 'auditor' and {user} is not null and {tenant} is not null`,
            },
          },
        },
      });
      await s.as(owner);
      const invite = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'auditor')`,
        [organization, invitee.email],
      );
      await s.as(invitee);
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [invite.token]),
      ).toBe("INVITATION_INVITER_REVOKED");
    } finally {
      await s.close();
    }
  });

  it("invites to tenant and platform roles in one shared table with a uuid role column", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const staff = await s.user("staff");
      const member = await s.user("member");
      const agent = await s.user("agent");
      const organization = crypto.randomUUID();
      const schema = await sharedSchema(s, organization, owner, staff);
      await s.install(["invitations"], sharedLayout(schema));
      const roleKey = (table: string, user: TestUser) =>
        s.value<string>(
          `(select r.key from ${schema}.${table} m join ${schema}.roles r on r.id = m.role_id where m.user_id = $1)`,
          [user.id],
        );

      await s.as(staff);
      const platform = await s.value<{ token: string; prefill: unknown }>(
        `${schema}.invite_member(null, $1, 'support', prefill => $2)`,
        [agent.email, { name: "Agent" }],
      );
      expect(platform.prefill).toEqual({ name: "Agent" });
      const adminId = await s.value<string>(
        `(select id::text from ${schema}.roles where key = 'admin')`,
      );
      for (const tenantRole of ["admin", adminId]) {
        expect(
          await s.hint(`${schema}.invite_member(null, $1, $2)`, [
            agent.email,
            tenantRole,
          ]),
        ).toBe("INVITATION_ROLE_UNKNOWN");
      }
      await s.as(agent);
      expect(
        await s.value<{ prefill: unknown; role: string }>(
          `${schema}.invitation_preview($1)`,
          [platform.token],
        ),
      ).toMatchObject({ prefill: { name: "Agent" } });
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [platform.token]),
      ).toBeNull();
      expect(await roleKey("user_roles", agent)).toBe("support");

      await s.as(owner);
      const tenant = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, member.email],
      );
      await s.as(member);
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [tenant.token]),
      ).toBe(organization);
      expect(await roleKey("team_members", member)).toBe("member");
    } finally {
      await s.close();
    }
  });

  it("resolves tenant roles only among the roles roleThrough.where names", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const staff = await s.user("staff");
      const member = await s.user("member");
      const schema = await sharedSchema(s, crypto.randomUUID(), owner, staff);
      const layout = sharedLayout(schema);
      await s.install(["organizations", "invitations"], {
        ...layout,
        modules: { ...layout.modules, organizations: { schema } },
      });
      const supportId = await s.value<string>(
        `(select id::text from ${schema}.roles where key = 'support')`,
      );
      await s.as(owner);
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Shared", slug: `shared-${owner.id.slice(0, 8)}` }],
      );
      for (const platformRole of ["support", supportId]) {
        expect(
          await s.hint(`${schema}.invite_member($1, $2, $3)`, [
            organization,
            member.email,
            platformRole,
          ]),
        ).toBe("INVITATION_ROLE_UNKNOWN");
      }
      const invite = await s.value<{ id: string; token: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, member.email],
      );
      expect(
        await s.hint(`${schema}.update_invitation($1, null, $2)`, [
          invite.id,
          supportId,
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");

      await s.client.query(
        `update ${schema}.invitations set role_id = $2 where id = $1`,
        [invite.id, supportId],
      );
      await s.as(member);
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [invite.token]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      await s.client.query(
        `update ${schema}.invitations set role_id = (select id from ${schema}.roles where key = 'member') where id = $1`,
        [invite.id],
      );
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [invite.token]),
      ).toBe(organization);

      await s.as(owner);
      for (const platformRole of ["support", supportId]) {
        expect(
          await s.hint(`${schema}.update_member_role($1, $2, $3)`, [
            organization,
            member.id,
            platformRole,
          ]),
        ).toBe("ORGANIZATION_ROLE_UNKNOWN");
      }
      await s.value(`${schema}.update_member_role($1, $2, 'admin')`, [
        organization,
        member.id,
      ]);
      expect(
        await s.value<string>(
          `(select r.key from ${schema}.team_members m join ${schema}.roles r on r.id = m.role_id where m.organization_id = $1 and m.user_id = $2)`,
          [organization, member.id],
        ),
      ).toBe("admin");
    } finally {
      await s.close();
    }
  });

  it("keeps every write to the memberships and platform roles tables within where", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const staff = await s.user("staff");
      const member = await s.user("member");
      const organization = crypto.randomUUID();
      const schema = await sharedSchema(s, organization, owner, staff);
      await s.install(["invitations"], sharedLayout(schema));
      const roleId = (key: string) =>
        s.value<string>(`(select id from ${schema}.roles where key = $1)`, [
          key,
        ]);
      const support = await roleId("support");
      const admin = await roleId("admin");

      await s.service();
      expect(
        await s.hint(`insert into ${schema}.team_members values ($1, $2, $3)`, [
          organization,
          member.id,
          support,
        ]),
      ).toBe("MEMBERSHIP_ROLE_SCOPE");
      expect(
        await s.hint(
          `update ${schema}.team_members set role_id = $2 where user_id = $1`,
          [owner.id, support],
        ),
      ).toBe("MEMBERSHIP_ROLE_SCOPE");
      expect(
        await s.hint(`insert into ${schema}.team_members values ($1, $2, $3)`, [
          organization,
          member.id,
          admin,
        ]),
      ).toBe("no error");

      expect(
        await s.hint(`insert into ${schema}.user_roles values ($1, $2)`, [
          staff.id,
          admin,
        ]),
      ).toBe("PLATFORM_ROLE_SCOPE");
      expect(
        await s.hint(`insert into ${schema}.user_roles values ($1, $2)`, [
          staff.id,
          support,
        ]),
      ).toBe("no error");
    } finally {
      await s.close();
    }
  });

  it("resolves a role key among the tenant's own custom roles", async () => {
    const s = await BlockSession.open(pool);
    try {
      const owner = await s.user("owner");
      const staff = await s.user("staff");
      const member = await s.user("member");
      const schema = await sharedSchema(s, crypto.randomUUID(), owner, staff);
      const layout = sharedLayout(schema);
      const tenant = layout.modules!["tenant"]!;
      await s.install(["organizations", "invitations"], {
        ...layout,
        modules: {
          ...layout.modules,
          tenant: {
            ...tenant,
            options: {
              roleThrough: {
                table: `${schema}.roles`,
                id: "id",
                column: "key",
                tenant: "organization_id",
                where: "{row}.scope = 'organization'",
              },
            },
          },
          organizations: { schema },
        },
      });
      await s.as(owner);
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Custom", slug: `custom-${owner.id.slice(0, 8)}` }],
      );
      const [elsewhereRow] = await s.rows<{ id: string }>(
        `insert into ${schema}.roles (key, organization_id) values ('auditor', gen_random_uuid()) returning id::text`,
      );
      const [ownRow] = await s.rows<{ id: string }>(
        `insert into ${schema}.roles (key, organization_id) values ('auditor', $1) returning id::text`,
        [organization],
      );
      const own = ownRow!.id;
      const elsewhere = elsewhereRow!.id;
      const invite = await s.value<{ token: string; role: string }>(
        `${schema}.invite_member($1, $2, 'auditor')`,
        [organization, member.email],
      );
      expect(invite.role).toBe(own);
      expect(
        await s.hint(`${schema}.invite_member($1, $2, $3)`, [
          organization,
          `x-${member.email}`,
          elsewhere,
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      await s.as(member);
      await s.value(`${schema}.accept_invitation($1)`, [invite.token]);
      const stored = () =>
        s.value<string>(
          `(select role_id::text from ${schema}.team_members where organization_id = $1 and user_id = $2)`,
          [organization, member.id],
        );
      expect(await stored()).toBe(own);
      await s.as(owner);
      await s.value(`${schema}.update_member_role($1, $2, 'member')`, [
        organization,
        member.id,
      ]);
      await s.value(`${schema}.update_member_role($1, $2, 'auditor')`, [
        organization,
        member.id,
      ]);
      expect(await stored()).toBe(own);
    } finally {
      await s.close();
    }
  });
});

/**
 * One roles table for tenant and platform roles (uuid ids, a key, and the
 * tenant of a custom role), memberships and platform assignments that point
 * into it, and one invitations table for both kinds whose role column is a
 * uuid.
 */
async function sharedSchema(
  s: BlockSession,
  organization: string,
  owner: TestUser,
  staff: TestUser,
): Promise<string> {
  const schema = `bs_shared_${crypto.randomUUID().slice(0, 8)}`;
  await s.client.query(`
    create schema ${schema};
    create table ${schema}.roles (
      id uuid primary key default gen_random_uuid(),
      key text not null,
      organization_id uuid,
      scope text not null default 'organization'
    );
    insert into ${schema}.roles (key) values ('owner'), ('admin'), ('member');
    insert into ${schema}.roles (key, scope) values ('support', 'system');
    create table ${schema}.team_members (
      organization_id uuid not null,
      user_id uuid not null references auth.users (id) on delete cascade,
      role_id uuid not null references ${schema}.roles (id),
      primary key (organization_id, user_id)
    );
    insert into ${schema}.team_members
      select '${organization}', '${owner.id}', id from ${schema}.roles where key = 'owner';
    create table ${schema}.user_roles (
      user_id uuid not null references auth.users (id) on delete cascade,
      role_id uuid not null references ${schema}.roles (id),
      primary key (user_id, role_id)
    );
    create table ${schema}.invitations (
      id uuid primary key default gen_random_uuid(),
      organization_id uuid,
      email text not null,
      role_id uuid not null references ${schema}.roles (id),
      token_hash text not null unique,
      invited_by uuid,
      created_at timestamptz not null default now(),
      expires_at timestamptz not null,
      accepted_at timestamptz,
      accepted_by uuid,
      declined_at timestamptz,
      revoked_at timestamptz,
      prefill jsonb not null default '{}'
    );
    create function ${schema}.permitted_organization_ids(permission text) returns setof uuid
      language sql stable as $$
        select m.organization_id from ${schema}.team_members m
        join ${schema}.roles r on r.id = m.role_id
        where m.user_id = auth.uid() and r.key in ('owner', 'admin') $$;
    create function ${schema}.is_platform(permission text) returns boolean
      language sql stable as $$ select auth.uid() = '${staff.id}' $$;
    create function ${schema}.can_assign(p_role text, p_scope_id text) returns boolean
      language sql stable as $$ select p_role <> 'owner' $$;
  `);
  return schema;
}

function sharedLayout(schema: string): ModuleLayout {
  const roles = { table: `${schema}.roles`, id: "id", column: "key" };
  return {
    accessProvider: provider(schema),
    modules: {
      access: { model: "provider" },
      tenant: {
        schema,
        mode: "adopt",
        tables: { memberships: `${schema}.team_members` },
        columns: {
          memberships: { role: "role_id", updatedAt: null, lastUsedAt: null },
        },
        options: {
          roleThrough: { ...roles, where: "{row}.scope = 'organization'" },
        },
      },
      invitations: {
        schema,
        mode: "adopt",
        tables: {
          invitations: `${schema}.invitations`,
          platformInvitations: `${schema}.invitations`,
        },
        columns: {
          invitations: { role: "role_id", updatedAt: null },
          platformInvitations: { role: "role_id", updatedAt: null },
        },
        options: {
          platformRoles: {
            table: `${schema}.user_roles`,
            user: "user_id",
            role: "role_id",
            through: { ...roles, where: "{row}.scope = 'system'" },
          },
        },
      },
    },
  };
}
