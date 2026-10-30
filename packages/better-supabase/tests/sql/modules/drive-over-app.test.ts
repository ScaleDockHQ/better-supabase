import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { adoptedColumnProblems } from "../../../src/sql/adopted-columns.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const APP = `
create type public.file_node_kind as enum ('folder', 'file');
create type public.file_node_source as enum ('internal', 'google-drive', 'onedrive');
create type public.file_grant_role as enum ('viewer', 'commenter', 'editor');
create type public.file_drive_type as enum ('company', 'personal', 'shared');
create type public.file_provider as enum ('google-drive', 'onedrive');
create type public.file_connection_status as enum ('active', 'error');

create table public.file_drive_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  user_id uuid not null,
  provider public.file_provider not null,
  name text not null,
  status public.file_connection_status not null default 'active',
  sync_cursor text,
  sync_claimed_at timestamptz,
  last_synced_at timestamptz,
  last_sync_error text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.file_drives (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  drive_type public.file_drive_type not null,
  name text not null,
  owner_user_id uuid,
  connection_id uuid references public.file_drive_connections (id) on delete cascade,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create table public.file_drive_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  drive_id uuid not null references public.file_drives (id) on delete cascade,
  user_id uuid not null,
  role public.file_grant_role not null default 'viewer',
  expires_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table public.file_nodes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  drive_id uuid not null references public.file_drives (id) on delete cascade,
  parent_id uuid references public.file_nodes (id) on delete cascade,
  kind public.file_node_kind not null,
  name text not null,
  source public.file_node_source not null default 'internal',
  external_id text,
  external_metadata jsonb not null default '{}'::jsonb,
  deleted_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index file_nodes_external_idx on public.file_nodes (drive_id, source, external_id)
  where external_id is not null and deleted_at is null;

create table public.file_node_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  node_id uuid not null references public.file_nodes (id) on delete cascade,
  user_id uuid not null,
  role public.file_grant_role not null default 'viewer',
  expires_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);
`;

const OWN_TABLES = {
  "public.file_nodes": "app.sql",
  "public.file_node_grants": "app.sql",
  "public.file_drives": "app.sql",
  "public.file_drive_grants": "app.sql",
  "public.file_drive_connections": "app.sql",
};

const BLOCKS: AnyBlocksConfig = {
  drive: {
    tables: {
      nodes: "public.file_nodes",
      grants: "public.file_node_grants",
      drives: "public.file_drives",
      driveGrants: "public.file_drive_grants",
      connections: "public.file_drive_connections",
    },
    columns: {
      nodes: {
        tenant: "organization_id",
        drive: "drive_id",
        attachment: null,
        path: null,
        rank: null,
        legalHoldUntil: null,
        lockedBy: null,
        lockedUntil: null,
        lockNote: null,
        downloadBlocked: null,
        previewPages: null,
      },
      grants: {
        tenant: "organization_id",
        node: "node_id",
        principalType: null,
        principalId: null,
        team: null,
      },
      driveGrants: {
        tenant: "organization_id",
        principalType: null,
        principalId: null,
        team: null,
      },
      drives: {
        tenant: "organization_id",
        kind: "drive_type",
        owner: "owner_user_id",
        downloadBlocked: null,
      },
      connections: { tenant: "organization_id" },
    },
    options: {
      drives: true,
      driveKinds: ["shared", "company", "personal"],
      roles: ["viewer", "commenter", "editor"],
    },
  },
};

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}');
insert into better_supabase.memberships (organization_id, user_id, role)
  values ('${TENANT}', '${ALICE}', 'owner'), ('${TENANT}', '${BOB}', 'member');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["drive"], {
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
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("drive over the app's enum columns", BOOT, () => {
  it("takes enum kind, role, drive type, source, provider and status columns", () => {
    expect(
      adoptedColumnProblems(BLOCKS, [{ text: APP }], ["public"], OWN_TABLES),
    ).toEqual([]);
  });

  it("creates, shares, lists and syncs drives and nodes", async () => {
    await expect(
      run(`do $$
