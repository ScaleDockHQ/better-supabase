import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const NOTE = "44444444-4444-4444-8444-444444444444";
const FILE = "55555555-5555-4555-8555-555555555555";

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
create schema if not exists realtime;
create table realtime.messages (
  id bigint generated always as identity primary key,
  topic text not null default '',
  extension text not null default 'broadcast'
);
create function realtime.topic() returns text language sql stable
as $$ select nullif(current_setting('realtime.topic', true), '') $$;

-- Every member reads a note; only its owner changes it.
create table public.notes (
  id uuid primary key,
  organization_id uuid not null,
  owner_id uuid not null,
  body text
);
alter table public.notes enable row level security;
create policy notes_read on public.notes for select to authenticated using (true);
create policy notes_write on public.notes for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
`;

const ACCESS = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid where permission not like '%.manage' $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}') on conflict do nothing;
insert into public.notes (id, organization_id, owner_id) values ('${NOTE}', '${TENANT}', '${ALICE}');
-- A file Bob attached before the note became Alice's.
insert into better_supabase.attachments (id, tenant_id, name, mime_type, size, subject_type, subject_id, uploaded_by)
values ('${FILE}', '${TENANT}', 'b.pdf', 'application/pdf', 1, 'note', '${NOTE}', '${BOB}');
grant usage on schema auth to authenticated;
grant select, update (body) on public.notes to authenticated;
`;

const as = (user: string): string =>
  `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);`;

const modules = (upload: string): AnyBlocksConfig => ({
  attachments: {
    on: {
      note: {
        table: "public.notes",
        idType: "uuid",
        tenant: "organization_id",
        upload,
      },
    },
  },
});

const BOOT = { timeout: 60_000 };

async function run(blocks: AnyBlocksConfig, check: string): Promise<void> {
  const files = renderBlocks(["attachments"], { modules: blocks });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      STUBS,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ACCESS,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const attach = `better_supabase.create_attachment('${TENANT}', 'a.pdf', 'application/pdf', 1, 'note', '${NOTE}')`;

describe('attachments upload "subject"', BOOT, () => {
  it("lets only a caller who can change the subject row attach and delete", async () => {
    await expect(
      run(
        modules("subject"),
        `do $$
declare
  v_id uuid;
begin
  set local role authenticated;
  ${as(BOB)}
  if better_supabase.attachment_subject_writable('note', '${NOTE}') then
    raise exception 'a reader counts as able to change the note';
  end if;
  begin
    perform ${attach};
    raise exception 'allowed';
  exception when insufficient_privilege then
    null;
  end;
  ${as(ALICE)}
  if not better_supabase.attachment_subject_writable('note', '${NOTE}') then
    raise exception 'the owner can''t change the note';
  end if;
  v_id := (${attach} ->> 'id')::uuid;
  if not better_supabase.attachment_subject_writable('other', 'x') then
    raise exception 'a type without upload "subject" is refused';
  end if;
  ${as(BOB)}
  if better_supabase.delete_attachment('${FILE}') then
    raise exception 'the uploader deleted a file on a note they can''t change';
  end if;
  ${as(ALICE)}
  if not better_supabase.delete_attachment(v_id) then
    raise exception 'the owner could not delete the file';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("keeps the permission check alone by default", async () => {
    await expect(
      run(
        modules("permission"),
        `do $$
begin
  if exists (select 1 from pg_proc where proname = 'attachment_subject_writable') then
    raise exception 'the subject check is installed without upload "subject"';
  end if;
  set local role authenticated;
  ${as(BOB)}
  perform ${attach};
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses an unknown upload mode", () => {
    expect(() =>
      renderBlocks(["attachments"], { modules: modules("owner") }),
    ).toThrow(/upload must be "permission" or "subject"/u);
  });
});
