import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const ADA = "22222222-2222-4222-8222-222222222222";
const ORG = "33333333-3333-4333-8333-333333333333";
const FILE = "44444444-4444-4444-8444-444444444444";

const STUBS = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;

create schema if not exists extensions;
create function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create function extensions.digest(data text, type text) returns bytea
language sql immutable as $$ select sha256(convert_to(data, 'UTF8')) $$;

-- PGlite has no Storage schema; these are the columns the module reads.
create schema if not exists storage;
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid,
  metadata jsonb,
  version text
);
alter table storage.objects enable row level security;
`;

// The app's own files table: renamed columns, an enum status, its own
// caption, and no metadata, scan detail, size or scan time columns. The
// module adds the subject and version columns it is missing.
const APP = `
create type public.file_state as enum ('pending', 'clean', 'infected', 'failed');

create table public.files (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  bucket text not null default 'attachments',
  storage_path text generated always as (org_id::text || '/attachments/' || id::text) stored,
  file_name text not null,
  content_type text not null,
  byte_size bigint not null,
  state public.file_state not null default 'pending',
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  uploaded_at timestamptz,
  caption text
);
`;

const MODULES: AnyBlocksConfig = {
  attachments: {
    tables: { attachments: "public.files" },
    columns: {
      attachments: {
        tenant: "org_id",
        path: "storage_path",
        name: "file_name",
        mimeType: "content_type",
        size: "byte_size",
        status: "state",
        metadata: null,
        detail: null,
        width: null,
        height: null,
        pages: null,
        scannedAt: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const AS_ADA = `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${ADA}"}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', '${ADA}', true);`;

const PATH = `${ORG}/attachments/${FILE}`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["attachments"], {
    modules: MODULES,
    ownTables: { "public.files": "app.sql" },
  });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      STUBS,
      APP,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
    ],
    seed: [
      `insert into auth.users (id, email) values ('${ADA}', 'ada@example.com');`,
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("attachments over the app's tables", BOOT, () => {
  it("uploads, scans, replaces and restores a file in an enum status column", async () => {
    await expect(
      run(`do $$
declare
  v_file jsonb;
  v_versions jsonb;
begin
  ${SERVICE}
  insert into public.files (id, org_id, file_name, content_type, byte_size, caption)
  values ('${FILE}', '${ORG}', 'Plan.pdf', 'application/pdf', 1, 'The plan');
  insert into storage.objects (bucket_id, name, metadata)
  values ('attachments', '${PATH}', '{"size": 42, "mimetype": "application/pdf"}');
  v_file := better_supabase.confirm_attachment('${FILE}');
  if v_file ->> 'object_path' <> '${PATH}' or (v_file ->> 'size')::bigint <> 42
    or v_file ->> 'status' <> 'pending' or v_file ? 'caption' or v_file ? 'scan_detail' then
    raise exception 'confirmed %', v_file;
  end if;
  v_file := better_supabase.set_attachment_status('${FILE}', 'clean');
  if (select state from public.files where id = '${FILE}') <> 'clean' then
    raise exception 'scanned %', v_file;
  end if;
  if better_supabase.object_scan('attachments', '${PATH}') ->> 'status' <> 'clean'
    or not better_supabase.object_clean('attachments', '${PATH}') then
    raise exception 'scan row %', better_supabase.object_scan('attachments', '${PATH}');
  end if;

  v_file := better_supabase.replace_attachment('${FILE}', 'Plan v2.pdf', 'application/pdf', 50);
  if (v_file ->> 'version')::int <> 2 or v_file ->> 'object_path' <> '${PATH}-v2'
    or (select state from public.files where id = '${FILE}') <> 'pending' then
    raise exception 'replaced %', v_file;
  end if;
  v_versions := better_supabase.list_attachment_versions('${FILE}');
  if jsonb_array_length(v_versions) <> 1 or v_versions -> 0 ->> 'status' <> 'clean'
    or v_versions -> 0 ->> 'object_path' <> '${PATH}' or v_versions -> 0 ->> 'name' <> 'Plan.pdf' then
    raise exception 'versions %', v_versions;
  end if;

  v_file := better_supabase.restore_attachment_version('${FILE}', 1);
  if (v_file ->> 'version')::int <> 1 or v_file ->> 'name' <> 'Plan.pdf'
    or (select state from public.files where id = '${FILE}') <> 'clean' then
    raise exception 'restored %', v_file;
  end if;
  if (select caption from public.files where id = '${FILE}') <> 'The plan' then
    raise exception 'the app''s caption changed';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("starts a client's own insert pending, whatever status it sends", async () => {
    await expect(
      run(`do $$
begin
  ${AS_ADA}
  insert into public.files (id, org_id, file_name, content_type, byte_size, state, uploaded_at, uploaded_by)
  values ('${FILE}', '${ORG}', 'Plan.pdf', 'application/pdf', 1, 'clean', now(), null);
  if (select state from public.files where id = '${FILE}') <> 'pending'
    or (select uploaded_at from public.files where id = '${FILE}') is not null
    or (select uploaded_by from public.files where id = '${FILE}') <> '${ADA}' then
    raise exception 'insert kept %', (select to_jsonb(f) from public.files f);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
