-- ==== schema supabase/schemas/900_better_supabase_34_attachments.sql
-- better-supabase module: attachments
-- @bs-module attachments@3 managed
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
create table if not exists "better_supabase"."attachments" (
  "id" uuid primary key default gen_random_uuid(),
  "workspace_id" uuid not null,
  "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text check (length("subject_id") between 1 and 200),
  "bucket" text not null default 'attachments',
  "object_path" text generated always as ("workspace_id"::text || '/attachments/' || "id"::text) stored,
  "name" text not null check (length("name") between 1 and 255),
  "mime_type" text not null check ("mime_type" ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  "size" bigint not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default clock_timestamp(),
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  check (("subject_type" is null) = ("subject_id" is null))
);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "better_supabase"."attachments" add column if not exists "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object');
-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- options.path: the column comment records the template the expression was
-- built from, so a changed template rewrites the column (Postgres 17+).
do $$
declare
  v_current text := coalesce(
    col_description('better_supabase.attachments'::regclass,
      (select attnum from pg_attribute where attrelid = 'better_supabase.attachments'::regclass and attname = 'object_path')::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from 'better-supabase path: {organization_id}/attachments/{id}' then
    if current_setting('server_version_num')::integer < 170000 then
      raise exception 'blocks.attachments.options.path changed, which needs Postgres 17 to rewrite object_path; recreate the column in a migration instead';
    end if;
    execute 'alter table "better_supabase"."attachments" alter column "object_path" set expression as ("workspace_id"::text || ''/attachments/'' || "id"::text)';
  end if;
end;
$$;
comment on column "better_supabase"."attachments"."object_path" is 'better-supabase path: {organization_id}/attachments/{id}';
alter table "better_supabase"."attachments" alter column "bucket" set default 'attachments';
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bs_attachments_bucket'
  ), 'pg_constraint'), '') <> 'better-supabase check 06ecf11d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bs_attachments_bucket";
    alter table "better_supabase"."attachments" add constraint "bs_attachments_bucket" check ("bucket" in ('attachments')) not valid;
    comment on constraint "bs_attachments_bucket" on "better_supabase"."attachments" is 'better-supabase check 06ecf11d';
  end if;
end;
$$;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bs_attachments_size'
  ), 'pg_constraint'), '') <> 'better-supabase check 65b1c9ef' then
    alter table "better_supabase"."attachments" drop constraint if exists "bs_attachments_size";
    alter table "better_supabase"."attachments" add constraint "bs_attachments_size" check ("size" between 0 and 52428800);
    comment on constraint "bs_attachments_size" on "better_supabase"."attachments" is 'better-supabase check 65b1c9ef';
  end if;
end;
$$;
alter table "better_supabase"."attachments" drop constraint if exists bs_attachments_mime_type;
create unique index if not exists attachments_object_idx on "better_supabase"."attachments" ("bucket", "object_path");
create index if not exists attachments_subject_idx on "better_supabase"."attachments" ("workspace_id", "subject_type", "subject_id");
create index if not exists attachments_uploaded_by_idx on "better_supabase"."attachments" ("uploaded_by");
alter table "better_supabase"."attachments" enable row level security;
revoke all on "better_supabase"."attachments" from anon, authenticated;
grant select, delete on "better_supabase"."attachments" to authenticated;
grant insert ("workspace_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata") on "better_supabase"."attachments" to authenticated;
grant all on "better_supabase"."attachments" to service_role;
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with options.subjects, an unlisted type fails.
-- plpgsql, so a subject table a later module creates (messages) binds late.
create or replace function "better_supabase"."attachment_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return true;
end;
$$;
revoke execute on function "better_supabase"."attachment_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."attachment_subject_readable"(text, text, uuid) to authenticated, service_role;

drop policy if exists "attachments_read" on "better_supabase"."attachments";
create policy "attachments_read" on "better_supabase"."attachments" for select to authenticated
  using ("workspace_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "workspace_id"));
drop policy if exists "attachments_insert" on "better_supabase"."attachments";
create policy "attachments_insert" on "better_supabase"."attachments" for insert to authenticated
  with check ((
    "uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "workspace_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "workspace_id")
  ) and (select better_supabase.actor_may_write()));
drop policy if exists "attachments_delete" on "better_supabase"."attachments";
create policy "attachments_delete" on "better_supabase"."attachments" for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "workspace_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a clean file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists "bs_attachments_insert" on storage.objects;
drop policy if exists "bs_attachments_select" on storage.objects;
drop policy if exists "bs_attachments_delete" on storage.objects;
drop function if exists "better_supabase"."attachment_object_allowed"(text, text);
create or replace function "better_supabase"."attachment_object_allowed"(bucket text, path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."attachments" a
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and coalesce(better_supabase.can('tenant', a."workspace_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."workspace_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."workspace_id", 'attachments.manage'), false)
        else false
      end
  )
$$;
revoke execute on function "better_supabase"."attachment_object_allowed"(text, text, text) from public, anon;
grant execute on function "better_supabase"."attachment_object_allowed"(text, text, text) to authenticated, service_role;

-- Whether the caller sees the object's record through the table's own read
-- policy, which checks the subject. It runs as the caller (security invoker):
-- attachment_object_allowed runs as its owner, so it can't apply the subject
-- table's policies itself.
create or replace function "better_supabase"."attachment_object_visible"(bucket text, path text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."attachments" a
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = attachment_object_visible.path
  )
$$;
revoke execute on function "better_supabase"."attachment_object_visible"(text, text) from public, anon;
grant execute on function "better_supabase"."attachment_object_visible"(text, text) to authenticated, service_role;

