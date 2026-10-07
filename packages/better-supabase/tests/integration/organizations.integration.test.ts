import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { InvitationSent } from "../../src/blocks/organizations/index.ts";
import type { ModuleLayout } from "../../src/sql/registry.ts";

import {
  createOrganizations,
  sqlTransport,
} from "../../src/blocks/organizations/index.ts";
import { EventHub } from "../../src/core/events.ts";
import { renderModules } from "../../src/sql/registry.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query("select 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

const USERS = {
  owner: crypto.randomUUID(),
  admin: crypto.randomUUID(),
  member: crypto.randomUUID(),
  outsider: crypto.randomUUID(),
} as const;
type Who = keyof typeof USERS;
const email = (who: Who) => `${who}-${USERS[who]}@example.test`;

/** Runs each call in a savepoint, so a refused call leaves the test transaction usable. */
const savepointSql = (client: PoolClient) => ({
  async queryRaw(text: string, params: readonly unknown[] = []) {
    await client.query("savepoint call");
    try {
      const { rows } = await client.query(text, [...params]);
      await client.query("release savepoint call");
      return rows;
    } catch (error) {
      await client.query("rollback to savepoint call");
      throw error;
    }
  },
});

const LAYOUT: ModuleLayout = {
  modules: {
    organizations: { options: { reservedSlugs: ["admin"] } },
    invitations: { options: { prefill: true } },
  },
};

class Session {
  private readonly client: PoolClient;

  constructor(client: PoolClient) {
    this.client = client;
  }

  async as(who: Who | "anon"): Promise<void> {
    const claims =
      who === "anon"
        ? { role: "anon" }
        : { sub: USERS[who], role: "authenticated", email: email(who) };
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify(claims)],
    );
  }

  async value<T>(sql: string, params: unknown[] = []): Promise<T> {
    const { rows } = await this.client.query<{ value: T }>(
      `select ${sql} as value`,
      params,
    );
    return rows[0]!.value;
  }

  /** The hint of the error `sql` raises, rolled back to a savepoint. */
  async hint(sql: string, params: unknown[] = []): Promise<string> {
    await this.client.query("savepoint attempt");
    try {
      await this.client.query(`select ${sql}`, params);
      await this.client.query("set constraints all immediate");
    } catch (error) {
      await this.client.query("rollback to savepoint attempt");
      return (error as { hint?: string }).hint ?? (error as Error).message;
    }
    await this.client.query("release savepoint attempt");
    return "no error";
  }

  role(organization: string, who: Who): Promise<string | null> {
    return this.value(
      "(select role from better_supabase.memberships where organization_id = $1 and user_id = $2)",
      [organization, USERS[who]],
    );
  }
}

