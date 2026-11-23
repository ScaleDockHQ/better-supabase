import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const NODE = "44444444-4444-4444-8444-444444444444";
const OTHER = "55555555-5555-4555-8555-555555555555";
const GRANTS_TABLE = 'create table "better_supabase"."drive_grants" (';

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

type Layout = Parameters<typeof renderBlocks>[1];

const provider = {
  ...moduleProvider,
  functions: {
    ...moduleProvider.functions,
    roleOn: "authz.role_on({user}, '{resource}', {id})",
  },
};

const rolesLayout = (drive: Record<string, unknown> = {}): Layout => ({
  modules: {
    permissions: { model: "provider" },
    drive: {
      ...drive,
      options: {
        grants: "roles",
        roleFunctions: { node: { rows: "file_node" } },
        ...(drive["options"] as Record<string, unknown> | undefined),
      },
    },
  },
  accessProvider: provider,
});

const driveSql = (layout: Layout): string =>
  renderBlocks(["drive"], layout)
    .filter((file) => file.module === "drive")
    .map((file) => file.contents)
    .join("\n");

const fn = (sql: string, name: string): string => {
  const start = sql.indexOf(`function "better_supabase"."${name}"(`);
  expect(start, `${name} is rendered`).toBeGreaterThan(-1);

  return sql.slice(start, sql.indexOf("$$;", start));
};