create policy "bs_attachments_insert" on storage.objects for insert to authenticated
  with check ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy "bs_attachments_select" on storage.objects for select to authenticated
  using (bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'select'));
create policy "bs_attachments_delete" on storage.objects for delete to authenticated
  using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
create or replace function "better_supabase"."create_attachment"(
  tenant uuid,
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into "better_supabase"."attachments" as x ("workspace_id", "bucket", "name", "mime_type", "size", "subject_type", "subject_id", "metadata")
  values (create_attachment.tenant, 'attachments', create_attachment.name, lower(create_attachment.mime_type), create_attachment.size, create_attachment.subject_type, create_attachment.subject_id, coalesce(create_attachment.metadata, '{}'))
  returning to_jsonb(x.*)
$$;

-- Marks the upload done once the object exists, taking its size and type
-- from Storage, and writes attachment.uploaded for the scan job.
create or replace function "better_supabase"."confirm_attachment"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments";
  v_meta jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = confirm_attachment.id for update;
  if v_row."id" is null or (v_row."uploaded_by" is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No pending attachment of yours has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    return to_jsonb(v_row);
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = v_row."object_path";
  if not found then
    raise exception 'The file was not uploaded yet' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_UPLOADED';
  end if;
  update "better_supabase"."attachments" a set
    "uploaded_at" = now(),
    "size" = coalesce((v_meta ->> 'size')::bigint, a."size"),
    "mime_type" = coalesce(lower(v_meta ->> 'mimetype'), a."mime_type")
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;

-- Records a scan result (service role). A clean or infected file keeps its
-- status, so a replayed job changes nothing.
create or replace function "better_supabase"."set_attachment_status"(id uuid, status text, detail text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_attachment_status.status not in ('clean', 'infected', 'failed') then
    raise exception 'status must be clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  update "better_supabase"."attachments" a set
    "status" = set_attachment_status.status,
    "scan_detail" = set_attachment_status.detail,
    "scanned_at" = now()
  where a."id" = set_attachment_status.id
    and a."uploaded_at" is not null
    and a."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."attachments" a where a."id" = set_attachment_status.id;
    return case when v_row."id" is null then null else to_jsonb(v_row) end;
  end if;
  insert into "better_supabase"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", v_row."object_path", v_row."status", v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  null;
  return to_jsonb(v_row);
end;
$$;

create or replace function "better_supabase"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with page as (
    select * from "better_supabase"."attachments" y
    where y."workspace_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  )
  select coalesce(jsonb_agg(to_jsonb(a.*) order by a."created_at", a."id"), '[]'::jsonb)
  from page a
$$;

create or replace function "better_supabase"."get_attachment"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(a.*) from "better_supabase"."attachments" a where a."id" = get_attachment.id
$$;

create or replace function "better_supabase"."delete_attachment"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from "better_supabase"."attachments" a where a."id" = delete_attachment.id returning 1
  )
  select exists (select 1 from removed)
$$;

-- The scan gate for any bucket: one row per scanned object, object_clean()
-- for storage policies, and set_object_scan() for the scanner. With
-- options.scanBuckets, a new object in those buckets gets a pending row and
-- writes object.uploaded for the scan job.
create table if not exists "better_supabase"."scanned_objects" (
  "bucket" text not null,
  "object_path" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "created_at" timestamptz not null default now(),
  "scanned_at" timestamptz,
  primary key ("bucket", "object_path")
);
alter table "better_supabase"."scanned_objects" enable row level security;
revoke all on "better_supabase"."scanned_objects" from anon, authenticated;
grant all on "better_supabase"."scanned_objects" to service_role;

-- For storage policies: whether the object was scanned and found clean.
--   using (bucket_id = 'files' and better_supabase.object_clean(bucket_id, name) and ...)
create or replace function "better_supabase"."object_clean"(bucket text, path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."scanned_objects" s
    where s."bucket" = object_clean.bucket and s."object_path" = object_clean.path and s."status" = 'clean'
  )
$$;

-- The scan row of an object, or null (service role).
create or replace function "better_supabase"."object_scan"(bucket text, path text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(s.*) from "better_supabase"."scanned_objects" s
  where s."bucket" = object_scan.bucket and s."object_path" = object_scan.path
$$;

-- Records a scan result for any object (service role). A clean or infected
-- object keeps its status, so a replayed job changes nothing.
create or replace function "better_supabase"."set_object_scan"(bucket text, path text, status text, detail text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."scanned_objects";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_object_scan.status not in ('pending', 'clean', 'infected', 'failed') then
    raise exception 'status must be pending, clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  insert into "better_supabase"."scanned_objects" as s ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (set_object_scan.bucket, set_object_scan.path, set_object_scan.status, set_object_scan.detail,
    case when set_object_scan.status = 'pending' then null else now() end)
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at"
    where s."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."bucket" is null then
    select * into v_row from "better_supabase"."scanned_objects" s where s."bucket" = set_object_scan.bucket and s."object_path" = set_object_scan.path;
  end if;
  return to_jsonb(v_row);
end;
$$;
drop trigger if exists bs_object_scan_pending on storage.objects;

revoke execute on function "better_supabase"."object_clean"(text, text) from public, anon;
revoke execute on function "better_supabase"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "better_supabase"."object_scan"(text, text) to service_role;
grant execute on function "better_supabase"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "better_supabase"."get_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment"(uuid) from public, anon;
grant execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_attachment_status"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_34_attachments.sql
-- better-supabase module: attachments
-- @bs-module-data attachments
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do nothing;

insert into better_supabase.modules (name, version, mode)
values ('attachments', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
