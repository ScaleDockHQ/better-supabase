import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 120_000 };

const layout = {
  modules: {
    permissions: { model: "provider" },
    drive: {
      options: {
        roleFunctions: {
          node: {
            rows: "file_node",
            roles: { viewer: "fileNode.read", editor: "fileNode.update" },
          },
        },
      },
    },
  },
  accessProvider: {
    ...moduleProvider,
    functions: {
      ...moduleProvider.functions,
      rowsWith: "authz.rows_{resource}({permission}, {ids})",
    },
  },
} as const;

const driveSql = (): string =>
  renderBlocks(["drive"], layout)
    .map((file) => file.contents)
    .join("\n");

describe("drive set readers with provider row grants", () => {
  it("ask rowsWith once per role with the candidate ids as one array", () => {
    const sql = driveSql();

    const start = sql.indexOf(
      'function "better_supabase"."drive_readable_ids"',
    );

    const reader = sql.slice(start, sql.indexOf("$$;", start + 60));

    expect(start).toBeGreaterThan(-1);
    expect(reader).not.toMatch(/array\[x\.[^\]]*::text\]/u);
    expect(reader.match(/authz\.rows_file_node\(/gu)).toHaveLength(2);
    expect(reader).toContain("(select c.ids from candidates c)");
    expect(sql).toContain(
      "authz.rows_file_node('fileNode.read', array[drive_role.node::text])",
    );
  });

  describe("in Postgres", BOOT, () => {
    it("makes no more provider calls than there are mapped roles", async () => {
      const files = renderBlocks(["drive"], layout);

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
create table authz.calls (permission text);
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
create function authz.rows_file_node(permission text, ids text[]) returns setof text
  language plpgsql volatile as $$
begin
  insert into authz.calls values (permission);
  return query select unnest(ids);
end;
$$;`;

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
          `insert into auth.users (id) values ('${ALICE}');
insert into better_supabase.drive_nodes (tenant_id, kind, name)
select '${TENANT}', 'folder', 'n' || g from generate_series(1, 1000) g;
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', false);
select count(*) from better_supabase.drive_nodes;
reset role;
do $$ begin
  if (select count(*) from authz.calls) not between 1 and 2 then
    raise exception 'rowsWith was called % times', (select count(*) from authz.calls);
  end if;
end $$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    });
  });
});