describe('drive with options.grants "roles"', () => {
  it("keeps no grants table and asks the provider's roleOn", () => {
    const sql = driveSql(rolesLayout());

    expect(sql).not.toContain(GRANTS_TABLE);
    expect(sql).not.toMatch(/from "better_supabase"\."drive_grants"/u);
    expect(fn(sql, "drive_role")).toContain(
      "authz.role_on(v_uid, 'file_node', drive_role.node::text)",
    );
    expect(fn(sql, "drive_share")).toContain("DRIVE_SHARING_EXTERNAL");
    expect(fn(sql, "drive_unshare")).toContain("DRIVE_SHARING_EXTERNAL");
    expect(fn(sql, "drive_grants")).toContain(
      `authz.role_on(mu."user_id", 'file_node', drive_grants.node::text)`,
    );
    expect(fn(sql, "drive_transfer_ownership")).not.toContain("v_grant");
  });

  it("works with a named role function as well", () => {
    const sql = driveSql({
      modules: {
        drive: {
          options: {
            grants: "roles",
            roleFunctions: { node: "public.file_node_role" },
          },
        },
      },
    });

    expect(sql).not.toContain(GRANTS_TABLE);
    expect(sql).not.toMatch(/from "better_supabase"\."drive_grants"/u);
    expect(fn(sql, "drive_grants")).toContain(
      `"public"."file_node_role"(drive_grants.node, mu."user_id")`,
    );
  });

  it("leaves the default grants table in place", () => {
    const sql = driveSql({ modules: { drive: {} } });

    expect(sql).toContain(GRANTS_TABLE);
    expect(fn(sql, "drive_share")).not.toContain("DRIVE_SHARING_EXTERNAL");
  });

  it("refuses configurations that would leave access undecided", () => {
    const render = (layout: Layout) => () => renderBlocks(["drive"], layout);

    expect(
      render({ modules: { drive: { options: { grants: "everyone" } } } }),
    ).toThrow('blocks.drive.options.grants is "table" or "roles"');
    expect(
      render({ modules: { drive: { options: { grants: "roles" } } } }),
    ).toThrow(/roleFunctions\.node/u);
    expect(
      render(rolesLayout({ options: { uploadRole: "uploader" } })),
    ).toThrow(/uploadRole/u);
    expect(
      render(rolesLayout({ tables: { grants: "public.file_node_grant" } })),
    ).toThrow(/grants/u);
    expect(
      render({
        modules: {
          permissions: { model: "provider" },
          drive: {
            options: { roleFunctions: { node: { rows: "file_node" } } },
          },
        },
        accessProvider: moduleProvider,
      }),
    ).toThrow(/functions\.roleOn/u);
  });

  describe("in Postgres", BOOT, () => {
    it("reads, lists and refuses sharing through the role function", async () => {
      const files = renderBlocks(["drive"], rolesLayout());

      const stub = `
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated', 'service_role', 'supabase_auth_admin'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I', r);
    end if;
  end loop;
end;
$$;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid $$;
create or replace function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create schema if not exists realtime;
create table if not exists realtime.messages (id bigint, topic text, extension text);
create function realtime.topic() returns text language sql stable as $$ select null::text $$;
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create function storage.foldername(name text) returns text[] language sql immutable as $$ select '{}'::text[] $$;
create table if not exists storage.objects (id uuid, bucket_id text, name text, owner uuid);
create schema if not exists authz;
grant usage on schema auth, authz to anon, authenticated;
create function authz.ids_organization(permission text) returns setof uuid
  language sql stable as $$ select '${TENANT}'::uuid $$;
create function authz.ids_organization_for(u uuid, permission text) returns setof uuid
  language sql stable as $$ select '${TENANT}'::uuid $$;
create function authz.ids_project(permission text) returns setof uuid
  language sql stable as $$ select null::uuid where false $$;
create function authz.ids_project_for(u uuid, permission text) returns setof uuid
  language sql stable as $$ select null::uuid where false $$;
create function authz.is_platform_for(u uuid, permission text) returns boolean
  language sql stable as $$ select false $$;
create function authz.member_organization_ids() returns setof uuid
  language sql stable as $$ select '${TENANT}'::uuid $$;
create function authz.member_project_ids() returns setof uuid
  language sql stable as $$ select null::uuid where false $$;
create function authz.member_organization_ids_for(u uuid) returns setof uuid
  language sql stable as $$ select '${TENANT}'::uuid $$;
create function authz.member_project_ids_for(u uuid) returns setof uuid
  language sql stable as $$ select null::uuid where false $$;
create function authz.can_assign(t uuid, r text) returns boolean
  language sql stable as $$ select true $$;
create function authz.can_assign_for(u uuid, t uuid, r text) returns boolean
  language sql stable as $$ select true $$;
create function authz.is_platform(permission text) returns boolean
  language sql stable as $$ select false $$;
-- Alice edits one node; nobody else has a role anywhere.
create function authz.role_on(u uuid, resource text, id text) returns text
  language sql stable as $$
    select 'editor' where u = '${ALICE}' and resource = 'file_node' and id = '${NODE}'
  $$;
grant execute on all functions in schema authz to authenticated;`;

      await using stack = await liteStack({
        driver: "pglite",
        seed: [
          stub,
          ...files
            .filter((file) => file.kind === "schema")
            .map((file) => file.contents),
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          `insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id, role)
values ('${TENANT}', '${ALICE}', 'member'), ('${TENANT}', '${BOB}', 'member');
insert into better_supabase.drive_nodes (id, tenant_id, kind, name)
values ('${NODE}', '${TENANT}', 'folder', 'shared'), ('${OTHER}', '${TENANT}', 'folder', 'private');
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', false);
do $$
declare
  v jsonb;
begin
  if (select array_agg(id) from better_supabase.drive_nodes) is distinct from array['${NODE}'::uuid] then
    raise exception 'Alice reads %', (select array_agg(id) from better_supabase.drive_nodes);
  end if;
  if better_supabase.drive_role('${NODE}') is distinct from 'editor' then
    raise exception 'drive_role is %', better_supabase.drive_role('${NODE}');
  end if;
  v := better_supabase.drive_grants('${NODE}');
  if jsonb_array_length(v) <> 1 or v -> 0 ->> 'principalId' <> '${ALICE}' or v -> 0 ->> 'role' <> 'editor' then
    raise exception 'drive_grants is %', v;
  end if;
  begin
    perform better_supabase.drive_share('${NODE}', 'user', '${BOB}', 'viewer');
    raise exception 'drive_share was allowed';
  exception when feature_not_supported then null;
  end;
end;
$$;
reset role;`,
        ],
      });

      expect(stack.url).not.toBe("");
    });
  });
});