declare
  v_drive uuid;
  v_folder jsonb;
  v_child jsonb;
  v_connection jsonb;
  v_mirror uuid;
  v_count integer;
begin
  ${AS_ALICE}
  v_drive := (better_supabase.drive_create_drive('${TENANT}', 'Team', 'company') ->> 'id')::uuid;
  if (select drive_type from public.file_drives where id = v_drive) <> 'company' then
    raise exception 'drive type';
  end if;
  perform better_supabase.drive_share_drive(v_drive, 'user', '${BOB}', 'commenter');
  if (select role from public.file_drive_grants where drive_id = v_drive and user_id = '${BOB}') <> 'commenter' then
    raise exception 'drive grant';
  end if;
  if better_supabase.drive_drive_role(v_drive) is null then
    raise exception 'drive role';
  end if;
  v_folder := better_supabase.drive_create_folder('${TENANT}', null, 'Docs', null, null, v_drive);
  v_child := better_supabase.drive_create_folder('${TENANT}', (v_folder ->> 'id')::uuid, 'Inner', null, null, v_drive);
  if v_child ->> 'kind' <> 'folder' then
    raise exception 'folder %', v_child;
  end if;
  perform better_supabase.drive_share((v_folder ->> 'id')::uuid, 'user', '${BOB}', 'editor');
  if (select role from public.file_node_grants where user_id = '${BOB}') <> 'editor' then
    raise exception 'node grant';
  end if;
  if jsonb_array_length(better_supabase.drive_grants((v_child ->> 'id')::uuid)) < 1 then
    raise exception 'grants';
  end if;
  if not better_supabase.drive_can((v_child ->> 'id')::uuid, 'editor') then
    raise exception 'can';
  end if;
  if jsonb_array_length(better_supabase.drive_list('${TENANT}', (v_folder ->> 'id')::uuid, 50, 0, v_drive) -> 'items') <> 1 then
    raise exception 'list %', better_supabase.drive_list('${TENANT}', (v_folder ->> 'id')::uuid, 50, 0, v_drive);
  end if;
  perform better_supabase.drive_rename((v_child ->> 'id')::uuid, 'Renamed');
  perform better_supabase.drive_move((v_child ->> 'id')::uuid, null);
  perform better_supabase.drive_unshare((v_folder ->> 'id')::uuid, 'user', '${BOB}');
  perform better_supabase.drive_unshare_drive(v_drive, 'user', '${BOB}');
  v_connection := better_supabase.drive_connect('${TENANT}', 'google-drive', 'alice@example.com');
  if v_connection ->> 'status' <> 'active' or v_connection ->> 'provider' <> 'google-drive' then
    raise exception 'connection %', v_connection;
  end if;
  if jsonb_array_length(better_supabase.drive_list_connections('${TENANT}')) <> 1 then
    raise exception 'connections';
  end if;
  v_mirror := (better_supabase.drive_create_drive('${TENANT}', 'Mirror', 'personal', null, (v_connection ->> 'id')::uuid) ->> 'id')::uuid;
  ${SERVICE}
  v_count := better_supabase.drive_sync_batch(v_mirror, '[{"externalId":"a","parentExternalId":"root","name":"A","kind":"folder"},{"externalId":"b","parentExternalId":"a","name":"B","kind":"file"}]'::jsonb, 'root');
  if v_count <> 2 or (select count(*) from public.file_nodes where drive_id = v_mirror and source = 'google-drive') <> 2 then
    raise exception 'synced %', v_count;
  end if;
  ${AS_ALICE}
  if jsonb_array_length(better_supabase.drive_list_drives('${TENANT}')) <> 2 then
    raise exception 'drives';
  end if;
  perform better_supabase.drive_disconnect((v_connection ->> 'id')::uuid);
  perform better_supabase.drive_delete((v_folder ->> 'id')::uuid);
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
