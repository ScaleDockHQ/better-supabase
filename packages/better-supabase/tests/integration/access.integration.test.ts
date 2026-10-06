import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockLayout } from "../../src/sql/blocks.ts";

import { renderBlocks } from "../../src/sql/blocks.ts";

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

const ORG = crypto.randomUUID();
const USER = crypto.randomUUID();
const ADMIN_ROLE = crypto.randomUUID();
const SUPPORT_ROLE = crypto.randomUUID();
const INVITE = crypto.randomUUID();
const BILLING = crypto.randomUUID();
const USERS_MANAGE = crypto.randomUUID();

/** Runs `run` in a transaction that is always rolled back, after installing `names` for `layout`. */
async function inTransaction<T>(
  pool: Pool,
  setup: string,
  names: readonly string[],
  layout: BlockLayout,
  run: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query(
      `insert into auth.users (id, email, aud, role, instance_id)
       values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')`,
      [USER, `access-${USER}@example.test`],
    );
    if (setup) await client.query(setup);
    for (const file of renderBlocks(names, layout))
      await client.query(file.contents);
    return await run(client);
  } finally {
    await client.query("rollback");
    client.release();
  }
}

async function asUser(
  client: PoolClient,
  claims: Readonly<Record<string, unknown>> = {},
): Promise<void> {
  await client.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: USER, role: "authenticated", ...claims }),
  ]);
}