describe.skipIf(!live)("organizations and invitations", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("runs the organization lifecycle on the access contract", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    try {
      await client.query("begin");
      for (const who of Object.keys(USERS) as Who[]) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderModules(
        ["organizations", "invitations"],
        LAYOUT,
      ))
        await client.query(file.contents);

      await s.as("owner");
      const slug = `acme-${USERS.owner.slice(0, 8)}`;
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug }],
      );
      expect(await s.role(organization, "owner")).toBe("owner");
      expect(
        await s.hint("better_supabase.create_organization($1)", [
          { name: "x", slug: "admin" },
        ]),
      ).toBe("ORGANIZATION_SLUG_RESERVED");
      expect(
        await s.hint("better_supabase.create_organization($1)", [
          { name: "x", slug: "Bad Slug" },
        ]),
      ).toBe("ORGANIZATION_SLUG_INVALID");
      expect(
        await s.hint("better_supabase.create_organization($1)", [
          { name: "x", slug },
        ]),
      ).toBe("ORGANIZATION_SLUG_TAKEN");

      const invite = async (who: Who, role: string) =>
        s.value<{ token: string; id: string }>(
          "better_supabase.invite_member($1, $2, $3)",
          [organization, email(who), role],
        );
      const memberInvite = await invite("member", "member");
      await s.as("anon");
      const preview = await s.value<Record<string, unknown>>(
        "better_supabase.invitation_preview($1)",
        [memberInvite.token],
      );
      expect(preview).toMatchObject({
        status: "pending",
        role: "member",
        organization: { id: organization, name: "Acme" },
      });

      await s.as("member");
      expect(
        await s.value("better_supabase.accept_invitation($1)", [
          memberInvite.token,
        ]),
      ).toBe(organization);
      expect(
        await s.hint("better_supabase.accept_invitation($1)", [
          memberInvite.token,
        ]),
      ).toBe("INVITATION_INVALID");
      expect(
        await s.hint("better_supabase.update_member_role($1, $2, 'member')", [
          organization,
          USERS.owner,
        ]),
      ).toBe("ORGANIZATION_FORBIDDEN");

      await s.as("owner");
      expect(
        await s.hint("better_supabase.invite_member($1, $2, 'member')", [
          organization,
          email("member"),
        ]),
      ).toBe("INVITATION_ALREADY_MEMBER");
      const adminInvite = await invite("admin", "admin");
      await s.as("admin");
      await s.value("better_supabase.accept_invitation($1)", [
        adminInvite.token,
      ]);
      expect(
        await s.hint("better_supabase.update_member_role($1, $2, 'owner')", [
          organization,
          USERS.member,
        ]),
      ).toBe("ORGANIZATION_ROLE_CEILING");
      expect(
        await s.hint("better_supabase.update_member_role($1, $2, 'member')", [
          organization,
          USERS.admin,
        ]),
      ).toBe("ORGANIZATION_SELF_ROLE");
      expect(
        await s.value("better_supabase.update_member_role($1, $2, 'viewer')", [
          organization,
          USERS.member,
        ]),
      ).toBe(true);
      expect(await s.role(organization, "member")).toBe("viewer");

      const outsiderInvite = await invite("outsider", "member");
      await s.as("owner");
      await s.value("better_supabase.update_member_role($1, $2, 'member')", [
        organization,
        USERS.admin,
      ]);
      await s.as("outsider");
      expect(
        await s.hint("better_supabase.accept_invitation($1)", [
          outsiderInvite.token,
        ]),
      ).toBe("INVITATION_INVITER_REVOKED");
      expect(
        await s.value("better_supabase.decline_invitation($1)", [
          outsiderInvite.token,
        ]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.invitation_preview($1) ->> 'status'", [
          outsiderInvite.token,
        ]),
      ).toBe("declined");

      await s.as("owner");
      expect(
        await s.hint("better_supabase.leave_organization($1)", [organization]),
      ).toBe("ORGANIZATION_OWNER_REQUIRED");
      await s.value("better_supabase.transfer_ownership($1, $2)", [
        organization,
        USERS.admin,
      ]);
      expect(await s.role(organization, "admin")).toBe("owner");
      expect(await s.role(organization, "owner")).toBe("admin");
      await client.query("set constraints all immediate");

      await s.as("admin");
      expect(
        await s.value("better_supabase.mark_used($1)", [organization]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.delete_organization($1)", [
          organization,
        ]),
      ).toBe(true);
      expect(await s.role(organization, "member")).toBeNull();
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("fails closed on stale tenant claims, disabled organizations and non-owner transfers", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    try {
      await client.query("begin");
      for (const who of ["owner", "admin", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      const layout: ModuleLayout = {
        modules: {
          access: {
            activeTenant: "claim",
            roles: {
              owner: ["*"],
              admin: ["ownership.transfer", "members.*"],
              member: [],
            },
          },
        },
      };
      for (const file of renderModules(["organizations"], layout))
        await client.query(file.contents);

      await s.as("owner");
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Stale", slug: `stale-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        `insert into better_supabase.memberships (organization_id, user_id, role)
         values ($1, $2, 'admin'), ($1, $3, 'member')`,
        [organization, USERS.admin, USERS.member],
      );

      await s.as("member");
      await s.value("better_supabase.switch_organization($1)", [organization]);
      expect(
        await s.value(
          "(select raw_app_meta_data ->> 'tenant_id' from auth.users where id = $1)",
          [USERS.member],
        ),
      ).toBe(organization);
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({
          sub: USERS.member,
          role: "authenticated",
          tenant_id: organization,
        }),
      ]);
      expect(await s.value("better_supabase.current_tenant_id()")).toBe(
        organization,
      );

      await s.as("owner");
      await s.value("better_supabase.remove_member($1, $2)", [
        organization,
        USERS.member,
      ]);
      expect(
        await s.value(
          "(select raw_app_meta_data ->> 'tenant_id' from auth.users where id = $1)",
          [USERS.member],
        ),
      ).toBeNull();
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({
          sub: USERS.member,
          role: "authenticated",
          tenant_id: organization,
        }),
      ]);
      expect(await s.value("better_supabase.current_tenant_id()")).toBeNull();

      await s.as("admin");
      expect(
        await s.hint("better_supabase.transfer_ownership($1, $2)", [
          organization,
          USERS.admin,
        ]),
      ).toBe("ORGANIZATION_FORBIDDEN");

      await client.query(
        "update better_supabase.organizations set disabled_at = now() where id = $1",
        [organization],
      );
      await s.as("owner");
      expect(
        await s.value("better_supabase.has_organization_role($1, '{owner}')", [
          organization,
        ]),
      ).toBe(false);
      expect(
        await s.value(
          "better_supabase.can('organization', $1, 'organization.read')",
          [organization],
        ),
      ).toBe(false);
      expect(
        await s.value(
          "array(select better_supabase.member_organization_ids())::text[]",
        ),
      ).toEqual([]);
      await client.query("set local role authenticated");
      expect(
        await s.hint("better_supabase.tenant_disabled($1)", [organization]),
      ).toMatch(/permission denied/);
      await client.query("reset role");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("stores catalog role ids and resolves role keys", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_catalog_${USERS.owner.slice(0, 8)}`;
    const module = { schema };
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      const layout: ModuleLayout = {
        modules: {
          access: { ...module, model: "catalog" },
          tenant: module,
          organizations: module,
          invitations: module,
        },
      };
      for (const file of renderModules(
        ["organizations", "invitations"],
        layout,
      ))
        await client.query(file.contents);
      await client.query(`
        insert into ${schema}.roles (id, key) values
          ('00000000-0000-4000-8000-00000000f001', 'owner'),
          ('00000000-0000-4000-8000-00000000f002', 'member');
        insert into ${schema}.permissions (id, key) values
          ('00000000-0000-4000-8000-00000000f101', 'members.invite');
        insert into ${schema}.role_permissions (role_id, permission_id) values
          ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-00000000f101');
      `);

      await s.as("owner");
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Catalog", slug: `catalog-${USERS.owner.slice(0, 8)}` }],
      );
      const invite = await s.value<{ token: string; role: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, email("member")],
      );
      expect(invite.role).toBe("00000000-0000-4000-8000-00000000f002");
      await s.as("member");
      await s.value(`${schema}.accept_invitation($1)`, [invite.token]);
      expect(
        await s.value(
          `(select role::text from ${schema}.memberships where organization_id = $1 and user_id = $2)`,
          [organization, USERS.member],
        ),
      ).toBe("00000000-0000-4000-8000-00000000f002");

      // A role still held by a member can't be deleted, and the
      // organization's rows go with it.
      await s.as("owner");
      await client.query("savepoint role_delete");
      await expect(
        client.query(`delete from ${schema}.roles where key = 'member'`),
      ).rejects.toMatchObject({ code: "23503" });
      await client.query("rollback to savepoint role_delete");
      await s.value(`${schema}.invite_member($1, $2, 'member')`, [
        organization,
        "later@example.test",
      ]);
      await client.query(`delete from ${schema}.organizations where id = $1`, [
        organization,
      ]);
      expect(
        await s.value(
          `(select (select count(*) from ${schema}.memberships where organization_id = $1) + (select count(*) from ${schema}.invitations where organization_id = $1))::int`,
          [organization],
        ),
      ).toBe(0);
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ role: "service_role" }),
      ]);
      expect(
        await s.hint(`${schema}.invite_member($1, $2, 'member')`, [
          organization,
          "late@example.test",
        ]),
      ).toBe("INVITATION_INVALID");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("reads role names through a roles table with roleThrough", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_through_${USERS.owner.slice(0, 8)}`;
    const ids = {
      owner: "00000000-0000-4000-8000-00000000e001",
      admin: "00000000-0000-4000-8000-00000000e002",
      member: "00000000-0000-4000-8000-00000000e003",
    };
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      await client.query(`
        create schema ${schema};
        create table ${schema}.team_roles (id uuid primary key, key text not null unique);
        insert into ${schema}.team_roles values
          ('${ids.owner}', 'owner'), ('${ids.admin}', 'admin'), ('${ids.member}', 'member');
        create table ${schema}.team_members (
          organization_id uuid not null,
          user_id uuid not null references auth.users (id) on delete cascade,
          role_id uuid not null references ${schema}.team_roles (id),
          created_at timestamptz not null default now(),
          primary key (organization_id, user_id)
        );
        grant usage on schema ${schema} to authenticated;
        grant select on ${schema}.team_members, ${schema}.team_roles to authenticated;
      `);
      const layout: ModuleLayout = {
        modules: {
          access: { schema },
          tenant: {
            schema,
            mode: "adopt",
            tables: { memberships: `${schema}.team_members` },
            columns: {
              memberships: {
                role: "role_id",
                updatedAt: null,
                lastUsedAt: null,
              },
            },
            options: {
              roleThrough: {
                table: `${schema}.team_roles`,
                id: "id",
                column: "key",
              },
            },
          },
          organizations: { schema },
          invitations: { schema },
        },
      };
      for (const file of renderModules(
        ["organizations", "invitations"],
        layout,
      ))
        await client.query(file.contents);
      const roleOf = (organization: string, who: Who) =>
        s.value<string>(
          `(select role_id::text from ${schema}.team_members where organization_id = $1 and user_id = $2)`,
          [organization, USERS[who]],
        );

      await s.as("owner");
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Through", slug: `through-${USERS.owner.slice(0, 8)}` }],
      );
      expect(await roleOf(organization, "owner")).toBe(ids.owner);
      expect(
        await s.value(`better_supabase.has_organization_role($1, '{owner}')`, [
          organization,
        ]),
      ).toBe(true);
      expect(
        await s.hint(`${schema}.invite_member($1, $2, 'superuser')`, [
          organization,
          email("member"),
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      const invite = await s.value<{ token: string; role: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, email("member")],
      );
      expect(invite.role).toBe(ids.member);
      await s.as("member");
      await s.value(`${schema}.accept_invitation($1)`, [invite.token]);
      expect(await roleOf(organization, "member")).toBe(ids.member);
      await s.as("owner");
      await s.value(`${schema}.update_member_role($1, $2, 'admin')`, [
        organization,
        USERS.member,
      ]);
      expect(await roleOf(organization, "member")).toBe(ids.admin);
      expect(
        await s.hint(`${schema}.update_member_role($1, $2, 'superuser')`, [
          organization,
          USERS.member,
        ]),
      ).toBe("ORGANIZATION_ROLE_UNKNOWN");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("leaves the memberships table to an external guard", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_guard_${USERS.owner.slice(0, 8)}`;
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      await client.query(`
        create schema ${schema};
        create table ${schema}.team_members (
          organization_id uuid not null,
          user_id uuid not null references auth.users (id) on delete cascade,
          role text not null,
          created_at timestamptz not null default now(),
          primary key (organization_id, user_id)
        );
      `);
      const layout: ModuleLayout = {
        modules: {
          access: { schema },
          tenant: {
            schema,
            mode: "adopt",
            tables: { memberships: `${schema}.team_members` },
            columns: {
              memberships: { updatedAt: null, lastUsedAt: null },
            },
          },
          organizations: {
            schema,
            options: { assignmentGuard: "external" },
          },
        },
      };
      for (const file of renderModules(["organizations"], layout))
        await client.query(file.contents);
      expect(
        await s.value(
          `(select count(*)::int from pg_trigger where tgrelid = '${schema}.team_members'::regclass and tgname = 'bs_organization_role_guard')`,
        ),
      ).toBe(0);
      await s.as("owner");
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Guard", slug: `guard-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        `insert into ${schema}.team_members (organization_id, user_id, role) values ($1, $2, 'member')`,
        [organization, USERS.member],
      );
      await s.as("member");
      expect(
        await s.hint(`${schema}.update_member_role($1, $2, 'owner')`, [
          organization,
          USERS.owner,
        ]),
      ).toBe("ORGANIZATION_FORBIDDEN");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("invites to platform roles under the permdock model", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_pdplat_${USERS.owner.slice(0, 8)}`;
    const support = "00000000-0000-4000-8000-00000000d001";
    try {
      await client.query("begin");
      for (const who of ["owner", "member", "outsider"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      await client.query(`
        create schema ${schema};
        create table ${schema}.team_members (
          organization_id uuid not null,
          user_id uuid not null,
          role text not null,
          created_at timestamptz not null default now(),
          primary key (organization_id, user_id)
        );
        create table ${schema}.app_roles (id uuid primary key, key text not null unique);
        insert into ${schema}.app_roles values
          ('${support}', 'support'), ('00000000-0000-4000-8000-00000000d002', 'superadmin');
        create table ${schema}.user_roles (
          user_id uuid not null,
          role_id uuid not null references ${schema}.app_roles (id),
          primary key (user_id, role_id)
        );
        create function ${schema}.permitted_organization_ids(permission text) returns setof uuid
          language sql stable as $$ select null::uuid where false $$;
        create function ${schema}.permdock_has(permission text) returns boolean
          language sql stable as $$ select auth.uid() = '${USERS.owner}' and permission = 'platform.invite' $$;
        create function ${schema}.can_assign_platform(member uuid, role text) returns boolean
          language sql stable as $$ select role <> 'superadmin' $$;
      `);
      const layout: ModuleLayout = {
        modules: {
          access: {
            model: "permdock",
            permdock: { schema, scope: "organization" },
          },
          tenant: {
            schema,
            mode: "adopt",
            tables: { memberships: `${schema}.team_members` },
            columns: { memberships: { updatedAt: null, lastUsedAt: null } },
          },
          invitations: {
            schema,
            options: {
              platformRoles: {
                table: `${schema}.user_roles`,
                user: "user_id",
                role: "role_id",
                through: {
                  table: `${schema}.app_roles`,
                  id: "id",
                  column: "key",
                },
                canAssign: `${schema}.can_assign_platform({user}, {role})`,
              },
            },
          },
        },
      };
      for (const file of renderModules(["invitations"], layout))
        await client.query(file.contents);

      await s.as("member");
      expect(
        await s.hint(`${schema}.invite_member(null, $1, 'support')`, [
          email("outsider"),
        ]),
      ).toBe("INVITATION_FORBIDDEN");
      await s.as("owner");
      expect(
        await s.hint(`${schema}.invite_member(null, $1, 'superadmin')`, [
          email("member"),
        ]),
      ).toBe("INVITATION_ROLE_FORBIDDEN");
      expect(
        await s.hint(`${schema}.invite_member(null, $1, 'janitor')`, [
          email("member"),
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      const invite = await s.value<{ token: string; role: string }>(
        `${schema}.invite_member(null, $1, 'support')`,
        [email("member")],
      );
      expect(invite.role).toBe(support);
      await s.as("member");
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [invite.token]),
      ).toBeNull();
      expect(
        await s.value(
          `(select role_id::text from ${schema}.user_roles where user_id = $1)`,
          [USERS.member],
        ),
      ).toBe(support);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("checks a platform invitation's inviter, not the invitee, and accepts or declines by id", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_pdbyid_${USERS.owner.slice(0, 8)}`;
    const support = "00000000-0000-4000-8000-00000000e001";
    const organization = crypto.randomUUID();
    try {
      await client.query("begin");
      for (const who of ["owner", "admin", "member", "outsider"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      await client.query(`
        create schema ${schema};
        create table ${schema}.team_members (
          organization_id uuid not null,
          user_id uuid not null,
          role text not null,
          created_at timestamptz not null default now(),
          primary key (organization_id, user_id)
        );
        insert into ${schema}.team_members (organization_id, user_id, role) values
          ('${organization}', '${USERS.owner}', 'owner');
        create table ${schema}.app_roles (id uuid primary key, key text not null unique);
        insert into ${schema}.app_roles values ('${support}', 'support');
        create table ${schema}.user_roles (
          user_id uuid not null,
          role_id uuid not null references ${schema}.app_roles (id),
          primary key (user_id, role_id)
        );
        create function ${schema}.permitted_organization_ids(permission text) returns setof uuid
          language sql stable as $$
            select m.organization_id from ${schema}.team_members m
            where m.user_id = auth.uid() and m.role = 'owner' $$;
        create function ${schema}.permitted_organization_ids_for(p_user uuid, p_grant text) returns setof uuid
          language sql stable as $$
            select m.organization_id from ${schema}.team_members m
            where m.user_id = p_user and m.role = 'owner' $$;
        create function ${schema}.permdock_has(permission text) returns boolean
          language sql stable as $$ select auth.uid() = '${USERS.owner}' $$;
        create function ${schema}.permdock_has_for(p_user uuid, p_grant text) returns boolean
          language sql stable as $$ select p_user = '${USERS.owner}' $$;
        create function ${schema}.caller_can_assign(role text) returns boolean
          language sql stable as $$ select auth.uid() = '${USERS.owner}' $$;
        create function ${schema}.permdock_can_assign(p_role text, p_scope_id text) returns boolean
          language sql stable as $$ select true $$;
        create function ${schema}.permdock_can_assign_for(p_user uuid, p_role text, p_scope_id text) returns boolean
          language sql stable as $$ select p_user = '${USERS.owner}' $$;
      `);
      const layout: ModuleLayout = {
        modules: {
          access: {
            model: "permdock",
            permdock: { schema, scope: "organization", forUser: true },
          },
          tenant: {
            schema,
            mode: "adopt",
            tables: { memberships: `${schema}.team_members` },
            columns: { memberships: { updatedAt: null, lastUsedAt: null } },
          },
          invitations: {
            schema,
            options: {
              platformRoles: {
                table: `${schema}.user_roles`,
                user: "user_id",
                role: "role_id",
                through: {
                  table: `${schema}.app_roles`,
                  id: "id",
                  column: "key",
                },
                canAssign: `${schema}.caller_can_assign({role})`,
              },
            },
          },
        },
      };
      for (const file of renderModules(["invitations"], layout))
        await client.query(file.contents);

      await s.as("owner");
      const platform = await s.value<{ id: string }>(
        `${schema}.invite_member(null, $1, 'support')`,
        [email("member")],
      );
      const tenant = await s.value<{ id: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, email("member")],
      );
      const declined = await s.value<{ id: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, email("admin")],
      );
      expect(
        await s.hint(`${schema}.update_invitation($1, null, 'nope')`, [
          platform.id,
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      expect(
        await s.value(`${schema}.update_invitation($1, $2, 'support')`, [
          platform.id,
          email("member"),
        ]),
      ).toMatchObject({
        id: platform.id,
        tenant: null,
        organization: null,
        role: support,
      });
      const expire = (at: string) =>
        client.query(
          `update ${schema}.platform_invitations set expires_at = now() + $2::interval where id = $1`,
          [platform.id, at],
        );
      await expire("-1 minute");
      expect(
        await s.hint(`${schema}.update_invitation($1, null, 'support')`, [
          platform.id,
        ]),
      ).toBe("INVITATION_INVALID");
      await expire("1 day");
      await s.as("outsider");
      expect(
        await s.hint(`${schema}.update_invitation($1, null, 'support')`, [
          platform.id,
        ]),
      ).toBe("INVITATION_FORBIDDEN");
      expect(
        await s.hint(`${schema}.accept_invitation_by_id($1)`, [platform.id]),
      ).toBe("INVITATION_EMAIL_MISMATCH");
      expect(
        await s.value(`${schema}.decline_invitation_by_id($1)`, [declined.id]),
      ).toBe(false);
      expect(await s.value(`${schema}.my_invitations()`)).toEqual([]);
      await s.as("member");
      const inbox = await s.value<Record<string, unknown>[]>(
        `${schema}.my_invitations()`,
      );
      expect(new Set(inbox.map((entry) => entry["id"]))).toEqual(
        new Set([platform.id, tenant.id]),
      );
      expect(inbox.every((entry) => !("token" in entry))).toBe(true);
      expect(inbox.find((entry) => entry["id"] === tenant.id)).toMatchObject({
        tenant: organization,
        role: "member",
        email: email("member"),
      });
      expect(
        await s.value(`${schema}.accept_invitation_by_id($1)`, [platform.id]),
      ).toBeNull();
      expect(
        await s.value(
          `(select role_id::text from ${schema}.user_roles where user_id = $1)`,
          [USERS.member],
        ),
      ).toBe(support);
      expect(
        await s.value(`${schema}.accept_invitation_by_id($1)`, [tenant.id]),
      ).toBe(organization);
      await s.as("admin");
      expect(
        await s.value(`${schema}.decline_invitation_by_id($1)`, [declined.id]),
      ).toBe(true);
      expect(
        await s.hint(`${schema}.accept_invitation_by_id($1)`, [declined.id]),
      ).toBe("INVITATION_INVALID");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("checks the inviter again at accept through PermDock's _for helpers", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_pdfor_${USERS.owner.slice(0, 8)}`;
    const organization = crypto.randomUUID();
    try {
      await client.query("begin");
      for (const who of ["owner", "admin", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      await client.query(`
        create schema ${schema};
        create table ${schema}.team_members (
          organization_id uuid not null,
          user_id uuid not null,
          role text not null,
          created_at timestamptz not null default now(),
          primary key (organization_id, user_id)
        );
        create table ${schema}.grants (user_id uuid, permission text);
        insert into ${schema}.team_members (organization_id, user_id, role) values
          ('${organization}', '${USERS.owner}', 'owner'),
          ('${organization}', '${USERS.admin}', 'admin');
        insert into ${schema}.grants values
          ('${USERS.owner}', 'members.invite'), ('${USERS.admin}', 'members.invite');
        create function ${schema}.permitted_organization_ids(permission text) returns setof uuid
          language sql stable as $$
            select m.organization_id from ${schema}.team_members m
            join ${schema}.grants g on g.user_id = m.user_id and g.permission = permitted_organization_ids.permission
            where m.user_id = auth.uid() $$;
        create function ${schema}.permitted_organization_ids_for(p_user uuid, p_grant text) returns setof uuid
          language sql stable as $$
            select m.organization_id from ${schema}.team_members m
            join ${schema}.grants g on g.user_id = m.user_id and g.permission = p_grant
            where m.user_id = p_user $$;
        create function ${schema}.permdock_has(permission text) returns boolean
          language sql stable as $$ select false $$;
        create function ${schema}.permdock_has_for(p_user uuid, p_grant text) returns boolean
          language sql stable as $$ select false $$;
        create function ${schema}.permdock_can_assign(p_role text, p_scope_id text) returns boolean
          language sql stable as $$ select p_role <> 'owner' $$;
        create function ${schema}.permdock_can_assign_for(p_user uuid, p_role text, p_scope_id text) returns boolean
          language sql stable as $$ select p_role <> 'owner' and p_user <> '${USERS.admin}' $$;
      `);
      const layout: ModuleLayout = {
        modules: {
          access: {
            model: "permdock",
            permdock: { schema, scope: "organization", forUser: true },
            functions: {
              canAssign: `${schema}.permdock_can_assign({role}, {tenant}::text)`,
            },
          },
          tenant: {
            schema,
            mode: "adopt",
            tables: { memberships: `${schema}.team_members` },
            columns: { memberships: { updatedAt: null, lastUsedAt: null } },
          },
          invitations: { schema },
        },
      };
      for (const file of renderModules(["invitations"], layout))
        await client.query(file.contents);

      await s.as("owner");
      expect(
        await s.value(
          "better_supabase.can_user($1, 'organization', $2, 'members.invite')",
          [USERS.admin, organization],
        ),
      ).toBe(true);
      const kept = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, email("member")],
      );
      await s.as("admin");
      const lost = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, `late-${email("member")}`],
      );
      expect(lost.token).not.toBe(kept.token);
      await client.query(`delete from ${schema}.grants where user_id = $1`, [
        USERS.owner,
      ]);
      await s.as("member");
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [kept.token]),
      ).toBe("INVITATION_INVITER_REVOKED");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("writes api entry points for the functions only, not the guard helper", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const api = `bs_api_${USERS.owner.slice(0, 8)}`;
    try {
      await client.query("begin");
      await client.query(
        `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
         values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
        [USERS.owner, email("owner")],
      );
      await client.query(`create schema ${api};
        create function ${api}.guard_membership_role(uuid, uuid, text, uuid, text) returns void
          language sql as $$ select $$;`);
      for (const file of renderModules(["organizations", "invitations"], {
        modules: { organizations: { api }, invitations: { api } },
      }))
        await client.query(file.contents);
      const exists = (signature: string) =>
        s.value<boolean>(`to_regprocedure($1) is not null`, [
          `${api}.${signature}`,
        ]);
      expect(
        await exists("guard_membership_role(uuid, uuid, text, uuid, text)"),
      ).toBe(false);
      expect(await exists("invitation_tenant_ids()")).toBe(false);
      expect(await exists("update_member_role(uuid, uuid, text)")).toBe(true);
      expect(await exists("update_invitation(uuid, text, text, jsonb)")).toBe(
        true,
      );
      await s.as("owner");
      const organization = await s.value<string>(
        `${api}.create_organization($1)`,
        [{ name: "Api", slug: `wrapped-${USERS.owner.slice(0, 8)}` }],
      );
      expect(await s.role(organization, "owner")).toBe("owner");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("updates an open invitation in place with the invite checks", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    try {
      await client.query("begin");
      for (const who of Object.keys(USERS) as Who[]) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderModules(
        ["organizations", "invitations"],
        LAYOUT,
      ))
        await client.query(file.contents);

      await s.as("owner");
      const organization = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Edit", slug: `edit-${USERS.owner.slice(0, 8)}` }],
      );
      const invite = (to: string, role: string) =>
        s.value<{ token: string; id: string }>(
          "better_supabase.invite_member($1, $2, $3, '7 days', $4)",
          [organization, to, role, { name: "Out" }],
        );
      const admin = await invite(email("admin"), "admin");
      const open = await invite(email("outsider"), "member");
      const owner = await invite(`owner-${email("outsider")}`, "owner");
      const other = await invite(`renamed-${email("outsider")}`, "member");
      await s.as("admin");
      await s.value("better_supabase.accept_invitation($1)", [admin.token]);

      await s.as("outsider");
      expect(
        await s.hint("better_supabase.update_invitation($1, null, 'viewer')", [
          open.id,
        ]),
      ).toBe("INVITATION_FORBIDDEN");
      await s.as("admin");
      expect(
        await s.hint("better_supabase.update_invitation($1, null, 'member')", [
          owner.id,
        ]),
      ).toBe("INVITATION_ROLE_FORBIDDEN");
      expect(
        await s.hint("better_supabase.update_invitation($1, null, 'owner')", [
          open.id,
        ]),
      ).toBe("INVITATION_ROLE_FORBIDDEN");
      expect(
        await s.hint("better_supabase.update_invitation($1, null, 'nope')", [
          open.id,
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      expect(
        await s.hint("better_supabase.update_invitation($1, $2)", [
          open.id,
          email("owner"),
        ]),
      ).toBe("INVITATION_ALREADY_MEMBER");

      const updated = await s.value<Record<string, unknown>>(
        "better_supabase.update_invitation($1, $2, 'viewer', $3)",
        [open.id, ` Renamed-${email("outsider")} `, { name: "Renamed" }],
      );
      expect(updated).toMatchObject({
        id: open.id,
        email: `renamed-${email("outsider")}`,
        role: "viewer",
        prefill: { name: "Renamed" },
        organization: { id: organization, name: "Edit" },
      });
      expect(updated).not.toHaveProperty("token");
      expect(
        await s.value(
          "(select count(*)::int from better_supabase.invitations where id = $1)",
          [other.id],
        ),
      ).toBe(0);
      await s.as("anon");
      expect(
        await s.value("better_supabase.invitation_preview($1)", [open.token]),
      ).toMatchObject({
        status: "pending",
        email: `renamed-${email("outsider")}`,
        role: "viewer",
        prefill: { name: "Renamed" },
      });

      await s.as("owner");
      expect(
        await s.value(
          "better_supabase.update_invitation($1, null, null, null)",
          [open.id],
        ),
      ).toMatchObject({ role: "viewer", prefill: { name: "Renamed" } });
      await client.query(
        "update better_supabase.invitations set expires_at = now() - interval '1 minute' where id = $1",
        [open.id],
      );
      expect(
        await s.hint("better_supabase.update_invitation($1, null, 'member')", [
          open.id,
        ]),
      ).toBe("INVITATION_INVALID");
      await s.value("better_supabase.resend_invitation($1)", [open.id]);
      expect(
        await s.value("better_supabase.update_invitation($1, null, 'member')", [
          open.id,
        ]),
      ).toMatchObject({ role: "member" });
      await s.value("better_supabase.revoke_invitation($1)", [open.id]);
      expect(
        await s.hint("better_supabase.update_invitation($1, null, 'member')", [
          open.id,
        ]),
      ).toBe("INVITATION_INVALID");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("merges the preview hook, reserves the app's slugs and lets platform staff delete", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_extra_${USERS.owner.slice(0, 8)}`;
    try {
      await client.query("begin");
      for (const who of ["owner", "member", "outsider"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      await client.query(`create schema ${schema};
        create function ${schema}.invitation_preview_extra(invitation uuid) returns jsonb
          language sql stable as $$ select jsonb_build_object('roleLabel', 'Team member', 'invitation', invitation) $$;`);
      const layout: ModuleLayout = {
        modules: {
          access: { schema },
          tenant: { schema },
          "reserved-slugs": { options: { slugs: ["dashboard-beta"] } },
          organizations: {
            schema,
            permissions: { deletePlatform: "platform.organization.delete" },
          },
          invitations: { schema, hooks: { schema } },
        },
      };
      for (const file of renderModules(
        ["organizations", "invitations", "reserved-slugs"],
        layout,
      ))
        await client.query(file.contents);

      await s.as("owner");
      expect(
        await s.hint(`${schema}.create_organization($1)`, [
          { name: "x", slug: "dashboard-beta" },
        ]),
      ).toBe("ORGANIZATION_SLUG_RESERVED");
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Extra", slug: `extra-${USERS.owner.slice(0, 8)}` }],
      );
      const invite = await s.value<{ id: string; token: string }>(
        `${schema}.invite_member($1, $2, 'member')`,
        [organization, email("member")],
      );
      await s.as("anon");
      expect(
        await s.value(`${schema}.invitation_preview($1)`, [invite.token]),
      ).toMatchObject({
        status: "pending",
        roleLabel: "Team member",
        invitation: invite.id,
      });
      expect(await s.value(`${schema}.invitation_preview('nope')`)).toBeNull();
      const preview = await createOrganizations({
        transport: sqlTransport(savepointSql(client)),
        schema,
      })
        .previewInvitation(invite.token)
        .orThrow();
      expect(preview?.extra).toEqual({
        roleLabel: "Team member",
        invitation: invite.id,
      });
      await s.as("member");
      const [inbox] = await createOrganizations({
        transport: sqlTransport(savepointSql(client)),
        schema,
      })
        .myInvitations()
        .orThrow();
      expect(inbox).toMatchObject({
        id: invite.id,
        organizationId: organization,
        organization: { id: organization, name: "Extra" },
        extra: { roleLabel: "Team member", invitation: invite.id },
      });
      expect(inbox?.createdAt).toBeDefined();

      await s.as("outsider");
      expect(
        await s.hint(`${schema}.delete_organization($1)`, [organization]),
      ).toBe("ORGANIZATION_FORBIDDEN");
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({
          sub: USERS.outsider,
          role: "authenticated",
          platform_permissions: ["platform.organization.delete"],
        }),
      ]);
      expect(
        await s.value(`${schema}.delete_organization($1)`, [organization]),
      ).toBe(true);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("caps platform and tenant invitations at the inviter's authority, then and at accept", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const schema = `bs_platform_${USERS.owner.slice(0, 8)}`;
    const module = { schema };
    const role = (n: number) => `00000000-0000-4000-8000-00000000f00${n}`;
    const permission = (n: number) => `00000000-0000-4000-8000-00000000f10${n}`;
    try {
      await client.query("begin");
      for (const who of ["owner", "outsider"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      const layout: ModuleLayout = {
        modules: {
          access: { ...module, model: "catalog" },
          tenant: module,
          organizations: module,
          invitations: module,
        },
      };
      for (const file of renderModules(
        ["organizations", "invitations"],
        layout,
      ))
        await client.query(file.contents);
      await client.query(`
        insert into ${schema}.roles (id, key, scope) values
          ('${role(1)}', 'owner', 'tenant'), ('${role(2)}', 'member', 'tenant'),
          ('${role(3)}', 'lead', 'tenant'), ('${role(4)}', 'inviter', 'platform'),
          ('${role(5)}', 'support', 'platform');
        insert into ${schema}.permissions (id, key) values
          ('${permission(1)}', 'members.invite'), ('${permission(2)}', 'reports.view'),
          ('${permission(3)}', 'platform.invite'), ('${permission(4)}', 'support.view');
        insert into ${schema}.role_permissions (role_id, permission_id) values
          ('${role(1)}', '${permission(1)}'), ('${role(1)}', '${permission(2)}'),
          ('${role(3)}', '${permission(1)}'), ('${role(3)}', '${permission(2)}'),
          ('${role(4)}', '${permission(3)}'),
          ('${role(5)}', '${permission(3)}'), ('${role(5)}', '${permission(4)}');
        insert into ${schema}.platform_roles (user_id, role_id) values ('${USERS.owner}', '${role(4)}');
      `);

      await s.as("owner");
      const organization = await s.value<string>(
        `${schema}.create_organization($1)`,
        [{ name: "Platform", slug: `platform-${USERS.owner.slice(0, 8)}` }],
      );
      expect(
        await s.hint(`${schema}.invite_member($1, $2, 'member', '90 days')`, [
          organization,
          email("outsider"),
        ]),
      ).toBe("INVITATION_VALIDITY");
      const lead = await s.value<{ token: string }>(
        `${schema}.invite_member($1, $2, 'lead')`,
        [organization, email("outsider")],
      );
      expect(
        await s.hint(`${schema}.invite_member(null, $1, 'support')`, [
          email("outsider"),
        ]),
      ).toBe("INVITATION_ROLE_FORBIDDEN");
      expect(
        await s.hint(`${schema}.invite_member(null, $1, 'member')`, [
          email("outsider"),
        ]),
      ).toBe("INVITATION_ROLE_UNKNOWN");
      const platform = await s.value<{ token: string; tenant: null }>(
        `${schema}.invite_member(null, $1, 'inviter')`,
        [email("outsider")],
      );
      expect(platform.tenant).toBeNull();
      expect(
        await s.value(
          `(select count(*)::int from ${schema}.platform_invitations)`,
        ),
      ).toBe(1);

      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({
          sub: USERS.owner,
          role: "authenticated",
          act: { sub: USERS.outsider },
        }),
      ]);
      expect(
        await s.value("better_supabase.is_platform('platform.invite')"),
      ).toBe(false);

      await client.query(
        `delete from ${schema}.role_permissions where role_id = $1 and permission_id = $2`,
        [role(1), permission(2)],
      );
      await client.query(`delete from ${schema}.platform_roles`);
      await s.as("outsider");
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [lead.token]),
      ).toBe("INVITATION_INVITER_REVOKED");
      expect(
        await s.hint(`${schema}.accept_invitation($1)`, [platform.token]),
      ).toBe("INVITATION_INVITER_REVOKED");

      await client.query(
        `insert into ${schema}.platform_roles (user_id, role_id) values ($1, $2)`,
        [USERS.owner, role(4)],
      );
      expect(
        await s.value(`${schema}.accept_invitation($1)`, [platform.token]),
      ).toBeNull();
      expect(
        await s.value(
          `(select role_id::text from ${schema}.platform_roles where user_id = $1)`,
          [USERS.outsider],
        ),
      ).toBe(role(4));
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("drives the modules through createOrganizations and sqlTransport", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const sql = savepointSql(client);
    try {
      await client.query("begin");
      for (const who of ["owner", "member"] as const) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], email(who)],
        );
      }
      for (const file of renderModules(
        ["organizations", "invitations"],
        LAYOUT,
      ))
        await client.query(file.contents);

      const events = new EventHub();
      const seen: string[] = [];
      events.on("block", (event) => seen.push(event.type));
      const mail: InvitationSent[] = [];
      const organizations = createOrganizations({
        transport: sqlTransport(sql),
        events,
        onInvite: (sent) => {
          mail.push(sent);
        },
      });

      await s.as("owner");
      const slug = `api-${USERS.owner.slice(0, 8)}`;
      const created = await organizations
        .create({ name: "Api", slug })
        .orThrow();
      expect((await organizations.slugProblem(slug)).data).toBe("taken");
      expect(
        (await organizations.slugProblem(slug, created.id)).data,
      ).toBeUndefined();
      const taken = await organizations.create({ name: "Again", slug });
      expect(taken.error).toMatchObject({ hint: "ORGANIZATION_SLUG_TAKEN" });

      const switched = await organizations.switch(created.id).orThrow();
      expect(switched).toEqual({ organizationId: created.id, refresh: false });

      const sent = await organizations
        .invite({
          organizationId: created.id,
          email: email("member"),
          role: "member",
          prefill: { name: "Member" },
        })
        .orThrow();
      expect(mail).toEqual([sent]);
      expect(sent.invitation.prefill).toEqual({ name: "Member" });

      await s.as("anon");
      const preview = await organizations
        .previewInvitation(sent.token)
        .orThrow();
      expect(preview).toMatchObject({
        status: "pending",
        organizationId: created.id,
        organization: { name: "Api" },
      });

      await s.as("member");
      const forbidden = await organizations.update(created.id, {
        name: "Mine",
      });
      expect(forbidden.error).toMatchObject({ hint: "ORGANIZATION_FORBIDDEN" });
      expect(
        await organizations.acceptInvitation(sent.token).orThrow(),
      ).toEqual({
        organizationId: created.id,
      });
      expect(await s.role(created.id, "member")).toBe("member");
      await organizations.leave(created.id).orThrow();
      expect(await s.role(created.id, "member")).toBeNull();

      await s.as("owner");
      await organizations.update(created.id, { name: "Api 2" }).orThrow();
      expect(await organizations.delete(created.id).orThrow()).toBe(true);
      expect(seen).toEqual([
        "organization.created",
        "organization.switched",
        "invitation.created",
        "organization.member_added",
        "organization.member_left",
        "organization.updated",
        "organization.deleted",
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
