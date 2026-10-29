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

const MODULES: AnyBlocksConfig = {
  attachments: {
    options: {
      offline: true,
      path: "{organization_id}/attachments/{id}.{ext}",
    },
  },
};

const SEED = `
insert into auth.users (id, email) values ('${ADA}', 'ada@example.com');
insert into better_supabase.attachments (id, organization_id, name, mime_type, size, uploaded_by)
values ('${FILE}', '${ORG}', 'Plan.PDF', 'application/pdf', 1, '${ADA}');
`;

const AS_ADA = `perform set_config('request.jwt.claims', '{"role":"authenticated","sub":"${ADA}"}', true);
  perform set_config('request.jwt.claim.sub', '${ADA}', true);`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const PATH = `${ORG}/attachments/${FILE}.pdf`;

const BOOT = { timeout: 60_000 };

async function run(modules: AnyBlocksConfig, check: string): Promise<void> {
  const files = renderBlocks(["attachments"], { modules });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      STUBS,
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

describe("attachments offline", BOOT, () => {
  it("takes client ids, derives {ext} and marks an upload done from storage", async () => {
    await expect(
      run(
        MODULES,
        `${SEED}
do $$
declare
  v_row better_supabase.attachments;
begin
  if not has_column_privilege('authenticated', 'better_supabase.attachments', 'id', 'INSERT') then
    raise exception 'authenticated cannot insert id';
  end if;
  select * into v_row from better_supabase.attachments where id = '${FILE}';
  if v_row.object_path <> '${PATH}' then
    raise exception 'path %', v_row.object_path;
  end if;
  if exists (
    select 1 from pg_attribute
    where attrelid = 'better_supabase.attachments'::regclass and attname = 'object_path' and attgenerated <> ''
  ) then
    raise exception 'object_path is a generated column, which logical replication skips';
  end if;
  insert into storage.objects (bucket_id, name, metadata)
  values ('attachments', '${PATH}', '{"size": 42, "mimetype": "Application/PDF"}');
  select * into v_row from better_supabase.attachments where id = '${FILE}';
  if v_row.uploaded_at is null or v_row.size <> 42 or v_row.status <> 'clean' then
    raise exception 'not marked uploaded: %', to_jsonb(v_row);
  end if;
  ${AS_ADA}
  if (better_supabase.confirm_attachment('${FILE}') ->> 'size')::bigint <> 42 then
    raise exception 'confirm did not return early';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("queues a deleted record's objects until storage or the sweep removes them", async () => {
    await expect(
      run(
        MODULES,
        `${SEED}
insert into storage.objects (bucket_id, name) values ('attachments', '${PATH}');
do $$
declare
  v_items jsonb;
begin
  ${AS_ADA}
  if better_supabase.attachment_object_queued('attachments', '${PATH}') then
    raise exception 'a live record''s object counts as queued';
  end if;
  delete from better_supabase.attachments where id = '${FILE}';
  if not better_supabase.attachment_object_queued('attachments', '${PATH}') then
    raise exception 'the deleted record''s object is not queued for its deleter';
  end if;
  ${SERVICE}
  v_items := better_supabase.queued_attachment_objects(10);
  if v_items <> jsonb_build_array(jsonb_build_object('bucket', 'attachments', 'path', '${PATH}', 'attempts', 1)) then
    raise exception 'queued %', v_items;
  end if;
  delete from storage.objects where name = '${PATH}';
  if exists (select 1 from better_supabase.attachment_cleanup) then
    raise exception 'the storage delete left the queue row';
  end if;
  insert into better_supabase.attachment_cleanup (bucket, path) values ('attachments', 'x/y');
  if better_supabase.complete_attachment_cleanup(jsonb_build_array(jsonb_build_object('bucket', 'attachments', 'path', 'x/y'))) <> 1 then
    raise exception 'complete did not drop the row';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses the sweep to other callers", async () => {
    await expect(
      run(
        MODULES,
        `do $$
begin
  ${AS_ADA}
  perform better_supabase.queued_attachment_objects(10);
end;
$$;`,
      ),
    ).rejects.toThrow(/Only the service role sweeps queued objects/);
  });

  it("keeps requireScan when offline is off", async () => {
    await expect(
      run(
        {},
        `insert into auth.users (id, email) values ('${ADA}', 'ada@example.com');
do $$
begin
  if has_column_privilege('authenticated', 'better_supabase.attachments', 'id', 'INSERT') then
    raise exception 'id is insertable without offline';
  end if;
  if exists (select 1 from pg_trigger where tgname = 'bsb_attachments_object_uploaded') then
    raise exception 'the upload trigger exists without offline';
  end if;
end;
$$;`,
      ),
    ).resolves.toBeUndefined();
  });
});
