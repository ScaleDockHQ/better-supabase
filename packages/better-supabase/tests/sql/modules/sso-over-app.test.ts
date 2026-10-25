import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const PROVIDER = "22222222-2222-4222-8222-222222222222";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own SSO tables: renamed tenant columns, enum roles, types and
// operations, an extra private column on each, and none of the optional
// columns.
const APP = `
create type public.member_role as enum ('admin', 'member', 'viewer');
create type public.idp_kind as enum ('saml');
create type public.scim_op as enum ('create', 'replace', 'patch', 'delete');
create type public.scim_kind as enum ('User', 'Group');

create table public.org_domains (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  domain text not null,
  verification_token text not null default 'secret-token',
  verified_at timestamptz,
  auto_join_role public.member_role,
  enforce_sso boolean not null default false,
  note text default 'private'
);

create table public.org_idps (
  id uuid primary key,
  org_id uuid not null,
  type public.idp_kind not null,
  domains text[] not null default '{}',
  created_at timestamptz not null default now(),
  note text default 'private'
);

create table public.directory_users (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  user_id uuid,
  external_id text,
  user_name text not null,
  email text,
  emails jsonb not null default '[]',
  active boolean not null default true,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  note text default 'private'
);

create table public.directory_groups (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  display_name text not null,
  external_id text,
  role public.member_role,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  note text default 'private'
);

create table public.directory_members (
  group_id uuid not null references public.directory_groups (id) on delete cascade,
  scim_user_id uuid not null references public.directory_users (id) on delete cascade
);

create table public.directory_log (
  id bigint generated always as identity primary key,
  org_id uuid not null,
  operation public.scim_op not null,
  resource_type public.scim_kind not null,
  resource_id text,
  status integer not null,
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.org_domains": "app.sql",
  "public.org_idps": "app.sql",
  "public.directory_users": "app.sql",
  "public.directory_groups": "app.sql",
  "public.directory_members": "app.sql",
  "public.directory_log": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  sso: {
    options: { syncLog: true },
    tables: {
      domains: "public.org_domains",
      providers: "public.org_idps",
      scimUsers: "public.directory_users",
      scimGroups: "public.directory_groups",
      scimMembers: "public.directory_members",
      syncLog: "public.directory_log",
    },
    columns: {
      domains: { tenant: "org_id", createdBy: null, createdAt: null },
      providers: { tenant: "org_id", metadataUrl: null },
      scimUsers: {
        tenant: "org_id",
        displayName: null,
        givenName: null,
        familyName: null,
        updatedAt: null,
      },
      scimGroups: { tenant: "org_id", updatedAt: null },
      syncLog: { tenant: "org_id", error: null, requestId: null },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["memberships", "permissions", "sso"], {
    modules: BLOCKS,
    ownTables: OWN_TABLES,
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("sso over the app's tables", BOOT, () => {
  it("verifies domains and registers providers without the token or the app's columns", async () => {
    await expect(
      run(`do $$
declare
  v_domain jsonb;
  v_provider jsonb;
begin
  ${SERVICE}
  insert into public.org_domains (org_id, domain) values ('${TENANT}', 'acme.test');
  v_domain := better_supabase.verify_organization_domain((select id from public.org_domains));
  if v_domain ->> 'verified_at' is null or v_domain ->> 'organization_id' <> '${TENANT}' then
    raise exception 'verified %', v_domain;
  end if;
  if v_domain ? 'verification_token' or v_domain ? 'note' or v_domain ->> 'created_by' is not null then
    raise exception 'leaked %', v_domain;
  end if;
  if v_domain -> 'record' ->> 'value' <> 'better-supabase-domain-verification=secret-token' then
    raise exception 'record %', v_domain;
  end if;
  update public.org_domains set auto_join_role = 'viewer';
  if better_supabase.list_organization_domains('${TENANT}') -> 0 ->> 'auto_join_role' <> 'viewer' then
    raise exception 'listed %', better_supabase.list_organization_domains('${TENANT}');
  end if;
  v_provider := better_supabase.register_sso_provider('${TENANT}', '${PROVIDER}', array['ACME.test']);
  if (select type from public.org_idps) <> 'saml' or v_provider ->> 'type' <> 'saml' then
    raise exception 'registered %', v_provider;
  end if;
  if v_provider ? 'note' or v_provider ->> 'metadata_url' is not null or v_provider -> 'domains' <> '["acme.test"]' then
    raise exception 'provider %', v_provider;
  end if;
  v_provider := better_supabase.register_sso_provider('${TENANT}', '${PROVIDER}', array['acme.test']);
  if (select count(*) from public.org_idps) <> 1 then
    raise exception 'registered twice';
  end if;
  if better_supabase.sso_domain_for('jo@acme.test') ->> 'providerId' <> '${PROVIDER}' then
    raise exception 'domain for %', better_supabase.sso_domain_for('jo@acme.test');
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("saves SCIM users and groups with an enum role and logs writes", async () => {
    await expect(
      run(`do $$
declare
  v_user jsonb;
  v_group jsonb;
  v_log jsonb;
begin
  ${SERVICE}
  v_user := better_supabase.scim_save_user('${TENANT}', null, '{"userName":"jo@acme.test","displayName":"Jo","emails":[{"value":"jo@acme.test","primary":true}]}');
  if v_user ->> 'user_name' <> 'jo@acme.test' or v_user ? 'note' or v_user ->> 'display_name' is not null then
    raise exception 'user %', v_user;
  end if;
  if v_user ->> 'updated_at' <> v_user ->> 'created_at' then
    raise exception 'updated %', v_user;
  end if;
  v_user := better_supabase.scim_save_user('${TENANT}', (v_user ->> 'id')::uuid, '{"userName":"jo@acme.test","active":false}');
  if (v_user ->> 'version')::integer <> 2 or (v_user ->> 'active')::boolean then
    raise exception 'replaced %', v_user;
  end if;
  v_group := better_supabase.scim_save_group('${TENANT}', null, jsonb_build_object('displayName', 'Admin', 'members', jsonb_build_array(v_user ->> 'id')));
  if (select role from public.directory_groups) <> 'admin' or v_group ? 'note' then
    raise exception 'group %', v_group;
  end if;
  if v_group -> 'members' -> 0 ->> 'display' <> 'jo@acme.test' then
    raise exception 'members %', v_group;
  end if;
  v_group := better_supabase.scim_save_group('${TENANT}', (v_group ->> 'id')::uuid, jsonb_build_object('displayName', 'Viewer', 'members', jsonb_build_array(v_user ->> 'id')));
  if (select role from public.directory_groups) <> 'viewer' or (select count(*) from public.directory_members) <> 1 then
    raise exception 'regrouped %', v_group;
  end if;
  if better_supabase.scim_get_user('${TENANT}', (v_user ->> 'id')::uuid) -> 'groups' -> 0 ->> 'display' <> 'Viewer' then
    raise exception 'groups %', better_supabase.scim_get_user('${TENANT}', (v_user ->> 'id')::uuid);
  end if;
  perform better_supabase.scim_log_sync('${TENANT}', 'create', 'User', v_user ->> 'id', 201, 'ignored', 'req-1');
  v_log := better_supabase.list_scim_sync_log('${TENANT}');
  if v_log -> 0 ->> 'operation' <> 'create' or v_log -> 0 ->> 'resource_type' <> 'User' or v_log -> 0 ->> 'error' is not null then
    raise exception 'log %', v_log;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