describe.skipIf(!live)("access contract against the local database", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("answers from the roles model, with platform permissions from the token", async () => {
    const row = await inTransaction(
      pool,
      "",
      ["access"],
      {},
      async (client) => {
        await client.query(
          "insert into better_supabase.organizations (id, name, slug) values ($1::uuid, 'Test', 'test-' || left($1::text, 8)) on conflict do nothing",
          [ORG],
        );
        await client.query(
          "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'admin')",
          [ORG, USER],
        );
        await asUser(client, { platform_permissions: ["support.*"] });
        const { rows } = await client.query<Record<string, unknown>>(
          `select better_supabase.can('organization', $1, 'members.invite') as invite,
          better_supabase.can('organization', $1, 'organization.delete') as delete,
          better_supabase.can('team', $1, 'members.invite') as other_scope,
          better_supabase.can_assign($1, 'member') as assign_member,
          better_supabase.can_assign($1, 'owner') as assign_owner,
          better_supabase.is_platform('support.start') as platform,
          better_supabase.is_platform('billing.manage') as not_platform,
          array(select better_supabase.tenant_ids_with('audit.read')) as ids,
          better_supabase.permission_claims($2) -> $1::text as claims`,
          [ORG, USER],
        );
        return rows[0]!;
      },
    );
    expect(row).toMatchObject({
      invite: true,
      delete: false,
      other_scope: false,
      assign_member: true,
      assign_owner: false,
      platform: true,
      not_platform: false,
      ids: [ORG],
    });
    expect(row["claims"]).toContain("members.*");
  });

  it("adopts a CentraKit-shaped catalog: deny overrides, platform roles, disabled tenants and a resolved tenant", async () => {
    const setup = `
      create table public.bs_access_organizations (id uuid primary key, disabled_at timestamptz);
      create table public.bs_access_roles (id uuid primary key, key text not null);
      create table public.bs_access_permissions (id uuid primary key, key text not null unique);
      create table public.bs_access_role_permissions (role_id uuid, permission_id uuid, primary key (role_id, permission_id));
      create table public.bs_access_overrides (organization_id uuid, role_id uuid, permission_id uuid, granted boolean not null, primary key (organization_id, role_id, permission_id));
      create table public.bs_access_user_roles (user_id uuid, role_id uuid, primary key (user_id, role_id));
      create table public.bs_access_organization_users (user_id uuid, organization_id uuid, role_id uuid, created_at timestamptz default now(), unique (user_id, organization_id));
      insert into public.bs_access_organizations values ('${ORG}', null);
      insert into public.bs_access_roles values ('${ADMIN_ROLE}', 'admin'), ('${SUPPORT_ROLE}', 'system-support');
      insert into public.bs_access_permissions values ('${INVITE}', 'organization.members.invite'), ('${BILLING}', 'organization.billing.manage'), ('${USERS_MANAGE}', 'system.users.manage');
      insert into public.bs_access_role_permissions values ('${ADMIN_ROLE}', '${INVITE}'), ('${ADMIN_ROLE}', '${BILLING}'), ('${SUPPORT_ROLE}', '${USERS_MANAGE}');
      insert into public.bs_access_overrides values ('${ORG}', '${ADMIN_ROLE}', '${BILLING}', false);
      insert into public.bs_access_user_roles values ('${USER}', '${SUPPORT_ROLE}');
      insert into public.bs_access_organization_users (user_id, organization_id, role_id) values ('${USER}', '${ORG}', '${ADMIN_ROLE}');
    `;
    const layout: BlockLayout = {
      blocks: {
        tenant: {
          mode: "adopt",
          tables: { memberships: "public.bs_access_organization_users" },
          columns: {
            memberships: {
              tenant: "organization_id",
              role: "role_id",
              lastUsedAt: null,
            },
          },
        },
        access: {
          mode: "adopt",
          model: "catalog",
          tables: {
            roles: "public.bs_access_roles",
            permissions: "public.bs_access_permissions",
            rolePermissions: "public.bs_access_role_permissions",
            overrides: "public.bs_access_overrides",
            platformAssignments: "public.bs_access_user_roles",
          },
          columns: { overrides: { tenant: "organization_id" } },
          disabled: { tenant: "public.bs_access_organizations.disabled_at" },
          activeTenant: "resolver",
        },
      },
    };
    const [before, after] = await inTransaction(
      pool,
      setup,
      ["access"],
      layout,
      async (client) => {
        await asUser(client);
        await client.query(
          "select set_config('better_supabase.tenant', $1, true)",
          [ORG],
        );
        const query = `select better_supabase.can('organization', $1, 'organization.members.invite') as invite,
            better_supabase.can('organization', $1, 'organization.billing.manage') as billing,
            better_supabase.is_platform('system.users.manage') as platform,
            better_supabase.current_tenant_id() as active,
            better_supabase.has_organization_role($1, '{admin}') as admin,
            better_supabase.permission_claims($2) as claims,
            better_supabase.membership_claims($2) as memberships`;
        const first = await client.query<Record<string, unknown>>(query, [
          ORG,
          USER,
        ]);
        await client.query(
          "update public.bs_access_organizations set disabled_at = now() where id = $1",
          [ORG],
        );
        const second = await client.query<Record<string, unknown>>(query, [
          ORG,
          USER,
        ]);
        return [first.rows[0]!, second.rows[0]!];
      },
    );
    expect(before).toEqual({
      invite: true,
      billing: false,
      platform: true,
      active: ORG,
      admin: true,
      claims: { [ORG]: ["organization.members.invite"] },
      memberships: [{ scope: "tenant", id: ORG, roles: ["admin"] }],
    });
    expect(after).toMatchObject({
      invite: false,
      platform: true,
      claims: {},
      memberships: [],
    });
  });

  it("ignores a resolved tenant the caller isn't a member of", async () => {
    const active = await inTransaction(
      pool,
      "",
      ["tenant"],
      { blocks: { access: { activeTenant: "resolver" } } },
      async (client) => {
        await asUser(client);
        await client.query(
          "select set_config('better_supabase.tenant', $1, true)",
          [crypto.randomUUID()],
        );
        const { rows } = await client.query<{ id: string | null }>(
          "select better_supabase.current_tenant_id() as id",
        );
        return rows[0]!.id;
      },
    );
    expect(active).toBeNull();
  });

  it("wraps the app's own functions in the custom model", async () => {
    const row = await inTransaction(
      pool,
      `create function public.bs_access_can(scope text, id uuid, perm text) returns boolean language sql as $$ select perm = 'ok' $$;
       create function public.bs_access_ids(perm text) returns setof uuid language sql as $$ select '${ORG}'::uuid where perm = 'ok' $$;
       create function public.bs_access_platform(perm text) returns boolean language sql as $$ select perm = 'ok' $$;`,
      ["access"],
      {
        blocks: {
          access: {
            model: "custom",
            functions: {
              can: "public.bs_access_can({scope}, {id}, {permission})",
              tenantIdsWith: "public.bs_access_ids({permission})",
              isPlatform: "public.bs_access_platform({permission})",
              canAssign: "{role} <> 'owner'",
            },
          },
        },
      },
      async (client) => {
        await asUser(client);
        const { rows } = await client.query<Record<string, unknown>>(
          `select better_supabase.can('organization', $1, 'ok') as yes,
            better_supabase.can('organization', $1, 'no') as no,
            better_supabase.can('platform', $1, 'ok') as platform,
            array(select better_supabase.tenant_ids_with('ok')) as ids`,
          [ORG],
        );
        return rows[0]!;
      },
    );
    expect(row).toEqual({ yes: true, no: false, platform: true, ids: [ORG] });
  });
});
