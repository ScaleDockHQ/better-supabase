-- ==== alone: schema supabase/schemas/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block attachments@8 managed
-- @bsb-hash sha256:e057de8b4923b36e205bcb6d7709278fdaec492bb776c47375503bf0c291efb0
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types text, number, amount, date, expiry, boolean, select.
create table if not exists "better_supabase"."attachment_document_types" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length(btrim("name")) between 1 and 200),
  "fields" jsonb not null default '{}'::jsonb check (jsonb_typeof("fields") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("organization_id", "key")
);
alter table "better_supabase"."attachment_document_types" enable row level security;
revoke all on "better_supabase"."attachment_document_types" from public, anon, authenticated;
grant select on "better_supabase"."attachment_document_types" to authenticated;
grant all on "better_supabase"."attachment_document_types" to service_role;
drop policy if exists attachment_document_types_read on "better_supabase"."attachment_document_types";
create policy attachment_document_types_read on "better_supabase"."attachment_document_types"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')));

-- The reason a document type's field schema is invalid, or null.
create or replace function "better_supabase"."attachment_schema_error"(fields jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in ('text', 'number', 'amount', 'date', 'expiry', 'boolean', 'select') then
      return v_key || ' needs one of the types text, number, amount, date, expiry, boolean, select';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$$;

-- The reason a record's metadata doesn't match a document type's fields, or
-- null. A key the type doesn't declare is left alone.
create or replace function "better_supabase"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachment_schema_error"(jsonb) from public, anon;
revoke execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."attachment_schema_error"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) to authenticated, service_role;

-- Creates or changes the document type with key in an organization.
create or replace function "better_supabase"."define_attachment_document_type"(tenant uuid, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachment_document_types";
  v_error text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', define_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  v_error := "better_supabase"."attachment_schema_error"(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_SCHEMA_INVALID';
  end if;
  insert into "better_supabase"."attachment_document_types" as t ("organization_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("organization_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function "better_supabase"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "better_supabase"."attachment_document_types" t
  where t."organization_id" = list_attachment_document_types.tenant
$$;

-- Deletes a document type that no attachment uses.
create or replace function "better_supabase"."delete_attachment_document_type"(tenant uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', delete_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."attachment_document_types" t
  where t."organization_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  raise exception 'attachments still use this document type' using errcode = '23503', hint = 'ATTACHMENT_DOCUMENT_TYPE_IN_USE';
end;
$$;
revoke execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."list_attachment_document_types"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) from public, anon;
grant execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_document_types"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) to authenticated, service_role;

create table if not exists "better_supabase"."attachments" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check (length("subject_id") between 1 and 200),
  "bucket" text not null default 'attachments',
  "object_path" text,
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
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table "better_supabase"."attachments" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "better_supabase"."attachments" add column if not exists "width" integer check ("width" > 0);
alter table "better_supabase"."attachments" add column if not exists "height" integer check ("height" > 0);
alter table "better_supabase"."attachments" add column if not exists "pages" integer check ("pages" > 0);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "better_supabase"."attachments" add column if not exists "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object');
-- Where a record came from and what it is (ADR 0157). storage_status follows
-- the upload: stored once uploaded_at is set, pending_upload until then, and
-- missing for a record whose file never arrived.
alter table "better_supabase"."attachments" add column if not exists "document_type_id" uuid references "better_supabase"."attachment_document_types" ("id") on delete restrict;
alter table "better_supabase"."attachments" add column if not exists "source" text check (length("source") between 1 and 200);
alter table "better_supabase"."attachments" add column if not exists "external_id" text check (length("external_id") between 1 and 500);
alter table "better_supabase"."attachments" add column if not exists "storage_status" text not null default 'pending_upload' check ("storage_status" in ('stored', 'pending_upload', 'missing'));
alter table "better_supabase"."attachments" add column if not exists "source_path" text check (length("source_path") between 1 and 2000);
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_external'
  ), 'pg_constraint'), '') <> 'better-supabase check 9237e50d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_external";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_external" check (("source" is null) = ("external_id" is null));
    comment on constraint "bsb_attachments_external" on "better_supabase"."attachments" is 'better-supabase check 9237e50d';
  end if;
end;
$$;
create unique index if not exists attachments_external_idx on "better_supabase"."attachments" ("organization_id", "source", "external_id") where "source" is not null;
create index if not exists attachments_document_type_idx on "better_supabase"."attachments" ("document_type_id") where "document_type_id" is not null;
do $$
begin
  update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';
end;
$$;

-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- "object_path" is a plain column a trigger fills: logical replication (PowerSync)
-- skips generated columns. An install from before keeps its values when the
-- expression is dropped.
do $$
begin
  if exists (
    select 1 from pg_attribute
    where attrelid = 'better_supabase.attachments'::regclass
      and attname = 'object_path' and attgenerated <> ''
  ) then
    alter table "better_supabase"."attachments" alter column "object_path" drop expression;
  end if;
end;
$$;
create or replace function "better_supabase"."attachment_object_path"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select "organization_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_object_path"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_object_path on "better_supabase"."attachments";
create trigger bsb_attachments_object_path
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_object_path"();
-- options.path: the column comment records the template the path was built
-- from, so a changed template rewrites every row's path.
do $$
declare
  v_current text := coalesce(
    col_description('better_supabase.attachments'::regclass,
      (select attnum from pg_attribute where attrelid = 'better_supabase.attachments'::regclass and attname = 'object_path')::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from 'better-supabase path: {organization_id}/attachments/{id}' then
    update "better_supabase"."attachments" set "object_path" = null;
  end if;
end;
$$;
comment on column "better_supabase"."attachments"."object_path" is 'better-supabase path: {organization_id}/attachments/{id}';
alter table "better_supabase"."attachments" alter column "bucket" set default 'attachments';
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_bucket'
  ), 'pg_constraint'), '') <> 'better-supabase check 06ecf11d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_bucket";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_bucket" check ("bucket" in ('attachments')) not valid;
    comment on constraint "bsb_attachments_bucket" on "better_supabase"."attachments" is 'better-supabase check 06ecf11d';
  end if;
end;
$$;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_size'
  ), 'pg_constraint'), '') <> 'better-supabase check 65b1c9ef' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_size";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_size" check ("size" between 0 and 52428800);
    comment on constraint "bsb_attachments_size" on "better_supabase"."attachments" is 'better-supabase check 65b1c9ef';
  end if;
end;
$$;
alter table "better_supabase"."attachments" drop constraint if exists bsb_attachments_mime_type;
create unique index if not exists attachments_object_idx on "better_supabase"."attachments" ("bucket", "object_path");
create index if not exists attachments_subject_idx on "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id");
create index if not exists attachments_uploaded_by_idx on "better_supabase"."attachments" ("uploaded_by");
create or replace function "better_supabase"."attachment_document_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[];
  v_fields jsonb;
  v_error text;
begin
  if new."storage_status" in ('stored', 'pending_upload') or new."uploaded_at" is not null then
    new."storage_status" := case when new."uploaded_at" is not null then 'stored' else
      case when new."storage_status" = 'missing' then 'missing' else 'pending_upload' end end;
  end if;
  if new."source" is not null and (tg_op = 'INSERT' or new."source" is distinct from old."source" or new."external_id" is distinct from old."external_id") then
    if not (new."source" = any (array[]::text[])) then
      raise exception 'the source is not in options.sources and has no import run' using errcode = '22023', hint = 'ATTACHMENT_SOURCE_UNKNOWN';
    end if;
    if new."organization_id" is not null and exists (
      select 1 from "better_supabase"."attachments" x
      where x."organization_id" = new."organization_id" and x."source" = new."source" and x."external_id" = new."external_id" and x."id" <> new."id"
    ) then
      raise exception 'an attachment of this source already has this external id' using errcode = '23505', hint = 'ATTACHMENT_EXTERNAL_ID_TAKEN';
    end if;
  end if;
  if new."document_type_id" is not null and (tg_op = 'INSERT' or new."document_type_id" is distinct from old."document_type_id" or new."metadata" is distinct from old."metadata") then
    select y."fields" into v_fields from "better_supabase"."attachment_document_types" y
    where y."id" = new."document_type_id" and y."organization_id" = new."organization_id";
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
    v_error := "better_supabase"."attachment_fields_error"(v_fields, new."metadata");
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_FIELD_INVALID';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_document_guard"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_documents on "better_supabase"."attachments";
create trigger bsb_attachments_documents
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_document_guard"();

alter table "better_supabase"."attachments" enable row level security;
revoke all on "better_supabase"."attachments" from public, anon, authenticated;
grant select, delete on "better_supabase"."attachments" to authenticated;
grant insert ("organization_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata", "width", "height", "pages", "document_type_id", "source", "external_id", "source_path") on "better_supabase"."attachments" to authenticated;
grant all on "better_supabase"."attachments" to service_role;
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with on, an unlisted type fails.
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

drop policy if exists attachments_read on "better_supabase"."attachments";
create policy attachments_read on "better_supabase"."attachments"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"));
drop policy if exists attachments_insert on "better_supabase"."attachments";
create policy attachments_insert on "better_supabase"."attachments"
  for insert to authenticated
  with check (("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id")) and (select better_supabase.actor_may_write()));
drop policy if exists attachments_delete on "better_supabase"."attachments";
create policy attachments_delete on "better_supabase"."attachments"
  for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

-- Tells the tenant's topic which subject's files changed. The payload carries
-- ids only; files without a tenant broadcast nothing.
create or replace function "better_supabase"."attachments_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."organization_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."organization_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_attachments_changed" on "better_supabase"."attachments";
create trigger "bsb_attachments_changed"
  after insert or update or delete on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachments_changed"();

-- Members join attachments:{tenant}; payloads name the subject whose files changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_attachments_receive on realtime.messages;
create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));
  end if;
end;
$do$;

-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
create table if not exists "better_supabase"."attachment_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "attachment_id" uuid not null references "better_supabase"."attachments" ("id") on delete cascade,
  "version" integer not null check ("version" >= 1),
  "bucket" text not null,
  "object_path" text not null,
  "name" text not null,
  "mime_type" text not null,
  "size" bigint not null,
  "width" integer,
  "height" integer,
  "pages" integer,
  "status" text not null check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null,
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  "archived_at" timestamptz not null default now(),
  unique ("attachment_id", "version"),
  unique ("bucket", "object_path")
);
create index if not exists attachment_versions_uploaded_by_idx on "better_supabase"."attachment_versions" ("uploaded_by");
alter table "better_supabase"."attachment_versions" enable row level security;
revoke all on "better_supabase"."attachment_versions" from public, anon, authenticated;
grant select on "better_supabase"."attachment_versions" to authenticated;
grant all on "better_supabase"."attachment_versions" to service_role;
drop policy if exists attachment_versions_read on "better_supabase"."attachment_versions";
create policy attachment_versions_read on "better_supabase"."attachment_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a clean file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists "bsb_attachments_insert" on storage.objects;
drop policy if exists "bsb_attachments_select" on storage.objects;
drop policy if exists "bsb_attachments_delete" on storage.objects;
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
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = any (array[attachment_object_allowed.path, regexp_replace(attachment_object_allowed.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    join "better_supabase"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
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
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = any (array[attachment_object_visible.path, regexp_replace(attachment_object_visible.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_visible.path
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    where v."bucket" = attachment_object_visible.bucket and v."object_path" = attachment_object_visible.path
  )
$$;
revoke execute on function "better_supabase"."attachment_object_visible"(text, text) from public, anon;
grant execute on function "better_supabase"."attachment_object_visible"(text, text) to authenticated, service_role;

drop trigger if exists "bsb_attachments_object_uploaded" on storage.objects;
drop trigger if exists "bsb_attachments_object_removed" on storage.objects;
drop trigger if exists "bsb_attachments_queue_cleanup" on "better_supabase"."attachments";

create policy bsb_attachments_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_select on storage.objects
  for select to authenticated
  using (bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'select'));
create policy bsb_attachments_delete on storage.objects
  for delete to authenticated
  using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_attachment"(
  tenant uuid,
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null,
  width integer default null,
  height integer default null,
  pages integer default null,
  document_type text default null,
  source text default null,
  external_id text default null,
  source_path text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments";
  v_columns text;
begin
  v_row := jsonb_populate_record(null::"better_supabase"."attachments", (
    select coalesce(jsonb_object_agg(e.field_key, e.field_value), '{}'::jsonb)
    from jsonb_each('{}'::jsonb) as e (field_key, field_value)
    where e.field_key = any (array[]::text[])
  ));
  v_row."organization_id" := create_attachment.tenant;
  v_row."bucket" := 'attachments';
  v_row."name" := create_attachment.name;
  v_row."mime_type" := lower(create_attachment.mime_type);
  v_row."size" := create_attachment.size;
  v_row."subject_type" := create_attachment.subject_type;
  v_row."subject_id" := create_attachment.subject_id;
  v_row."metadata" := coalesce(create_attachment.metadata, '{}');
  v_row."width" := create_attachment.width;
  v_row."height" := create_attachment.height;
  v_row."pages" := create_attachment.pages;

  if create_attachment.document_type is not null then
    select y."id" into v_row."document_type_id" from "better_supabase"."attachment_document_types" y
    where y."organization_id" = create_attachment.tenant and y."key" = create_attachment.document_type;
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;
  v_row."source" := create_attachment.source;
  v_row."external_id" := create_attachment.external_id;
  v_row."source_path" := create_attachment.source_path;
  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array['"organization_id"', '"bucket"', '"name"', '"mime_type"', '"size"', '"subject_type"', '"subject_id"', '"metadata"', '"width"', '"height"', '"pages"', '"document_type_id"', '"source"', '"external_id"', '"source_path"']
    || array(select quote_ident(k) from jsonb_object_keys('{}'::jsonb) as k
      where k = any (array[]::text[]))) as column_name;
  execute format('insert into "better_supabase"."attachments" as x (%1$s) select %1$s from (select ($1).*) r returning x.*', v_columns)
  into v_row
  using v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
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
    return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
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
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;


-- The caller takes the upload of a record whose file hasn't arrived (pending
-- upload or missing): they become its uploader, upload to its object_path and
-- call confirm_attachment. The service role leaves the uploader as it is.
create or replace function "better_supabase"."claim_attachment_upload"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = claim_attachment_upload.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to upload this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set
    "storage_status" = 'pending_upload',
    "uploaded_by" = case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then a."uploaded_by" else auth.uid() end
  where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Marks a record whose file will not arrive.
create or replace function "better_supabase"."mark_attachment_missing"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = mark_attachment_missing.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to manage this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set "storage_status" = 'missing' where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;
revoke execute on function "better_supabase"."claim_attachment_upload"(uuid) from public, anon;
revoke execute on function "better_supabase"."mark_attachment_missing"(uuid) from public, anon;
grant execute on function "better_supabase"."claim_attachment_upload"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."mark_attachment_missing"(uuid) to authenticated, service_role;

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
    return case when v_row."id" is null then null else (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end))) end;
  end if;
  insert into "better_supabase"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."status", v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

create or replace function "better_supabase"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."organization_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  )
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a;
  return v_files;
end;
$$;

create or replace function "better_supabase"."get_attachment"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) from "better_supabase"."attachments" a where a."id" = get_attachment.id
$$;


-- Starts a new version of a file: the current one, once uploaded, moves to
-- attachment_versions, and the caller uploads the new file to the returned
-- object_path and confirms it, which scans it again. A file whose upload
-- never finished is replaced in place.
create or replace function "better_supabase"."replace_attachment"(
  id uuid,
  name text,
  mime_type text,
  size bigint,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_next integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = replace_attachment.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  select greatest(v_row."version" - case when v_row."uploaded_at" is null then 1 else 0 end, coalesce(max(v."version"), 0)) + 1
  into v_next
  from "better_supabase"."attachment_versions" v where v."attachment_id" = v_row."id";
  update "better_supabase"."attachments" a set
    "version" = v_next,
    "name" = replace_attachment.name,
    "mime_type" = lower(replace_attachment.mime_type),
    "size" = replace_attachment.size,
    "width" = replace_attachment.width,
    "height" = replace_attachment.height,
    "pages" = replace_attachment.pages,
    "status" = 'pending',
    "scan_detail" = null,
    "uploaded_by" = coalesce(auth.uid(), a."uploaded_by"),
    "uploaded_at" = null,
    "scanned_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Makes an earlier version current again; the current one, once uploaded,
-- becomes an earlier version. No object moves.
create or replace function "better_supabase"."restore_attachment_version"(id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_old "better_supabase"."attachment_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = restore_attachment_version.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may restore has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."attachment_versions" v
  where v."attachment_id" = v_row."id" and v."version" = restore_attachment_version.version
  for update;
  if v_old."id" is null then
    raise exception 'The file has no earlier version with this number' using errcode = 'P0002', hint = 'ATTACHMENT_VERSION_NOT_FOUND';
  end if;
  delete from "better_supabase"."attachment_versions" v where v."id" = v_old."id";
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  update "better_supabase"."attachments" a set
    "version" = v_old."version",
    "name" = v_old."name",
    "mime_type" = v_old."mime_type",
    "size" = v_old."size",
    "width" = v_old."width",
    "height" = v_old."height",
    "pages" = v_old."pages",
    "status" = v_old."status",
    "scan_detail" = v_old."scan_detail",
    "uploaded_by" = v_old."uploaded_by",
    "uploaded_at" = v_old."uploaded_at",
    "scanned_at" = v_old."scanned_at"
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- A file's earlier versions, newest first.
create or replace function "better_supabase"."list_attachment_versions"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(v) order by v."version" desc), '[]'::jsonb)
  from "better_supabase"."attachment_versions" v where v."attachment_id" = list_attachment_versions.id
$$;
revoke execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) from public, anon;
revoke execute on function "better_supabase"."restore_attachment_version"(uuid, integer) from public, anon;
revoke execute on function "better_supabase"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;
grant execute on function "better_supabase"."restore_attachment_version"(uuid, integer) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_versions"(uuid) to authenticated, service_role;

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
revoke all on "better_supabase"."scanned_objects" from public, anon, authenticated;
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
drop trigger if exists bsb_object_scan_pending on storage.objects;

revoke execute on function "better_supabase"."object_clean"(text, text) from public, anon;
revoke execute on function "better_supabase"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "better_supabase"."object_scan"(text, text) to service_role;
grant execute on function "better_supabase"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) from public, anon;
revoke execute on function "better_supabase"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "better_supabase"."get_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment"(uuid) from public, anon;
grant execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_attachment_status"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
create policy bsb_tenant_scope_select on "better_supabase"."attachments" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
create policy bsb_tenant_scope_insert on "better_supabase"."attachments" as restrictive
  for insert to public
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
create policy bsb_tenant_scope_update on "better_supabase"."attachments" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
create policy bsb_tenant_scope_delete on "better_supabase"."attachments" as restrictive
  for delete to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage')))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_document_types" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_document_types" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_document_types" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_document_types" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_versions" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_versions" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_versions" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_versions" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:dcd894555c7feed8442fdb2537836d5a60799ce09a4a91b898f5c7583445388c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block attachments@8 managed
-- @bsb-hash sha256:876864dfcf4b11207c2a5a6630b8431b47f227d8014c5db570f22666bb4cb101
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types text, number, amount, date, expiry, boolean, select.
create table if not exists "better_supabase"."attachment_document_types" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length(btrim("name")) between 1 and 200),
  "fields" jsonb not null default '{}'::jsonb check (jsonb_typeof("fields") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("organization_id", "key")
);
alter table "better_supabase"."attachment_document_types" enable row level security;
revoke all on "better_supabase"."attachment_document_types" from public, anon, authenticated;
grant select on "better_supabase"."attachment_document_types" to authenticated;
grant all on "better_supabase"."attachment_document_types" to service_role;
drop policy if exists attachment_document_types_read on "better_supabase"."attachment_document_types";
create policy attachment_document_types_read on "better_supabase"."attachment_document_types"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')));

-- The reason a document type's field schema is invalid, or null.
create or replace function "better_supabase"."attachment_schema_error"(fields jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in ('text', 'number', 'amount', 'date', 'expiry', 'boolean', 'select') then
      return v_key || ' needs one of the types text, number, amount, date, expiry, boolean, select';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$$;

-- The reason a record's metadata doesn't match a document type's fields, or
-- null. A key the type doesn't declare is left alone.
create or replace function "better_supabase"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachment_schema_error"(jsonb) from public, anon;
revoke execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."attachment_schema_error"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) to authenticated, service_role;

-- Creates or changes the document type with key in an organization.
create or replace function "better_supabase"."define_attachment_document_type"(tenant uuid, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachment_document_types";
  v_error text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', define_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  v_error := "better_supabase"."attachment_schema_error"(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_SCHEMA_INVALID';
  end if;
  insert into "better_supabase"."attachment_document_types" as t ("organization_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("organization_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function "better_supabase"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "better_supabase"."attachment_document_types" t
  where t."organization_id" = list_attachment_document_types.tenant
$$;

-- Deletes a document type that no attachment uses.
create or replace function "better_supabase"."delete_attachment_document_type"(tenant uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', delete_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."attachment_document_types" t
  where t."organization_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  raise exception 'attachments still use this document type' using errcode = '23503', hint = 'ATTACHMENT_DOCUMENT_TYPE_IN_USE';
end;
$$;
revoke execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."list_attachment_document_types"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) from public, anon;
grant execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_document_types"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) to authenticated, service_role;

create table if not exists "better_supabase"."attachments" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check (length("subject_id") between 1 and 200),
  "bucket" text not null default 'attachments',
  "object_path" text,
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
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table "better_supabase"."attachments" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "better_supabase"."attachments" add column if not exists "width" integer check ("width" > 0);
alter table "better_supabase"."attachments" add column if not exists "height" integer check ("height" > 0);
alter table "better_supabase"."attachments" add column if not exists "pages" integer check ("pages" > 0);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "better_supabase"."attachments" add column if not exists "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object');
-- Where a record came from and what it is (ADR 0157). storage_status follows
-- the upload: stored once uploaded_at is set, pending_upload until then, and
-- missing for a record whose file never arrived.
alter table "better_supabase"."attachments" add column if not exists "document_type_id" uuid references "better_supabase"."attachment_document_types" ("id") on delete restrict;
alter table "better_supabase"."attachments" add column if not exists "source" text check (length("source") between 1 and 200);
alter table "better_supabase"."attachments" add column if not exists "external_id" text check (length("external_id") between 1 and 500);
alter table "better_supabase"."attachments" add column if not exists "storage_status" text not null default 'pending_upload' check ("storage_status" in ('stored', 'pending_upload', 'missing'));
alter table "better_supabase"."attachments" add column if not exists "source_path" text check (length("source_path") between 1 and 2000);
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_external'
  ), 'pg_constraint'), '') <> 'better-supabase check 9237e50d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_external";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_external" check (("source" is null) = ("external_id" is null));
    comment on constraint "bsb_attachments_external" on "better_supabase"."attachments" is 'better-supabase check 9237e50d';
  end if;
end;
$$;
create unique index if not exists attachments_external_idx on "better_supabase"."attachments" ("organization_id", "source", "external_id") where "source" is not null;
create index if not exists attachments_document_type_idx on "better_supabase"."attachments" ("document_type_id") where "document_type_id" is not null;
do $$
begin
  update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';
end;
$$;

-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- "object_path" is a plain column a trigger fills: logical replication (PowerSync)
-- skips generated columns. An install from before keeps its values when the
-- expression is dropped.
do $$
begin
  if exists (
    select 1 from pg_attribute
    where attrelid = 'better_supabase.attachments'::regclass
      and attname = 'object_path' and attgenerated <> ''
  ) then
    alter table "better_supabase"."attachments" alter column "object_path" drop expression;
  end if;
end;
$$;
create or replace function "better_supabase"."attachment_object_path"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select "organization_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_object_path"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_object_path on "better_supabase"."attachments";
create trigger bsb_attachments_object_path
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_object_path"();
-- options.path: the column comment records the template the path was built
-- from, so a changed template rewrites every row's path.
do $$
declare
  v_current text := coalesce(
    col_description('better_supabase.attachments'::regclass,
      (select attnum from pg_attribute where attrelid = 'better_supabase.attachments'::regclass and attname = 'object_path')::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from 'better-supabase path: {organization_id}/attachments/{id}' then
    update "better_supabase"."attachments" set "object_path" = null;
  end if;
end;
$$;
comment on column "better_supabase"."attachments"."object_path" is 'better-supabase path: {organization_id}/attachments/{id}';
alter table "better_supabase"."attachments" alter column "bucket" set default 'attachments';
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_bucket'
  ), 'pg_constraint'), '') <> 'better-supabase check 06ecf11d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_bucket";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_bucket" check ("bucket" in ('attachments')) not valid;
    comment on constraint "bsb_attachments_bucket" on "better_supabase"."attachments" is 'better-supabase check 06ecf11d';
  end if;
end;
$$;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_size'
  ), 'pg_constraint'), '') <> 'better-supabase check 65b1c9ef' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_size";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_size" check ("size" between 0 and 52428800);
    comment on constraint "bsb_attachments_size" on "better_supabase"."attachments" is 'better-supabase check 65b1c9ef';
  end if;
end;
$$;
alter table "better_supabase"."attachments" drop constraint if exists bsb_attachments_mime_type;
create unique index if not exists attachments_object_idx on "better_supabase"."attachments" ("bucket", "object_path");
create index if not exists attachments_subject_idx on "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id");
create index if not exists attachments_uploaded_by_idx on "better_supabase"."attachments" ("uploaded_by");
create or replace function "better_supabase"."attachment_document_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[];
  v_fields jsonb;
  v_error text;
begin
  if new."storage_status" in ('stored', 'pending_upload') or new."uploaded_at" is not null then
    new."storage_status" := case when new."uploaded_at" is not null then 'stored' else
      case when new."storage_status" = 'missing' then 'missing' else 'pending_upload' end end;
  end if;
  if new."subject_type" is not null and (tg_op = 'INSERT' or new."subject_type" is distinct from old."subject_type") then
    v_types := "better_supabase"."subject_types"();
    if cardinality(v_types) > 0 and new."subject_type" <> all (v_types) and new."subject_type" <> all (array[]::text[]) then
      raise exception 'the subject type is not a registered subject type' using errcode = '22023', hint = 'ATTACHMENT_SUBJECT_UNKNOWN';
    end if;
  end if;
  if new."source" is not null and (tg_op = 'INSERT' or new."source" is distinct from old."source" or new."external_id" is distinct from old."external_id") then
    if not (new."source" = any (array[]::text[])
      or exists (
        select 1 from "better_supabase"."import_runs" r
        where r."tenant_id" = new."organization_id" and r."source" = new."source"
      )) then
      raise exception 'the source is not in options.sources and has no import run' using errcode = '22023', hint = 'ATTACHMENT_SOURCE_UNKNOWN';
    end if;
    if new."organization_id" is not null and exists (
      select 1 from "better_supabase"."attachments" x
      where x."organization_id" = new."organization_id" and x."source" = new."source" and x."external_id" = new."external_id" and x."id" <> new."id"
    ) then
      raise exception 'an attachment of this source already has this external id' using errcode = '23505', hint = 'ATTACHMENT_EXTERNAL_ID_TAKEN';
    end if;
  end if;
  if new."document_type_id" is not null and (tg_op = 'INSERT' or new."document_type_id" is distinct from old."document_type_id" or new."metadata" is distinct from old."metadata") then
    select y."fields" into v_fields from "better_supabase"."attachment_document_types" y
    where y."id" = new."document_type_id" and y."organization_id" = new."organization_id";
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
    v_error := "better_supabase"."attachment_fields_error"(v_fields, new."metadata");
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_FIELD_INVALID';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_document_guard"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_documents on "better_supabase"."attachments";
create trigger bsb_attachments_documents
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_document_guard"();

alter table "better_supabase"."attachments" enable row level security;
revoke all on "better_supabase"."attachments" from public, anon, authenticated;
grant select, delete on "better_supabase"."attachments" to authenticated;
grant insert ("organization_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata", "width", "height", "pages", "document_type_id", "source", "external_id", "source_path") on "better_supabase"."attachments" to authenticated;
grant all on "better_supabase"."attachments" to service_role;
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with on, an unlisted type fails.
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

drop policy if exists attachments_read on "better_supabase"."attachments";
create policy attachments_read on "better_supabase"."attachments"
  for select to authenticated
  using (("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) or (("organization_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"));
drop policy if exists attachments_insert on "better_supabase"."attachments";
create policy attachments_insert on "better_supabase"."attachments"
  for insert to authenticated
  with check (("uploaded_by" = (select auth.uid())
    and (coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false) or (("organization_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id")) and (select better_supabase.actor_may_write()));
drop policy if exists attachments_delete on "better_supabase"."attachments";
create policy attachments_delete on "better_supabase"."attachments"
  for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

-- Tells the tenant's topic which subject's files changed. The payload carries
-- ids only; files without a tenant broadcast nothing.
create or replace function "better_supabase"."attachments_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."organization_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."organization_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_attachments_changed" on "better_supabase"."attachments";
create trigger "bsb_attachments_changed"
  after insert or update or delete on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachments_changed"();

-- Members join attachments:{tenant}; payloads name the subject whose files changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_attachments_receive on realtime.messages;
create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));
  end if;
end;
$do$;

-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
create table if not exists "better_supabase"."attachment_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "attachment_id" uuid not null references "better_supabase"."attachments" ("id") on delete cascade,
  "version" integer not null check ("version" >= 1),
  "bucket" text not null,
  "object_path" text not null,
  "name" text not null,
  "mime_type" text not null,
  "size" bigint not null,
  "width" integer,
  "height" integer,
  "pages" integer,
  "status" text not null check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null,
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  "archived_at" timestamptz not null default now(),
  unique ("attachment_id", "version"),
  unique ("bucket", "object_path")
);
create index if not exists attachment_versions_uploaded_by_idx on "better_supabase"."attachment_versions" ("uploaded_by");
alter table "better_supabase"."attachment_versions" enable row level security;
revoke all on "better_supabase"."attachment_versions" from public, anon, authenticated;
grant select on "better_supabase"."attachment_versions" to authenticated;
grant all on "better_supabase"."attachment_versions" to service_role;
drop policy if exists attachment_versions_read on "better_supabase"."attachment_versions";
create policy attachment_versions_read on "better_supabase"."attachment_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a clean file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists "bsb_attachments_insert" on storage.objects;
drop policy if exists "bsb_attachments_select" on storage.objects;
drop policy if exists "bsb_attachments_delete" on storage.objects;
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
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = any (array[attachment_object_allowed.path, regexp_replace(attachment_object_allowed.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and (coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false) or ((a."organization_id")::text, (a."subject_type")::text, (a."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    join "better_supabase"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" = 'clean' and (coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false) or ((a."organization_id")::text, (a."subject_type")::text, (a."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
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
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = any (array[attachment_object_visible.path, regexp_replace(attachment_object_visible.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_visible.path
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    where v."bucket" = attachment_object_visible.bucket and v."object_path" = attachment_object_visible.path
  )
$$;
revoke execute on function "better_supabase"."attachment_object_visible"(text, text) from public, anon;
grant execute on function "better_supabase"."attachment_object_visible"(text, text) to authenticated, service_role;

drop trigger if exists "bsb_attachments_object_uploaded" on storage.objects;
drop trigger if exists "bsb_attachments_object_removed" on storage.objects;
drop trigger if exists "bsb_attachments_queue_cleanup" on "better_supabase"."attachments";

create policy bsb_attachments_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_select on storage.objects
  for select to authenticated
  using (bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'select'));
create policy bsb_attachments_delete on storage.objects
  for delete to authenticated
  using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_attachment"(
  tenant uuid,
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null,
  width integer default null,
  height integer default null,
  pages integer default null,
  document_type text default null,
  source text default null,
  external_id text default null,
  source_path text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments";
  v_columns text;
begin
  v_row := jsonb_populate_record(null::"better_supabase"."attachments", (
    select coalesce(jsonb_object_agg(e.field_key, e.field_value), '{}'::jsonb)
    from jsonb_each('{}'::jsonb) as e (field_key, field_value)
    where e.field_key = any (array[]::text[])
  ));
  v_row."organization_id" := create_attachment.tenant;
  v_row."bucket" := 'attachments';
  v_row."name" := create_attachment.name;
  v_row."mime_type" := lower(create_attachment.mime_type);
  v_row."size" := create_attachment.size;
  v_row."subject_type" := create_attachment.subject_type;
  v_row."subject_id" := create_attachment.subject_id;
  v_row."metadata" := coalesce(create_attachment.metadata, '{}');
  v_row."width" := create_attachment.width;
  v_row."height" := create_attachment.height;
  v_row."pages" := create_attachment.pages;

  if create_attachment.document_type is not null then
    select y."id" into v_row."document_type_id" from "better_supabase"."attachment_document_types" y
    where y."organization_id" = create_attachment.tenant and y."key" = create_attachment.document_type;
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;
  v_row."source" := create_attachment.source;
  v_row."external_id" := create_attachment.external_id;
  v_row."source_path" := create_attachment.source_path;
  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array['"organization_id"', '"bucket"', '"name"', '"mime_type"', '"size"', '"subject_type"', '"subject_id"', '"metadata"', '"width"', '"height"', '"pages"', '"document_type_id"', '"source"', '"external_id"', '"source_path"']
    || array(select quote_ident(k) from jsonb_object_keys('{}'::jsonb) as k
      where k = any (array[]::text[]))) as column_name;
  execute format('insert into "better_supabase"."attachments" as x (%1$s) select %1$s from (select ($1).*) r returning x.*', v_columns)
  into v_row
  using v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
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
    return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
  if not found then
    raise exception 'The file was not uploaded yet' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_UPLOADED';
  end if;
  update "better_supabase"."attachments" a set
    "uploaded_at" = now(),
    "size" = coalesce((v_meta ->> 'size')::bigint, a."size"),
    "mime_type" = coalesce(lower(v_meta ->> 'mimetype'), a."mime_type")
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.uploaded', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'mimeType', v_row."mime_type", 'size', v_row."size", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.uploaded',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'mimeType', v_row."mime_type", 'size', v_row."size", 'version', v_row."version")
  );
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;


-- The caller takes the upload of a record whose file hasn't arrived (pending
-- upload or missing): they become its uploader, upload to its object_path and
-- call confirm_attachment. The service role leaves the uploader as it is.
create or replace function "better_supabase"."claim_attachment_upload"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = claim_attachment_upload.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not ((coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false) or ((v_row."organization_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to upload this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set
    "storage_status" = 'pending_upload',
    "uploaded_by" = case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then a."uploaded_by" else auth.uid() end
  where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Marks a record whose file will not arrive.
create or replace function "better_supabase"."mark_attachment_missing"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = mark_attachment_missing.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to manage this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set "storage_status" = 'missing' where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;
revoke execute on function "better_supabase"."claim_attachment_upload"(uuid) from public, anon;
revoke execute on function "better_supabase"."mark_attachment_missing"(uuid) from public, anon;
grant execute on function "better_supabase"."claim_attachment_upload"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."mark_attachment_missing"(uuid) to authenticated, service_role;

-- The import target of the attachment entity (ADR 0157): the record is
-- registered now, and claim_attachment_upload or mark_attachment_missing
-- settles it later. The item key is the external id in the run's source.
create or replace function "better_supabase"."import_attachment"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := (import_attachment.item ->> 'tenant')::uuid;
  v_scope text := coalesce(import_attachment.item ->> 'scope', '');
  v_key text := import_attachment.item ->> 'key';
  v_data jsonb := import_attachment.item -> 'data';
  v_reference jsonb := v_data -> 'subject';
  v_type text := nullif(v_data ->> 'subjectType', '');
  v_subject text := nullif(v_data ->> 'subjectId', '');
  v_source text;
  v_status text := coalesce(v_data ->> 'status', 'pending_upload');
  v_document uuid;
  v_size bigint;
  v_id uuid;
  v_metadata jsonb := coalesce(v_data -> 'metadata', '{}'::jsonb);
begin
  select u."source" into v_source from "better_supabase"."import_runs" u where u."id" = import_attachment.run;
  if v_status not in ('pending_upload', 'missing') then
    raise exception 'an imported attachment is pending_upload or missing' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_metadata) is distinct from 'object' then
    raise exception 'metadata must be an object' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_data ->> 'name' is null then
    raise exception 'an attachment needs a name' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_size := coalesce((v_data ->> 'size')::bigint, 0);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'size must be a whole number of bytes' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_reference is not null then
    if jsonb_typeof(v_reference) is distinct from 'object' then
      raise exception 'subject is { entity, key }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select x."subject_type", x."subject_id" into v_type, v_subject
    from "better_supabase"."import_records" x
    where x."tenant_id" = v_tenant and x."source" = v_source and x."scope" = v_scope
      and x."entity" = v_reference ->> 'entity' and x."external_key" = v_reference ->> 'key'
      and x."role" = 'primary';
    if not found then
      raise exception 'the record isn''t in the import record map; import it first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  if (v_type is null) <> (v_subject is null) then
    raise exception 'an attachment names a subject with both subjectType and subjectId, or none' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_data ->> 'documentType' is not null then
    select y."id" into v_document from "better_supabase"."attachment_document_types" y
    where y."organization_id" = v_tenant and y."key" = v_data ->> 'documentType';
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22022', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;

  select a."id" into v_id from "better_supabase"."attachments" a
  where a."organization_id" = v_tenant and a."source" = v_source and a."external_id" = v_key;
  if found then
    update "better_supabase"."attachments" a set
      "name" = v_data ->> 'name',
      "mime_type" = case when a."uploaded_at" is null then lower(coalesce(v_data ->> 'mimeType', a."mime_type")) else a."mime_type" end,
      "size" = case when a."uploaded_at" is null then v_size else a."size" end,
      "subject_type" = v_type,
      "subject_id" = v_subject,
      "document_type_id" = v_document,
      "metadata" = v_metadata,
      "source_path" = v_data ->> 'sourcePath',
      "storage_status" = case when a."uploaded_at" is null then v_status else a."storage_status" end
    where a."id" = v_id;
  else
    insert into "better_supabase"."attachments" ("organization_id", "name", "mime_type", "size", "subject_type", "subject_id", "document_type_id", "metadata", "source", "external_id", "source_path", "storage_status", "uploaded_by")
    values (v_tenant, v_data ->> 'name', lower(coalesce(v_data ->> 'mimeType', 'application/octet-stream')), v_size, v_type, v_subject, v_document, v_metadata, v_source, v_key, v_data ->> 'sourcePath', v_status, null)
    returning "id" into v_id;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'subjectType', 'attachment');
end;
$$;
revoke execute on function "better_supabase"."import_attachment"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_attachment"(uuid, jsonb, text) to service_role;

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
    return case when v_row."id" is null then null else (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end))) end;
  end if;
  insert into "better_supabase"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."status", v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  perform "better_supabase".emit_event('attachment.scanned', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'status', v_row."status", 'uploadedBy', v_row."uploaded_by"), 'attachments/' || v_row."id"::text, (v_row."organization_id")::text, 'attachment.scanned:' || v_row."id"::text || ':' || v_row."status", 'better-supabase/attachments');
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- The name and avatar of each attachment's uploader, keyed by
-- attachment id, for the attachments of ids the caller may read.
create or replace function "better_supabase"."attachment_authors"(ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(y."id"::text, jsonb_build_object('id', pr."id", 'name', coalesce(nullif(pr."full_name", ''), nullif(trim(concat_ws(' ', pr."first_name", pr."last_name")), ''), pr."username"), 'avatarUrl', pr."avatar_url")), '{}'::jsonb)
  from "better_supabase"."attachments" y
  join "better_supabase"."profiles" pr on pr."id" = y."uploaded_by"
  where y."id" = any ($1)
    and (y."organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) or ((y."organization_id")::text, (y."subject_type")::text, (y."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))
$$;
revoke execute on function "better_supabase"."attachment_authors"(uuid[]) from public, anon;
grant execute on function "better_supabase"."attachment_authors"(uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."organization_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  ),
  m as (select "better_supabase"."attachment_authors"(array(select p."id" from page p)) as authors)
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) || jsonb_build_object('author', m.authors -> a."id"::text) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a, m;
  return v_files;
end;
$$;

create or replace function "better_supabase"."get_attachment"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) from "better_supabase"."attachments" a where a."id" = get_attachment.id
$$;


-- Starts a new version of a file: the current one, once uploaded, moves to
-- attachment_versions, and the caller uploads the new file to the returned
-- object_path and confirms it, which scans it again. A file whose upload
-- never finished is replaced in place.
create or replace function "better_supabase"."replace_attachment"(
  id uuid,
  name text,
  mime_type text,
  size bigint,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_next integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = replace_attachment.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false) or ((v_row."organization_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  select greatest(v_row."version" - case when v_row."uploaded_at" is null then 1 else 0 end, coalesce(max(v."version"), 0)) + 1
  into v_next
  from "better_supabase"."attachment_versions" v where v."attachment_id" = v_row."id";
  update "better_supabase"."attachments" a set
    "version" = v_next,
    "name" = replace_attachment.name,
    "mime_type" = lower(replace_attachment.mime_type),
    "size" = replace_attachment.size,
    "width" = replace_attachment.width,
    "height" = replace_attachment.height,
    "pages" = replace_attachment.pages,
    "status" = 'pending',
    "scan_detail" = null,
    "uploaded_by" = coalesce(auth.uid(), a."uploaded_by"),
    "uploaded_at" = null,
    "scanned_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.replaced', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.replaced',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'version', v_row."version")
  );
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Makes an earlier version current again; the current one, once uploaded,
-- becomes an earlier version. No object moves.
create or replace function "better_supabase"."restore_attachment_version"(id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_old "better_supabase"."attachment_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = restore_attachment_version.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false) or ((v_row."organization_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may restore has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."attachment_versions" v
  where v."attachment_id" = v_row."id" and v."version" = restore_attachment_version.version
  for update;
  if v_old."id" is null then
    raise exception 'The file has no earlier version with this number' using errcode = 'P0002', hint = 'ATTACHMENT_VERSION_NOT_FOUND';
  end if;
  delete from "better_supabase"."attachment_versions" v where v."id" = v_old."id";
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  update "better_supabase"."attachments" a set
    "version" = v_old."version",
    "name" = v_old."name",
    "mime_type" = v_old."mime_type",
    "size" = v_old."size",
    "width" = v_old."width",
    "height" = v_old."height",
    "pages" = v_old."pages",
    "status" = v_old."status",
    "scan_detail" = v_old."scan_detail",
    "uploaded_by" = v_old."uploaded_by",
    "uploaded_at" = v_old."uploaded_at",
    "scanned_at" = v_old."scanned_at"
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.restored', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.restored',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."organization_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'version', v_row."version")
  );
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- A file's earlier versions, newest first.
create or replace function "better_supabase"."list_attachment_versions"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(v) order by v."version" desc), '[]'::jsonb)
  from "better_supabase"."attachment_versions" v where v."attachment_id" = list_attachment_versions.id
$$;
revoke execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) from public, anon;
revoke execute on function "better_supabase"."restore_attachment_version"(uuid, integer) from public, anon;
revoke execute on function "better_supabase"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;
grant execute on function "better_supabase"."restore_attachment_version"(uuid, integer) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_versions"(uuid) to authenticated, service_role;

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
revoke all on "better_supabase"."scanned_objects" from public, anon, authenticated;
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
drop trigger if exists bsb_object_scan_pending on storage.objects;

revoke execute on function "better_supabase"."object_clean"(text, text) from public, anon;
revoke execute on function "better_supabase"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "better_supabase"."object_scan"(text, text) to service_role;
grant execute on function "better_supabase"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) from public, anon;
revoke execute on function "better_supabase"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "better_supabase"."get_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment"(uuid) from public, anon;
grant execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_attachment_status"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
create policy bsb_tenant_scope_select on "better_supabase"."attachments" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) or (("organization_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
create policy bsb_tenant_scope_insert on "better_supabase"."attachments" as restrictive
  for insert to public
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid())
    and (coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false) or (("organization_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
create policy bsb_tenant_scope_update on "better_supabase"."attachments" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
create policy bsb_tenant_scope_delete on "better_supabase"."attachments" as restrictive
  for delete to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage')))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_document_types" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_document_types" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_document_types" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_document_types" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_versions" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_versions" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_versions" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_versions" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:8bdaf0a7ad6cad1fafaa63f09c2777ce7fbd1fee33d6ccc768e4b854c232f591
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.attachments', target_type => 'attachment', event_prefix => 'attachment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block attachments@8 managed
-- @bsb-hash sha256:3bd09767de743ff6088d90559514aa86f4ab49f3cab633381c04d9391609d8d6
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."attachments";
    drop policy if exists bsb_tenant_scope_select on "app_private"."attachments";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."attachments";
    drop policy if exists bsb_tenant_scope_update on "app_private"."attachments";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."attachments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_select on "app_private"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_update on "app_private"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."attachment_document_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."attachment_versions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."attachment_versions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."attachment_versions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."attachment_versions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."attachment_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types text, number, amount, date, expiry, boolean, select.
create table if not exists "app_private"."attachment_document_types" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length(btrim("name")) between 1 and 200),
  "fields" jsonb not null default '{}'::jsonb check (jsonb_typeof("fields") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("organization_id", "key")
);
alter table "app_private"."attachment_document_types" enable row level security;
revoke all on "app_private"."attachment_document_types" from public, anon, authenticated;
grant select on "app_private"."attachment_document_types" to authenticated;
grant all on "app_private"."attachment_document_types" to service_role;
drop policy if exists attachment_document_types_read on "app_private"."attachment_document_types";
create policy attachment_document_types_read on "app_private"."attachment_document_types"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')));

-- The reason a document type's field schema is invalid, or null.
create or replace function "app_private"."attachment_schema_error"(fields jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in ('text', 'number', 'amount', 'date', 'expiry', 'boolean', 'select') then
      return v_key || ' needs one of the types text, number, amount, date, expiry, boolean, select';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$$;

-- The reason a record's metadata doesn't match a document type's fields, or
-- null. A key the type doesn't declare is left alone.
create or replace function "app_private"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function "app_private"."attachment_schema_error"(jsonb) from public, anon;
revoke execute on function "app_private"."attachment_fields_error"(jsonb, jsonb) from public, anon;
grant execute on function "app_private"."attachment_schema_error"(jsonb) to authenticated, service_role;
grant execute on function "app_private"."attachment_fields_error"(jsonb, jsonb) to authenticated, service_role;

-- Creates or changes the document type with key in an organization.
create or replace function "app_private"."define_attachment_document_type"(tenant uuid, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."attachment_document_types";
  v_error text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', define_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  v_error := "app_private"."attachment_schema_error"(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_SCHEMA_INVALID';
  end if;
  insert into "app_private"."attachment_document_types" as t ("organization_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("organization_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function "app_private"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "app_private"."attachment_document_types" t
  where t."organization_id" = list_attachment_document_types.tenant
$$;

-- Deletes a document type that no attachment uses.
create or replace function "app_private"."delete_attachment_document_type"(tenant uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', delete_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  delete from "app_private"."attachment_document_types" t
  where t."organization_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  raise exception 'attachments still use this document type' using errcode = '23503', hint = 'ATTACHMENT_DOCUMENT_TYPE_IN_USE';
end;
$$;
revoke execute on function "app_private"."define_attachment_document_type"(uuid, text, text, jsonb) from public, anon;
revoke execute on function "app_private"."list_attachment_document_types"(uuid) from public, anon;
revoke execute on function "app_private"."delete_attachment_document_type"(uuid, text) from public, anon;
grant execute on function "app_private"."define_attachment_document_type"(uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function "app_private"."list_attachment_document_types"(uuid) to authenticated, service_role;
grant execute on function "app_private"."delete_attachment_document_type"(uuid, text) to authenticated, service_role;

create table if not exists "app_private"."attachments" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check (length("subject_id") between 1 and 200),
  "bucket" text not null default 'attachments',
  "object_path" text,
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
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table "app_private"."attachments" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "app_private"."attachments" add column if not exists "width" integer check ("width" > 0);
alter table "app_private"."attachments" add column if not exists "height" integer check ("height" > 0);
alter table "app_private"."attachments" add column if not exists "pages" integer check ("pages" > 0);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "app_private"."attachments" add column if not exists "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object');
-- Where a record came from and what it is (ADR 0157). storage_status follows
-- the upload: stored once uploaded_at is set, pending_upload until then, and
-- missing for a record whose file never arrived.
alter table "app_private"."attachments" add column if not exists "document_type_id" uuid references "app_private"."attachment_document_types" ("id") on delete restrict;
alter table "app_private"."attachments" add column if not exists "source" text check (length("source") between 1 and 200);
alter table "app_private"."attachments" add column if not exists "external_id" text check (length("external_id") between 1 and 500);
alter table "app_private"."attachments" add column if not exists "storage_status" text not null default 'pending_upload' check ("storage_status" in ('stored', 'pending_upload', 'missing'));
alter table "app_private"."attachments" add column if not exists "source_path" text check (length("source_path") between 1 and 2000);
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"app_private"."attachments"'::regclass and c.conname = 'bsb_attachments_external'
  ), 'pg_constraint'), '') <> 'better-supabase check 9237e50d' then
    alter table "app_private"."attachments" drop constraint if exists "bsb_attachments_external";
    alter table "app_private"."attachments" add constraint "bsb_attachments_external" check (("source" is null) = ("external_id" is null));
    comment on constraint "bsb_attachments_external" on "app_private"."attachments" is 'better-supabase check 9237e50d';
  end if;
end;
$$;
create unique index if not exists attachments_external_idx on "app_private"."attachments" ("organization_id", "source", "external_id") where "source" is not null;
create index if not exists attachments_document_type_idx on "app_private"."attachments" ("document_type_id") where "document_type_id" is not null;
do $$
begin
  update "app_private"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';
end;
$$;

-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- "object_path" is a plain column a trigger fills: logical replication (PowerSync)
-- skips generated columns. An install from before keeps its values when the
-- expression is dropped.
do $$
begin
  if exists (
    select 1 from pg_attribute
    where attrelid = 'app_private.attachments'::regclass
      and attname = 'object_path' and attgenerated <> ''
  ) then
    alter table "app_private"."attachments" alter column "object_path" drop expression;
  end if;
end;
$$;
create or replace function "app_private"."attachment_object_path"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select "organization_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$$;
revoke execute on function "app_private"."attachment_object_path"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_object_path on "app_private"."attachments";
create trigger bsb_attachments_object_path
  before insert or update on "app_private"."attachments"
  for each row execute function "app_private"."attachment_object_path"();
-- options.path: the column comment records the template the path was built
-- from, so a changed template rewrites every row's path.
do $$
declare
  v_current text := coalesce(
    col_description('app_private.attachments'::regclass,
      (select attnum from pg_attribute where attrelid = 'app_private.attachments'::regclass and attname = 'object_path')::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from 'better-supabase path: {organization_id}/attachments/{id}' then
    update "app_private"."attachments" set "object_path" = null;
  end if;
end;
$$;
comment on column "app_private"."attachments"."object_path" is 'better-supabase path: {organization_id}/attachments/{id}';
alter table "app_private"."attachments" alter column "bucket" set default 'attachments';
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"app_private"."attachments"'::regclass and c.conname = 'bsb_attachments_bucket'
  ), 'pg_constraint'), '') <> 'better-supabase check 06ecf11d' then
    alter table "app_private"."attachments" drop constraint if exists "bsb_attachments_bucket";
    alter table "app_private"."attachments" add constraint "bsb_attachments_bucket" check ("bucket" in ('attachments')) not valid;
    comment on constraint "bsb_attachments_bucket" on "app_private"."attachments" is 'better-supabase check 06ecf11d';
  end if;
end;
$$;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"app_private"."attachments"'::regclass and c.conname = 'bsb_attachments_size'
  ), 'pg_constraint'), '') <> 'better-supabase check 65b1c9ef' then
    alter table "app_private"."attachments" drop constraint if exists "bsb_attachments_size";
    alter table "app_private"."attachments" add constraint "bsb_attachments_size" check ("size" between 0 and 52428800);
    comment on constraint "bsb_attachments_size" on "app_private"."attachments" is 'better-supabase check 65b1c9ef';
  end if;
end;
$$;
alter table "app_private"."attachments" drop constraint if exists bsb_attachments_mime_type;
create unique index if not exists attachments_object_idx on "app_private"."attachments" ("bucket", "object_path");
create index if not exists attachments_subject_idx on "app_private"."attachments" ("organization_id", "subject_type", "subject_id");
create index if not exists attachments_uploaded_by_idx on "app_private"."attachments" ("uploaded_by");
create or replace function "app_private"."attachment_document_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[];
  v_fields jsonb;
  v_error text;
begin
  if new."storage_status" in ('stored', 'pending_upload') or new."uploaded_at" is not null then
    new."storage_status" := case when new."uploaded_at" is not null then 'stored' else
      case when new."storage_status" = 'missing' then 'missing' else 'pending_upload' end end;
  end if;
  if new."source" is not null and (tg_op = 'INSERT' or new."source" is distinct from old."source" or new."external_id" is distinct from old."external_id") then
    if not (new."source" = any (array[]::text[])) then
      raise exception 'the source is not in options.sources and has no import run' using errcode = '22023', hint = 'ATTACHMENT_SOURCE_UNKNOWN';
    end if;
    if new."organization_id" is not null and exists (
      select 1 from "app_private"."attachments" x
      where x."organization_id" = new."organization_id" and x."source" = new."source" and x."external_id" = new."external_id" and x."id" <> new."id"
    ) then
      raise exception 'an attachment of this source already has this external id' using errcode = '23505', hint = 'ATTACHMENT_EXTERNAL_ID_TAKEN';
    end if;
  end if;
  if new."document_type_id" is not null and (tg_op = 'INSERT' or new."document_type_id" is distinct from old."document_type_id" or new."metadata" is distinct from old."metadata") then
    select y."fields" into v_fields from "app_private"."attachment_document_types" y
    where y."id" = new."document_type_id" and y."organization_id" = new."organization_id";
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
    v_error := "app_private"."attachment_fields_error"(v_fields, new."metadata");
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_FIELD_INVALID';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function "app_private"."attachment_document_guard"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_documents on "app_private"."attachments";
create trigger bsb_attachments_documents
  before insert or update on "app_private"."attachments"
  for each row execute function "app_private"."attachment_document_guard"();

alter table "app_private"."attachments" enable row level security;
revoke all on "app_private"."attachments" from public, anon, authenticated;
grant select, delete on "app_private"."attachments" to authenticated;
grant insert ("organization_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata", "width", "height", "pages", "document_type_id", "source", "external_id", "source_path") on "app_private"."attachments" to authenticated;
grant all on "app_private"."attachments" to service_role;
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with on, an unlisted type fails.
-- plpgsql, so a subject table a later module creates (messages) binds late.
create or replace function "app_private"."attachment_subject_readable"(subject_type text, subject_id text, tenant uuid)
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
revoke execute on function "app_private"."attachment_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "app_private"."attachment_subject_readable"(text, text, uuid) to authenticated, service_role;

drop policy if exists attachments_read on "app_private"."attachments";
create policy attachments_read on "app_private"."attachments"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "app_private"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"));
drop policy if exists attachments_insert on "app_private"."attachments";
create policy attachments_insert on "app_private"."attachments"
  for insert to authenticated
  with check (("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "app_private"."attachment_subject_readable"("subject_type", "subject_id", "organization_id")) and (select better_supabase.actor_may_write()));
drop policy if exists attachments_delete on "app_private"."attachments";
create policy attachments_delete on "app_private"."attachments"
  for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

-- Tells the tenant's topic which subject's files changed. The payload carries
-- ids only; files without a tenant broadcast nothing.
create or replace function "app_private"."attachments_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."organization_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."organization_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."attachments_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_attachments_changed" on "app_private"."attachments";
create trigger "bsb_attachments_changed"
  after insert or update or delete on "app_private"."attachments"
  for each row execute function "app_private"."attachments_changed"();

-- Members join attachments:{tenant}; payloads name the subject whose files changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_attachments_receive on realtime.messages;
create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));
  end if;
end;
$do$;

-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
create table if not exists "app_private"."attachment_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "attachment_id" uuid not null references "app_private"."attachments" ("id") on delete cascade,
  "version" integer not null check ("version" >= 1),
  "bucket" text not null,
  "object_path" text not null,
  "name" text not null,
  "mime_type" text not null,
  "size" bigint not null,
  "width" integer,
  "height" integer,
  "pages" integer,
  "status" text not null check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null,
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  "archived_at" timestamptz not null default now(),
  unique ("attachment_id", "version"),
  unique ("bucket", "object_path")
);
create index if not exists attachment_versions_uploaded_by_idx on "app_private"."attachment_versions" ("uploaded_by");
alter table "app_private"."attachment_versions" enable row level security;
revoke all on "app_private"."attachment_versions" from public, anon, authenticated;
grant select on "app_private"."attachment_versions" to authenticated;
grant all on "app_private"."attachment_versions" to service_role;
drop policy if exists attachment_versions_read on "app_private"."attachment_versions";
create policy attachment_versions_read on "app_private"."attachment_versions"
  for select to authenticated
  using (exists (select 1 from "app_private"."attachments" a where a."id" = "attachment_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a clean file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists "bsb_attachments_insert" on storage.objects;
drop policy if exists "bsb_attachments_select" on storage.objects;
drop policy if exists "bsb_attachments_delete" on storage.objects;
drop function if exists "app_private"."attachment_object_allowed"(text, text);
create or replace function "app_private"."attachment_object_allowed"(bucket text, path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "app_private"."attachments" a
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = any (array[attachment_object_allowed.path, regexp_replace(attachment_object_allowed.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "app_private"."attachment_versions" v
    join "app_private"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        else false
      end
  )
$$;
revoke execute on function "app_private"."attachment_object_allowed"(text, text, text) from public, anon;
grant execute on function "app_private"."attachment_object_allowed"(text, text, text) to authenticated, service_role;

-- Whether the caller sees the object's record through the table's own read
-- policy, which checks the subject. It runs as the caller (security invoker):
-- attachment_object_allowed runs as its owner, so it can't apply the subject
-- table's policies itself.
create or replace function "app_private"."attachment_object_visible"(bucket text, path text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from "app_private"."attachments" a
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = any (array[attachment_object_visible.path, regexp_replace(attachment_object_visible.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_visible.path
  ) or exists (
    select 1 from "app_private"."attachment_versions" v
    where v."bucket" = attachment_object_visible.bucket and v."object_path" = attachment_object_visible.path
  )
$$;
revoke execute on function "app_private"."attachment_object_visible"(text, text) from public, anon;
grant execute on function "app_private"."attachment_object_visible"(text, text) to authenticated, service_role;

drop trigger if exists "bsb_attachments_object_uploaded" on storage.objects;
drop trigger if exists "bsb_attachments_object_removed" on storage.objects;
drop trigger if exists "bsb_attachments_queue_cleanup" on "app_private"."attachments";

create policy bsb_attachments_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id in ('attachments') and "app_private"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_select on storage.objects
  for select to authenticated
  using (bucket_id in ('attachments') and "app_private"."attachment_object_allowed"(bucket_id, name, 'select'));
create policy bsb_attachments_delete on storage.objects
  for delete to authenticated
  using ((bucket_id in ('attachments') and "app_private"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists "app_private"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "app_private"."create_attachment"(uuid, text, text, bigint, text, text, jsonb);
drop function if exists "app_private"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
drop function if exists "app_private"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);
drop function if exists "app_private"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
drop function if exists "app_private"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text, jsonb);
create or replace function "app_private"."create_attachment"(
  tenant uuid,
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null,
  width integer default null,
  height integer default null,
  pages integer default null,
  document_type text default null,
  source text default null,
  external_id text default null,
  source_path text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."attachments";
  v_columns text;
begin
  v_row := jsonb_populate_record(null::"app_private"."attachments", (
    select coalesce(jsonb_object_agg(e.field_key, e.field_value), '{}'::jsonb)
    from jsonb_each('{}'::jsonb) as e (field_key, field_value)
    where e.field_key = any (array[]::text[])
  ));
  v_row."organization_id" := create_attachment.tenant;
  v_row."bucket" := 'attachments';
  v_row."name" := create_attachment.name;
  v_row."mime_type" := lower(create_attachment.mime_type);
  v_row."size" := create_attachment.size;
  v_row."subject_type" := create_attachment.subject_type;
  v_row."subject_id" := create_attachment.subject_id;
  v_row."metadata" := coalesce(create_attachment.metadata, '{}');
  v_row."width" := create_attachment.width;
  v_row."height" := create_attachment.height;
  v_row."pages" := create_attachment.pages;

  if create_attachment.document_type is not null then
    select y."id" into v_row."document_type_id" from "app_private"."attachment_document_types" y
    where y."organization_id" = create_attachment.tenant and y."key" = create_attachment.document_type;
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;
  v_row."source" := create_attachment.source;
  v_row."external_id" := create_attachment.external_id;
  v_row."source_path" := create_attachment.source_path;
  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array['"organization_id"', '"bucket"', '"name"', '"mime_type"', '"size"', '"subject_type"', '"subject_id"', '"metadata"', '"width"', '"height"', '"pages"', '"document_type_id"', '"source"', '"external_id"', '"source_path"']
    || array(select quote_ident(k) from jsonb_object_keys('{}'::jsonb) as k
      where k = any (array[]::text[]))) as column_name;
  execute format('insert into "app_private"."attachments" as x (%1$s) select %1$s from (select ($1).*) r returning x.*', v_columns)
  into v_row
  using v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Marks the upload done once the object exists, taking its size and type
-- from Storage, and writes attachment.uploaded for the scan job.
create or replace function "app_private"."confirm_attachment"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."attachments";
  v_meta jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."attachments" a where a."id" = confirm_attachment.id for update;
  if v_row."id" is null or (v_row."uploaded_by" is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No pending attachment of yours has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
  if not found then
    raise exception 'The file was not uploaded yet' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_UPLOADED';
  end if;
  update "app_private"."attachments" a set
    "uploaded_at" = now(),
    "size" = coalesce((v_meta ->> 'size')::bigint, a."size"),
    "mime_type" = coalesce(lower(v_meta ->> 'mimetype'), a."mime_type")
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;


-- The caller takes the upload of a record whose file hasn't arrived (pending
-- upload or missing): they become its uploader, upload to its object_path and
-- call confirm_attachment. The service role leaves the uploader as it is.
create or replace function "app_private"."claim_attachment_upload"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."attachments" a where a."id" = claim_attachment_upload.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to upload this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "app_private"."attachments" a set
    "storage_status" = 'pending_upload',
    "uploaded_by" = case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then a."uploaded_by" else auth.uid() end
  where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Marks a record whose file will not arrive.
create or replace function "app_private"."mark_attachment_missing"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."attachments" a where a."id" = mark_attachment_missing.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to manage this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "app_private"."attachments" a set "storage_status" = 'missing' where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;
revoke execute on function "app_private"."claim_attachment_upload"(uuid) from public, anon;
revoke execute on function "app_private"."mark_attachment_missing"(uuid) from public, anon;
grant execute on function "app_private"."claim_attachment_upload"(uuid) to authenticated, service_role;
grant execute on function "app_private"."mark_attachment_missing"(uuid) to authenticated, service_role;

-- Records a scan result (service role). A clean or infected file keeps its
-- status, so a replayed job changes nothing.
create or replace function "app_private"."set_attachment_status"(id uuid, status text, detail text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "app_private"."attachments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_attachment_status.status not in ('clean', 'infected', 'failed') then
    raise exception 'status must be clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  update "app_private"."attachments" a set
    "status" = set_attachment_status.status,
    "scan_detail" = set_attachment_status.detail,
    "scanned_at" = now()
  where a."id" = set_attachment_status.id
    and a."uploaded_at" is not null
    and a."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "app_private"."attachments" a where a."id" = set_attachment_status.id;
    return case when v_row."id" is null then null else (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end))) end;
  end if;
  insert into "app_private"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."status", v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

create or replace function "app_private"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from "app_private"."attachments" y
    where y."organization_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  )
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a;
  return v_files;
end;
$$;

create or replace function "app_private"."get_attachment"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) from "app_private"."attachments" a where a."id" = get_attachment.id
$$;


-- Starts a new version of a file: the current one, once uploaded, moves to
-- attachment_versions, and the caller uploads the new file to the returned
-- object_path and confirms it, which scans it again. A file whose upload
-- never finished is replaced in place.
create or replace function "app_private"."replace_attachment"(
  id uuid,
  name text,
  mime_type text,
  size bigint,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."attachments";
  v_next integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."attachments" a where a."id" = replace_attachment.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "app_private"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  select greatest(v_row."version" - case when v_row."uploaded_at" is null then 1 else 0 end, coalesce(max(v."version"), 0)) + 1
  into v_next
  from "app_private"."attachment_versions" v where v."attachment_id" = v_row."id";
  update "app_private"."attachments" a set
    "version" = v_next,
    "name" = replace_attachment.name,
    "mime_type" = lower(replace_attachment.mime_type),
    "size" = replace_attachment.size,
    "width" = replace_attachment.width,
    "height" = replace_attachment.height,
    "pages" = replace_attachment.pages,
    "status" = 'pending',
    "scan_detail" = null,
    "uploaded_by" = coalesce(auth.uid(), a."uploaded_by"),
    "uploaded_at" = null,
    "scanned_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Makes an earlier version current again; the current one, once uploaded,
-- becomes an earlier version. No object moves.
create or replace function "app_private"."restore_attachment_version"(id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."attachments";
  v_old "app_private"."attachment_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."attachments" a where a."id" = restore_attachment_version.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may restore has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  select * into v_old from "app_private"."attachment_versions" v
  where v."attachment_id" = v_row."id" and v."version" = restore_attachment_version.version
  for update;
  if v_old."id" is null then
    raise exception 'The file has no earlier version with this number' using errcode = 'P0002', hint = 'ATTACHMENT_VERSION_NOT_FOUND';
  end if;
  delete from "app_private"."attachment_versions" v where v."id" = v_old."id";
  if v_row."uploaded_at" is not null then
    insert into "app_private"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  update "app_private"."attachments" a set
    "version" = v_old."version",
    "name" = v_old."name",
    "mime_type" = v_old."mime_type",
    "size" = v_old."size",
    "width" = v_old."width",
    "height" = v_old."height",
    "pages" = v_old."pages",
    "status" = v_old."status",
    "scan_detail" = v_old."scan_detail",
    "uploaded_by" = v_old."uploaded_by",
    "uploaded_at" = v_old."uploaded_at",
    "scanned_at" = v_old."scanned_at"
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- A file's earlier versions, newest first.
create or replace function "app_private"."list_attachment_versions"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(v) order by v."version" desc), '[]'::jsonb)
  from "app_private"."attachment_versions" v where v."attachment_id" = list_attachment_versions.id
$$;
revoke execute on function "app_private"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) from public, anon;
revoke execute on function "app_private"."restore_attachment_version"(uuid, integer) from public, anon;
revoke execute on function "app_private"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "app_private"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;
grant execute on function "app_private"."restore_attachment_version"(uuid, integer) to authenticated, service_role;
grant execute on function "app_private"."list_attachment_versions"(uuid) to authenticated, service_role;

create or replace function "app_private"."delete_attachment"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    delete from "app_private"."attachments" a where a."id" = delete_attachment.id returning 1
  )
  select exists (select 1 from removed)
$$;

-- The scan gate for any bucket: one row per scanned object, object_clean()
-- for storage policies, and set_object_scan() for the scanner. With
-- options.scanBuckets, a new object in those buckets gets a pending row and
-- writes object.uploaded for the scan job.
create table if not exists "app_private"."scanned_objects" (
  "bucket" text not null,
  "object_path" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "created_at" timestamptz not null default now(),
  "scanned_at" timestamptz,
  primary key ("bucket", "object_path")
);
alter table "app_private"."scanned_objects" enable row level security;
revoke all on "app_private"."scanned_objects" from public, anon, authenticated;
grant all on "app_private"."scanned_objects" to service_role;

-- For storage policies: whether the object was scanned and found clean.
--   using (bucket_id = 'files' and better_supabase.object_clean(bucket_id, name) and ...)
create or replace function "app_private"."object_clean"(bucket text, path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "app_private"."scanned_objects" s
    where s."bucket" = object_clean.bucket and s."object_path" = object_clean.path and s."status" = 'clean'
  )
$$;

-- The scan row of an object, or null (service role).
create or replace function "app_private"."object_scan"(bucket text, path text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(s.*) from "app_private"."scanned_objects" s
  where s."bucket" = object_scan.bucket and s."object_path" = object_scan.path
$$;

-- Records a scan result for any object (service role). A clean or infected
-- object keeps its status, so a replayed job changes nothing.
create or replace function "app_private"."set_object_scan"(bucket text, path text, status text, detail text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."scanned_objects";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records scan results' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if set_object_scan.status not in ('pending', 'clean', 'infected', 'failed') then
    raise exception 'status must be pending, clean, infected or failed' using errcode = '22023', hint = 'ATTACHMENT_STATUS_UNKNOWN';
  end if;
  insert into "app_private"."scanned_objects" as s ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (set_object_scan.bucket, set_object_scan.path, set_object_scan.status, set_object_scan.detail,
    case when set_object_scan.status = 'pending' then null else now() end)
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at"
    where s."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."bucket" is null then
    select * into v_row from "app_private"."scanned_objects" s where s."bucket" = set_object_scan.bucket and s."object_path" = set_object_scan.path;
  end if;
  return to_jsonb(v_row);
end;
$$;
drop trigger if exists bsb_object_scan_pending on storage.objects;

revoke execute on function "app_private"."object_clean"(text, text) from public, anon;
revoke execute on function "app_private"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "app_private"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "app_private"."object_scan"(text, text) to service_role;
grant execute on function "app_private"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "app_private"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) from public, anon;
revoke execute on function "app_private"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "app_private"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "app_private"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "app_private"."get_attachment"(uuid) from public, anon;
revoke execute on function "app_private"."delete_attachment"(uuid) from public, anon;
grant execute on function "app_private"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) to authenticated, service_role;
grant execute on function "app_private"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "app_private"."set_attachment_status"(uuid, text, text) to service_role;
grant execute on function "app_private"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "app_private"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "app_private"."delete_attachment"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "app_private"."attachments";
drop policy if exists bsb_tenant_scope_select on "app_private"."attachments";
create policy bsb_tenant_scope_select on "app_private"."attachments" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "app_private"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."attachments";
create policy bsb_tenant_scope_insert on "app_private"."attachments" as restrictive
  for insert to public
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "app_private"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_update on "app_private"."attachments";
create policy bsb_tenant_scope_update on "app_private"."attachments" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."attachments";
create policy bsb_tenant_scope_delete on "app_private"."attachments" as restrictive
  for delete to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage')))
  );
drop policy if exists bsb_tenant_scope on "app_private"."attachment_document_types";
drop policy if exists bsb_tenant_scope_select on "app_private"."attachment_document_types";
create policy bsb_tenant_scope_select on "app_private"."attachment_document_types" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."attachment_document_types";
create policy bsb_tenant_scope_insert on "app_private"."attachment_document_types" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."attachment_document_types";
create policy bsb_tenant_scope_update on "app_private"."attachment_document_types" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."attachment_document_types";
create policy bsb_tenant_scope_delete on "app_private"."attachment_document_types" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."attachment_versions";
drop policy if exists bsb_tenant_scope_select on "app_private"."attachment_versions";
create policy bsb_tenant_scope_select on "app_private"."attachment_versions" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."attachments" a where a."id" = "attachment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."attachment_versions";
create policy bsb_tenant_scope_insert on "app_private"."attachment_versions" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."attachment_versions";
create policy bsb_tenant_scope_update on "app_private"."attachment_versions" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."attachment_versions";
create policy bsb_tenant_scope_delete on "app_private"."attachment_versions" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:dcd894555c7feed8442fdb2537836d5a60799ce09a4a91b898f5c7583445388c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block attachments@8 managed
-- @bsb-hash sha256:962511ba212a63da484b6dc60c3c4a276689b8438e71d99b2da66fb19563264c
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types text, number, amount, date, expiry, boolean, select.
create table if not exists "better_supabase"."attachment_document_types" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length(btrim("name")) between 1 and 200),
  "fields" jsonb not null default '{}'::jsonb check (jsonb_typeof("fields") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("organization_id", "key")
);
alter table "better_supabase"."attachment_document_types" enable row level security;
revoke all on "better_supabase"."attachment_document_types" from public, anon, authenticated;
grant select on "better_supabase"."attachment_document_types" to authenticated;
grant all on "better_supabase"."attachment_document_types" to service_role;
drop policy if exists attachment_document_types_read on "better_supabase"."attachment_document_types";
create policy attachment_document_types_read on "better_supabase"."attachment_document_types"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')));

-- The reason a document type's field schema is invalid, or null.
create or replace function "better_supabase"."attachment_schema_error"(fields jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in ('text', 'number', 'amount', 'date', 'expiry', 'boolean', 'select') then
      return v_key || ' needs one of the types text, number, amount, date, expiry, boolean, select';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$$;

-- The reason a record's metadata doesn't match a document type's fields, or
-- null. A key the type doesn't declare is left alone.
create or replace function "better_supabase"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachment_schema_error"(jsonb) from public, anon;
revoke execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."attachment_schema_error"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) to authenticated, service_role;

-- Creates or changes the document type with key in an organization.
create or replace function "better_supabase"."define_attachment_document_type"(tenant uuid, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachment_document_types";
  v_error text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', define_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  v_error := "better_supabase"."attachment_schema_error"(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_SCHEMA_INVALID';
  end if;
  insert into "better_supabase"."attachment_document_types" as t ("organization_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("organization_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function "better_supabase"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "better_supabase"."attachment_document_types" t
  where t."organization_id" = list_attachment_document_types.tenant
$$;

-- Deletes a document type that no attachment uses.
create or replace function "better_supabase"."delete_attachment_document_type"(tenant uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', delete_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."attachment_document_types" t
  where t."organization_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  raise exception 'attachments still use this document type' using errcode = '23503', hint = 'ATTACHMENT_DOCUMENT_TYPE_IN_USE';
end;
$$;
revoke execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."list_attachment_document_types"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) from public, anon;
grant execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_document_types"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) to authenticated, service_role;

create table if not exists "better_supabase"."attachments" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check (length("subject_id") between 1 and 200),
  "bucket" text not null default 'attachments',
  "object_path" text,
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
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table "better_supabase"."attachments" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "better_supabase"."attachments" add column if not exists "width" integer check ("width" > 0);
alter table "better_supabase"."attachments" add column if not exists "height" integer check ("height" > 0);
alter table "better_supabase"."attachments" add column if not exists "pages" integer check ("pages" > 0);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "better_supabase"."attachments" add column if not exists "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object');
-- Where a record came from and what it is (ADR 0157). storage_status follows
-- the upload: stored once uploaded_at is set, pending_upload until then, and
-- missing for a record whose file never arrived.
alter table "better_supabase"."attachments" add column if not exists "document_type_id" uuid references "better_supabase"."attachment_document_types" ("id") on delete restrict;
alter table "better_supabase"."attachments" add column if not exists "source" text check (length("source") between 1 and 200);
alter table "better_supabase"."attachments" add column if not exists "external_id" text check (length("external_id") between 1 and 500);
alter table "better_supabase"."attachments" add column if not exists "storage_status" text not null default 'pending_upload' check ("storage_status" in ('stored', 'pending_upload', 'missing'));
alter table "better_supabase"."attachments" add column if not exists "source_path" text check (length("source_path") between 1 and 2000);
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_external'
  ), 'pg_constraint'), '') <> 'better-supabase check 9237e50d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_external";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_external" check (("source" is null) = ("external_id" is null));
    comment on constraint "bsb_attachments_external" on "better_supabase"."attachments" is 'better-supabase check 9237e50d';
  end if;
end;
$$;
create unique index if not exists attachments_external_idx on "better_supabase"."attachments" ("organization_id", "source", "external_id") where "source" is not null;
create index if not exists attachments_document_type_idx on "better_supabase"."attachments" ("document_type_id") where "document_type_id" is not null;
do $$
begin
  update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';
end;
$$;

-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- "object_path" is a plain column a trigger fills: logical replication (PowerSync)
-- skips generated columns. An install from before keeps its values when the
-- expression is dropped.
do $$
begin
  if exists (
    select 1 from pg_attribute
    where attrelid = 'better_supabase.attachments'::regclass
      and attname = 'object_path' and attgenerated <> ''
  ) then
    alter table "better_supabase"."attachments" alter column "object_path" drop expression;
  end if;
end;
$$;
create or replace function "better_supabase"."attachment_object_path"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select "organization_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_object_path"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_object_path on "better_supabase"."attachments";
create trigger bsb_attachments_object_path
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_object_path"();
-- options.path: the column comment records the template the path was built
-- from, so a changed template rewrites every row's path.
do $$
declare
  v_current text := coalesce(
    col_description('better_supabase.attachments'::regclass,
      (select attnum from pg_attribute where attrelid = 'better_supabase.attachments'::regclass and attname = 'object_path')::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from 'better-supabase path: {organization_id}/attachments/{id}' then
    update "better_supabase"."attachments" set "object_path" = null;
  end if;
end;
$$;
comment on column "better_supabase"."attachments"."object_path" is 'better-supabase path: {organization_id}/attachments/{id}';
alter table "better_supabase"."attachments" alter column "bucket" set default 'attachments';
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_bucket'
  ), 'pg_constraint'), '') <> 'better-supabase check 06ecf11d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_bucket";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_bucket" check ("bucket" in ('attachments')) not valid;
    comment on constraint "bsb_attachments_bucket" on "better_supabase"."attachments" is 'better-supabase check 06ecf11d';
  end if;
end;
$$;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_size'
  ), 'pg_constraint'), '') <> 'better-supabase check 65b1c9ef' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_size";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_size" check ("size" between 0 and 52428800);
    comment on constraint "bsb_attachments_size" on "better_supabase"."attachments" is 'better-supabase check 65b1c9ef';
  end if;
end;
$$;
alter table "better_supabase"."attachments" drop constraint if exists bsb_attachments_mime_type;
create unique index if not exists attachments_object_idx on "better_supabase"."attachments" ("bucket", "object_path");
create index if not exists attachments_subject_idx on "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id");
create index if not exists attachments_uploaded_by_idx on "better_supabase"."attachments" ("uploaded_by");
create or replace function "better_supabase"."attachment_document_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[];
  v_fields jsonb;
  v_error text;
begin
  if new."storage_status" in ('stored', 'pending_upload') or new."uploaded_at" is not null then
    new."storage_status" := case when new."uploaded_at" is not null then 'stored' else
      case when new."storage_status" = 'missing' then 'missing' else 'pending_upload' end end;
  end if;
  if new."source" is not null and (tg_op = 'INSERT' or new."source" is distinct from old."source" or new."external_id" is distinct from old."external_id") then
    if not (new."source" = any (array[]::text[])) then
      raise exception 'the source is not in options.sources and has no import run' using errcode = '22023', hint = 'ATTACHMENT_SOURCE_UNKNOWN';
    end if;
    if new."organization_id" is not null and exists (
      select 1 from "better_supabase"."attachments" x
      where x."organization_id" = new."organization_id" and x."source" = new."source" and x."external_id" = new."external_id" and x."id" <> new."id"
    ) then
      raise exception 'an attachment of this source already has this external id' using errcode = '23505', hint = 'ATTACHMENT_EXTERNAL_ID_TAKEN';
    end if;
  end if;
  if new."document_type_id" is not null and (tg_op = 'INSERT' or new."document_type_id" is distinct from old."document_type_id" or new."metadata" is distinct from old."metadata") then
    select y."fields" into v_fields from "better_supabase"."attachment_document_types" y
    where y."id" = new."document_type_id" and y."organization_id" = new."organization_id";
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
    v_error := "better_supabase"."attachment_fields_error"(v_fields, new."metadata");
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_FIELD_INVALID';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_document_guard"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_documents on "better_supabase"."attachments";
create trigger bsb_attachments_documents
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_document_guard"();

alter table "better_supabase"."attachments" enable row level security;
revoke all on "better_supabase"."attachments" from public, anon, authenticated;
grant select, delete on "better_supabase"."attachments" to authenticated;
grant insert ("organization_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata", "width", "height", "pages", "document_type_id", "source", "external_id", "source_path") on "better_supabase"."attachments" to authenticated;
grant all on "better_supabase"."attachments" to service_role;
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with on, an unlisted type fails.
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

drop policy if exists attachments_read on "better_supabase"."attachments";
create policy attachments_read on "better_supabase"."attachments"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"));
drop policy if exists attachments_insert on "better_supabase"."attachments";
create policy attachments_insert on "better_supabase"."attachments"
  for insert to authenticated
  with check (("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id")) and (select better_supabase.actor_may_write()));
drop policy if exists attachments_delete on "better_supabase"."attachments";
create policy attachments_delete on "better_supabase"."attachments"
  for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

-- Tells the tenant's topic which subject's files changed. The payload carries
-- ids only; files without a tenant broadcast nothing.
create or replace function "better_supabase"."attachments_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."organization_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."organization_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_attachments_changed" on "better_supabase"."attachments";
create trigger "bsb_attachments_changed"
  after insert or update or delete on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachments_changed"();

-- Members join attachments:{tenant}; payloads name the subject whose files changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_attachments_receive on realtime.messages;
create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));
  end if;
end;
$do$;

-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
create table if not exists "better_supabase"."attachment_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "attachment_id" uuid not null references "better_supabase"."attachments" ("id") on delete cascade,
  "version" integer not null check ("version" >= 1),
  "bucket" text not null,
  "object_path" text not null,
  "name" text not null,
  "mime_type" text not null,
  "size" bigint not null,
  "width" integer,
  "height" integer,
  "pages" integer,
  "status" text not null check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null,
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  "archived_at" timestamptz not null default now(),
  unique ("attachment_id", "version"),
  unique ("bucket", "object_path")
);
create index if not exists attachment_versions_uploaded_by_idx on "better_supabase"."attachment_versions" ("uploaded_by");
alter table "better_supabase"."attachment_versions" enable row level security;
revoke all on "better_supabase"."attachment_versions" from public, anon, authenticated;
grant select on "better_supabase"."attachment_versions" to authenticated;
grant all on "better_supabase"."attachment_versions" to service_role;
drop policy if exists attachment_versions_read on "better_supabase"."attachment_versions";
create policy attachment_versions_read on "better_supabase"."attachment_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a clean file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists "bsb_attachments_insert" on storage.objects;
drop policy if exists "bsb_attachments_select" on storage.objects;
drop policy if exists "bsb_attachments_delete" on storage.objects;
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
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = any (array[attachment_object_allowed.path, regexp_replace(attachment_object_allowed.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    join "better_supabase"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
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
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = any (array[attachment_object_visible.path, regexp_replace(attachment_object_visible.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_visible.path
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    where v."bucket" = attachment_object_visible.bucket and v."object_path" = attachment_object_visible.path
  )
$$;
revoke execute on function "better_supabase"."attachment_object_visible"(text, text) from public, anon;
grant execute on function "better_supabase"."attachment_object_visible"(text, text) to authenticated, service_role;

drop trigger if exists "bsb_attachments_object_uploaded" on storage.objects;
drop trigger if exists "bsb_attachments_object_removed" on storage.objects;
drop trigger if exists "bsb_attachments_queue_cleanup" on "better_supabase"."attachments";

create policy bsb_attachments_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_select on storage.objects
  for select to authenticated
  using (bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'select'));
create policy bsb_attachments_delete on storage.objects
  for delete to authenticated
  using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_attachment"(
  tenant uuid,
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null,
  width integer default null,
  height integer default null,
  pages integer default null,
  document_type text default null,
  source text default null,
  external_id text default null,
  source_path text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments";
  v_columns text;
begin
  v_row := jsonb_populate_record(null::"better_supabase"."attachments", (
    select coalesce(jsonb_object_agg(e.field_key, e.field_value), '{}'::jsonb)
    from jsonb_each('{}'::jsonb) as e (field_key, field_value)
    where e.field_key = any (array[]::text[])
  ));
  v_row."organization_id" := create_attachment.tenant;
  v_row."bucket" := 'attachments';
  v_row."name" := create_attachment.name;
  v_row."mime_type" := lower(create_attachment.mime_type);
  v_row."size" := create_attachment.size;
  v_row."subject_type" := create_attachment.subject_type;
  v_row."subject_id" := create_attachment.subject_id;
  v_row."metadata" := coalesce(create_attachment.metadata, '{}');
  v_row."width" := create_attachment.width;
  v_row."height" := create_attachment.height;
  v_row."pages" := create_attachment.pages;

  if create_attachment.document_type is not null then
    select y."id" into v_row."document_type_id" from "better_supabase"."attachment_document_types" y
    where y."organization_id" = create_attachment.tenant and y."key" = create_attachment.document_type;
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;
  v_row."source" := create_attachment.source;
  v_row."external_id" := create_attachment.external_id;
  v_row."source_path" := create_attachment.source_path;
  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array['"organization_id"', '"bucket"', '"name"', '"mime_type"', '"size"', '"subject_type"', '"subject_id"', '"metadata"', '"width"', '"height"', '"pages"', '"document_type_id"', '"source"', '"external_id"', '"source_path"']
    || array(select quote_ident(k) from jsonb_object_keys('{}'::jsonb) as k
      where k = any (array[]::text[]))) as column_name;
  execute format('insert into "better_supabase"."attachments" as x (%1$s) select %1$s from (select ($1).*) r returning x.*', v_columns)
  into v_row
  using v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
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
    return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
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
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;


-- The caller takes the upload of a record whose file hasn't arrived (pending
-- upload or missing): they become its uploader, upload to its object_path and
-- call confirm_attachment. The service role leaves the uploader as it is.
create or replace function "better_supabase"."claim_attachment_upload"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = claim_attachment_upload.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to upload this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set
    "storage_status" = 'pending_upload',
    "uploaded_by" = case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then a."uploaded_by" else auth.uid() end
  where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Marks a record whose file will not arrive.
create or replace function "better_supabase"."mark_attachment_missing"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = mark_attachment_missing.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to manage this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set "storage_status" = 'missing' where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;
revoke execute on function "better_supabase"."claim_attachment_upload"(uuid) from public, anon;
revoke execute on function "better_supabase"."mark_attachment_missing"(uuid) from public, anon;
grant execute on function "better_supabase"."claim_attachment_upload"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."mark_attachment_missing"(uuid) to authenticated, service_role;

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
    return case when v_row."id" is null then null else (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end))) end;
  end if;
  insert into "better_supabase"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."status", v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

create or replace function "better_supabase"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."organization_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  )
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a;
  return v_files;
end;
$$;

create or replace function "better_supabase"."get_attachment"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) from "better_supabase"."attachments" a where a."id" = get_attachment.id
$$;


-- Starts a new version of a file: the current one, once uploaded, moves to
-- attachment_versions, and the caller uploads the new file to the returned
-- object_path and confirms it, which scans it again. A file whose upload
-- never finished is replaced in place.
create or replace function "better_supabase"."replace_attachment"(
  id uuid,
  name text,
  mime_type text,
  size bigint,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_next integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = replace_attachment.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  select greatest(v_row."version" - case when v_row."uploaded_at" is null then 1 else 0 end, coalesce(max(v."version"), 0)) + 1
  into v_next
  from "better_supabase"."attachment_versions" v where v."attachment_id" = v_row."id";
  update "better_supabase"."attachments" a set
    "version" = v_next,
    "name" = replace_attachment.name,
    "mime_type" = lower(replace_attachment.mime_type),
    "size" = replace_attachment.size,
    "width" = replace_attachment.width,
    "height" = replace_attachment.height,
    "pages" = replace_attachment.pages,
    "status" = 'pending',
    "scan_detail" = null,
    "uploaded_by" = coalesce(auth.uid(), a."uploaded_by"),
    "uploaded_at" = null,
    "scanned_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Makes an earlier version current again; the current one, once uploaded,
-- becomes an earlier version. No object moves.
create or replace function "better_supabase"."restore_attachment_version"(id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_old "better_supabase"."attachment_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = restore_attachment_version.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may restore has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."attachment_versions" v
  where v."attachment_id" = v_row."id" and v."version" = restore_attachment_version.version
  for update;
  if v_old."id" is null then
    raise exception 'The file has no earlier version with this number' using errcode = 'P0002', hint = 'ATTACHMENT_VERSION_NOT_FOUND';
  end if;
  delete from "better_supabase"."attachment_versions" v where v."id" = v_old."id";
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  update "better_supabase"."attachments" a set
    "version" = v_old."version",
    "name" = v_old."name",
    "mime_type" = v_old."mime_type",
    "size" = v_old."size",
    "width" = v_old."width",
    "height" = v_old."height",
    "pages" = v_old."pages",
    "status" = v_old."status",
    "scan_detail" = v_old."scan_detail",
    "uploaded_by" = v_old."uploaded_by",
    "uploaded_at" = v_old."uploaded_at",
    "scanned_at" = v_old."scanned_at"
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- A file's earlier versions, newest first.
create or replace function "better_supabase"."list_attachment_versions"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(v) order by v."version" desc), '[]'::jsonb)
  from "better_supabase"."attachment_versions" v where v."attachment_id" = list_attachment_versions.id
$$;
revoke execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) from public, anon;
revoke execute on function "better_supabase"."restore_attachment_version"(uuid, integer) from public, anon;
revoke execute on function "better_supabase"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;
grant execute on function "better_supabase"."restore_attachment_version"(uuid, integer) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_versions"(uuid) to authenticated, service_role;

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
revoke all on "better_supabase"."scanned_objects" from public, anon, authenticated;
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
drop trigger if exists bsb_object_scan_pending on storage.objects;

revoke execute on function "better_supabase"."object_clean"(text, text) from public, anon;
revoke execute on function "better_supabase"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "better_supabase"."object_scan"(text, text) to service_role;
grant execute on function "better_supabase"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) from public, anon;
revoke execute on function "better_supabase"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "better_supabase"."get_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment"(uuid) from public, anon;
grant execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_attachment_status"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
create policy bsb_tenant_scope_select on "better_supabase"."attachments" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
create policy bsb_tenant_scope_insert on "better_supabase"."attachments" as restrictive
  for insert to public
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
create policy bsb_tenant_scope_update on "better_supabase"."attachments" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
create policy bsb_tenant_scope_delete on "better_supabase"."attachments" as restrictive
  for delete to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage')))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_document_types" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_document_types" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_document_types" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_document_types" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_versions" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_versions" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_versions" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_versions" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.attachments.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."attachment_subject_readable"(text, text, uuid);
drop function if exists "api"."attachment_object_allowed"(text, text, text);
drop function if exists "api"."attachment_object_visible"(text, text);
drop function if exists "api"."object_clean"(text, text);

drop function if exists "api"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "api"."create_attachment"(uuid, text, text, bigint, text, text, jsonb);
drop function if exists "api"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
drop function if exists "api"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);
drop function if exists "api"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
drop function if exists "api"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text, jsonb);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."attachment_schema_error"(fields jsonb)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."attachment_schema_error"($1) $$;
revoke execute on function "api"."attachment_schema_error"(jsonb) from public, anon;
grant execute on function "api"."attachment_schema_error"(jsonb) to authenticated, service_role;

create or replace function "api"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."attachment_fields_error"($1, $2) $$;
revoke execute on function "api"."attachment_fields_error"(jsonb, jsonb) from public, anon;
grant execute on function "api"."attachment_fields_error"(jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."define_attachment_document_type"(tenant uuid, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."define_attachment_document_type"($1, $2, $3, $4) $$;
revoke execute on function "api"."define_attachment_document_type"(uuid, text, text, jsonb) from public, anon;
grant execute on function "api"."define_attachment_document_type"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_attachment_document_types"($1) $$;
revoke execute on function "api"."list_attachment_document_types"(uuid) from public, anon;
grant execute on function "api"."list_attachment_document_types"(uuid) to authenticated, service_role;

create or replace function "api"."delete_attachment_document_type"(tenant uuid, key text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_attachment_document_type"($1, $2) $$;
revoke execute on function "api"."delete_attachment_document_type"(uuid, text) from public, anon;
grant execute on function "api"."delete_attachment_document_type"(uuid, text) to authenticated, service_role;

create or replace function "api"."claim_attachment_upload"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_attachment_upload"($1) $$;
revoke execute on function "api"."claim_attachment_upload"(uuid) from public, anon;
grant execute on function "api"."claim_attachment_upload"(uuid) to authenticated, service_role;

create or replace function "api"."mark_attachment_missing"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_attachment_missing"($1) $$;
revoke execute on function "api"."mark_attachment_missing"(uuid) from public, anon;
grant execute on function "api"."mark_attachment_missing"(uuid) to authenticated, service_role;

create or replace function "api"."replace_attachment"(id uuid, name text, mime_type text, size bigint, width integer default null, height integer default null, pages integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."replace_attachment"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) from public, anon;
grant execute on function "api"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;

create or replace function "api"."restore_attachment_version"(id uuid, version integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."restore_attachment_version"($1, $2) $$;
revoke execute on function "api"."restore_attachment_version"(uuid, integer) from public, anon;
grant execute on function "api"."restore_attachment_version"(uuid, integer) to authenticated, service_role;

create or replace function "api"."list_attachment_versions"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_attachment_versions"($1) $$;
revoke execute on function "api"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "api"."list_attachment_versions"(uuid) to authenticated, service_role;

create or replace function "api"."object_scan"(bucket text, path text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."object_scan"($1, $2) $$;
revoke execute on function "api"."object_scan"(text, text) from public, anon, authenticated;
grant execute on function "api"."object_scan"(text, text) to service_role;

create or replace function "api"."set_object_scan"(bucket text, path text, status text, detail text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_object_scan"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."set_object_scan"(text, text, text, text) to service_role;

create or replace function "api"."create_attachment"(tenant uuid, name text, mime_type text, size bigint, subject_type text default null, subject_id text default null, metadata jsonb default null, width integer default null, height integer default null, pages integer default null, document_type text default null, source text default null, external_id text default null, source_path text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_attachment"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) $$;
revoke execute on function "api"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) from public, anon;
grant execute on function "api"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) to authenticated, service_role;

create or replace function "api"."confirm_attachment"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."confirm_attachment"($1) $$;
revoke execute on function "api"."confirm_attachment"(uuid) from public, anon;
grant execute on function "api"."confirm_attachment"(uuid) to authenticated, service_role;

create or replace function "api"."set_attachment_status"(id uuid, status text, detail text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_attachment_status"($1, $2, $3) $$;
revoke execute on function "api"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."set_attachment_status"(uuid, text, text) to service_role;

create or replace function "api"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_attachments"($1, $2, $3) $$;
revoke execute on function "api"."list_attachments"(uuid, text, text) from public, anon;
grant execute on function "api"."list_attachments"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."get_attachment"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_attachment"($1) $$;
revoke execute on function "api"."get_attachment"(uuid) from public, anon;
grant execute on function "api"."get_attachment"(uuid) to authenticated, service_role;

create or replace function "api"."delete_attachment"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_attachment"($1) $$;
revoke execute on function "api"."delete_attachment"(uuid) from public, anon;
grant execute on function "api"."delete_attachment"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:dcd894555c7feed8442fdb2537836d5a60799ce09a4a91b898f5c7583445388c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block attachments@8 managed
-- @bsb-hash sha256:a0da439a31c8738a1cf449aaf7b053167aadb92c743dab3ad19e350c88976a61
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types text, number, amount, date, expiry, boolean, select.
-- better_supabase.attachment_document_types is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."attachment_document_types" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."attachment_document_types" add column if not exists "organization_id" uuid;
alter table "better_supabase"."attachment_document_types" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$');
alter table "better_supabase"."attachment_document_types" add column if not exists "name" text check (length(btrim("name")) between 1 and 200);
alter table "better_supabase"."attachment_document_types" add column if not exists "fields" jsonb not null default '{}'::jsonb check (jsonb_typeof("fields") = 'object');
alter table "better_supabase"."attachment_document_types" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."attachment_document_types" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_attachment_document_types_key" on "better_supabase"."attachment_document_types" ("organization_id", "key");
alter table "better_supabase"."attachment_document_types" enable row level security;
grant select on "better_supabase"."attachment_document_types" to authenticated;
grant all on "better_supabase"."attachment_document_types" to service_role;
drop policy if exists bsb_attachment_document_types_select on "better_supabase"."attachment_document_types";
create policy bsb_attachment_document_types_select on "better_supabase"."attachment_document_types"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')));

-- The reason a document type's field schema is invalid, or null.
create or replace function "better_supabase"."attachment_schema_error"(fields jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in ('text', 'number', 'amount', 'date', 'expiry', 'boolean', 'select') then
      return v_key || ' needs one of the types text, number, amount, date, expiry, boolean, select';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$$;

-- The reason a record's metadata doesn't match a document type's fields, or
-- null. A key the type doesn't declare is left alone.
create or replace function "better_supabase"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachment_schema_error"(jsonb) from public, anon;
revoke execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."attachment_schema_error"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) to authenticated, service_role;

-- Creates or changes the document type with key in an organization.
create or replace function "better_supabase"."define_attachment_document_type"(tenant uuid, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachment_document_types";
  v_error text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', define_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  v_error := "better_supabase"."attachment_schema_error"(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_SCHEMA_INVALID';
  end if;
  insert into "better_supabase"."attachment_document_types" as t ("organization_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("organization_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function "better_supabase"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "better_supabase"."attachment_document_types" t
  where t."organization_id" = list_attachment_document_types.tenant
$$;

-- Deletes a document type that no attachment uses.
create or replace function "better_supabase"."delete_attachment_document_type"(tenant uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', delete_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."attachment_document_types" t
  where t."organization_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  raise exception 'attachments still use this document type' using errcode = '23503', hint = 'ATTACHMENT_DOCUMENT_TYPE_IN_USE';
end;
$$;
revoke execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."list_attachment_document_types"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) from public, anon;
grant execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_document_types"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) to authenticated, service_role;

-- better_supabase.attachments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."attachments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."attachments" add column if not exists "organization_id" uuid;
alter table "better_supabase"."attachments" add column if not exists "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."attachments" add column if not exists "subject_id" text check (length("subject_id") between 1 and 200);
alter table "better_supabase"."attachments" add column if not exists "bucket" text not null default 'attachments';
alter table "better_supabase"."attachments" add column if not exists "object_path" text;
alter table "better_supabase"."attachments" add column if not exists "name" text check (length("name") between 1 and 255);
alter table "better_supabase"."attachments" add column if not exists "mime_type" text check ("mime_type" ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$');
alter table "better_supabase"."attachments" add column if not exists "size" bigint;
alter table "better_supabase"."attachments" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'clean', 'infected', 'failed'));
alter table "better_supabase"."attachments" add column if not exists "scan_detail" text;
alter table "better_supabase"."attachments" add column if not exists "uploaded_by" uuid references auth.users (id) on delete set null default auth.uid();
alter table "better_supabase"."attachments" add column if not exists "created_at" timestamptz not null default clock_timestamp();
alter table "better_supabase"."attachments" add column if not exists "uploaded_at" timestamptz;
alter table "better_supabase"."attachments" add column if not exists "scanned_at" timestamptz;
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table "better_supabase"."attachments" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "better_supabase"."attachments" add column if not exists "width" integer check ("width" > 0);
alter table "better_supabase"."attachments" add column if not exists "height" integer check ("height" > 0);
alter table "better_supabase"."attachments" add column if not exists "pages" integer check ("pages" > 0);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "better_supabase"."attachments" add column if not exists "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object');
-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
create unique index if not exists attachments_object_idx on "better_supabase"."attachments" ("bucket", "object_path");
create index if not exists attachments_subject_idx on "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id");
create index if not exists attachments_uploaded_by_idx on "better_supabase"."attachments" ("uploaded_by");
alter table "better_supabase"."attachments" enable row level security;
grant select, delete on "better_supabase"."attachments" to authenticated;
grant insert ("organization_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata", "width", "height", "pages") on "better_supabase"."attachments" to authenticated;
grant all on "better_supabase"."attachments" to service_role;
create or replace function "better_supabase"."attachment_insert_defaults"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    new."status" := 'pending';
    new."uploaded_by" := auth.uid();
    new."uploaded_at" := null;
    new."version" := 1;
    new."scan_detail" := null;
    new."scanned_at" := null;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_insert_defaults"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_insert_defaults on "better_supabase"."attachments";
create trigger bsb_attachments_insert_defaults
  before insert on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_insert_defaults"();
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with on, an unlisted type fails.
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

drop policy if exists bsb_attachments_select on "better_supabase"."attachments";
create policy bsb_attachments_select on "better_supabase"."attachments"
  for select to authenticated
  using ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"));
drop policy if exists bsb_attachments_insert on "better_supabase"."attachments";
create policy bsb_attachments_insert on "better_supabase"."attachments"
  for insert to authenticated
  with check (("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id")) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_attachments_delete on "better_supabase"."attachments";
create policy bsb_attachments_delete on "better_supabase"."attachments"
  for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

-- Tells the tenant's topic which subject's files changed. The payload carries
-- ids only; files without a tenant broadcast nothing.
create or replace function "better_supabase"."attachments_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."organization_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."organization_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_attachments_changed" on "better_supabase"."attachments";
create trigger "bsb_attachments_changed"
  after insert or update or delete on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachments_changed"();

-- Members join attachments:{tenant}; payloads name the subject whose files changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_attachments_receive on realtime.messages;
create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));
  end if;
end;
$do$;

-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
-- better_supabase.attachment_versions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."attachment_versions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."attachment_versions" add column if not exists "organization_id" uuid;
alter table "better_supabase"."attachment_versions" add column if not exists "attachment_id" uuid references "better_supabase"."attachments" ("id") on delete cascade;
alter table "better_supabase"."attachment_versions" add column if not exists "version" integer check ("version" >= 1);
alter table "better_supabase"."attachment_versions" add column if not exists "bucket" text;
alter table "better_supabase"."attachment_versions" add column if not exists "object_path" text;
alter table "better_supabase"."attachment_versions" add column if not exists "name" text;
alter table "better_supabase"."attachment_versions" add column if not exists "mime_type" text;
alter table "better_supabase"."attachment_versions" add column if not exists "size" bigint;
alter table "better_supabase"."attachment_versions" add column if not exists "width" integer;
alter table "better_supabase"."attachment_versions" add column if not exists "height" integer;
alter table "better_supabase"."attachment_versions" add column if not exists "pages" integer;
alter table "better_supabase"."attachment_versions" add column if not exists "status" text check ("status" in ('pending', 'clean', 'infected', 'failed'));
alter table "better_supabase"."attachment_versions" add column if not exists "scan_detail" text;
alter table "better_supabase"."attachment_versions" add column if not exists "uploaded_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."attachment_versions" add column if not exists "uploaded_at" timestamptz;
alter table "better_supabase"."attachment_versions" add column if not exists "scanned_at" timestamptz;
alter table "better_supabase"."attachment_versions" add column if not exists "archived_at" timestamptz not null default now();
create index if not exists attachment_versions_uploaded_by_idx on "better_supabase"."attachment_versions" ("uploaded_by");
alter table "better_supabase"."attachment_versions" enable row level security;
grant select on "better_supabase"."attachment_versions" to authenticated;
grant all on "better_supabase"."attachment_versions" to service_role;
drop policy if exists bsb_attachment_versions_select on "better_supabase"."attachment_versions";
create policy bsb_attachment_versions_select on "better_supabase"."attachment_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a clean file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists "bsb_attachments_insert" on storage.objects;
drop policy if exists "bsb_attachments_select" on storage.objects;
drop policy if exists "bsb_attachments_delete" on storage.objects;
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
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = any (array[attachment_object_allowed.path, regexp_replace(attachment_object_allowed.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    join "better_supabase"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" = 'clean' and coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.read'), false))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'attachments.manage'), false)
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
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = any (array[attachment_object_visible.path, regexp_replace(attachment_object_visible.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_visible.path
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    where v."bucket" = attachment_object_visible.bucket and v."object_path" = attachment_object_visible.path
  )
$$;
revoke execute on function "better_supabase"."attachment_object_visible"(text, text) from public, anon;
grant execute on function "better_supabase"."attachment_object_visible"(text, text) to authenticated, service_role;

drop trigger if exists "bsb_attachments_object_uploaded" on storage.objects;
drop trigger if exists "bsb_attachments_object_removed" on storage.objects;
drop trigger if exists "bsb_attachments_queue_cleanup" on "better_supabase"."attachments";

create policy bsb_attachments_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_select on storage.objects
  for select to authenticated
  using (bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'select'));
create policy bsb_attachments_delete on storage.objects
  for delete to authenticated
  using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
create or replace function "better_supabase"."create_attachment"(
  tenant uuid,
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into "better_supabase"."attachments" as x ("organization_id", "bucket", "name", "mime_type", "size", "subject_type", "subject_id", "metadata", "width", "height", "pages")
  values (create_attachment.tenant, 'attachments', create_attachment.name, lower(create_attachment.mime_type), create_attachment.size, create_attachment.subject_type, create_attachment.subject_id, coalesce(create_attachment.metadata, '{}'), create_attachment.width, create_attachment.height, create_attachment.pages)
  returning jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'bucket', x."bucket", 'object_path', (case when x."version" > 1 then x."object_path" || '-v' || x."version"::text else x."object_path" end), 'name', x."name", 'mime_type', x."mime_type", 'size', x."size", 'status', x."status", 'scan_detail', x."scan_detail", 'uploaded_by', x."uploaded_by", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'scanned_at', x."scanned_at", 'metadata', x."metadata", 'version', x."version", 'width', x."width", 'height', x."height", 'pages', x."pages", 'document_type_id', x."document_type_id", 'source', x."source", 'external_id', x."external_id", 'storage_status', x."storage_status", 'source_path', x."source_path")
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
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'bucket', v_row."bucket", 'object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), 'name', v_row."name", 'mime_type', v_row."mime_type", 'size', v_row."size", 'status', v_row."status", 'scan_detail', v_row."scan_detail", 'uploaded_by', v_row."uploaded_by", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'scanned_at', v_row."scanned_at", 'metadata', v_row."metadata", 'version', v_row."version", 'width', v_row."width", 'height', v_row."height", 'pages', v_row."pages", 'document_type_id', v_row."document_type_id", 'source', v_row."source", 'external_id', v_row."external_id", 'storage_status', v_row."storage_status", 'source_path', v_row."source_path");
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
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
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'bucket', v_row."bucket", 'object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), 'name', v_row."name", 'mime_type', v_row."mime_type", 'size', v_row."size", 'status', v_row."status", 'scan_detail', v_row."scan_detail", 'uploaded_by', v_row."uploaded_by", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'scanned_at', v_row."scanned_at", 'metadata', v_row."metadata", 'version', v_row."version", 'width', v_row."width", 'height', v_row."height", 'pages', v_row."pages", 'document_type_id', v_row."document_type_id", 'source', v_row."source", 'external_id', v_row."external_id", 'storage_status', v_row."storage_status", 'source_path', v_row."source_path");
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
    "status" = better_supabase.as_column_type(set_attachment_status.status, (null::"better_supabase"."attachments")."status"),
    "scan_detail" = set_attachment_status.detail,
    "scanned_at" = now()
  where a."id" = set_attachment_status.id
    and a."uploaded_at" is not null
    and a."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."attachments" a where a."id" = set_attachment_status.id;
    return case when v_row."id" is null then null else jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'bucket', v_row."bucket", 'object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), 'name', v_row."name", 'mime_type', v_row."mime_type", 'size', v_row."size", 'status', v_row."status", 'scan_detail', v_row."scan_detail", 'uploaded_by', v_row."uploaded_by", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'scanned_at', v_row."scanned_at", 'metadata', v_row."metadata", 'version', v_row."version", 'width', v_row."width", 'height', v_row."height", 'pages', v_row."pages", 'document_type_id', v_row."document_type_id", 'source', v_row."source", 'external_id', v_row."external_id", 'storage_status', v_row."storage_status", 'source_path', v_row."source_path") end;
  end if;
  insert into "better_supabase"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), better_supabase.as_column_type(v_row."status"::text, (null::"better_supabase"."scanned_objects")."status"), v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'bucket', v_row."bucket", 'object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), 'name', v_row."name", 'mime_type', v_row."mime_type", 'size', v_row."size", 'status', v_row."status", 'scan_detail', v_row."scan_detail", 'uploaded_by', v_row."uploaded_by", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'scanned_at', v_row."scanned_at", 'metadata', v_row."metadata", 'version', v_row."version", 'width', v_row."width", 'height', v_row."height", 'pages', v_row."pages", 'document_type_id', v_row."document_type_id", 'source', v_row."source", 'external_id', v_row."external_id", 'storage_status', v_row."storage_status", 'source_path', v_row."source_path");
end;
$$;

create or replace function "better_supabase"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."organization_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', a."id", 'organization_id', a."organization_id", 'subject_type', a."subject_type", 'subject_id', a."subject_id", 'bucket', a."bucket", 'object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end), 'name', a."name", 'mime_type', a."mime_type", 'size', a."size", 'status', a."status", 'scan_detail', a."scan_detail", 'uploaded_by', a."uploaded_by", 'created_at', a."created_at", 'uploaded_at', a."uploaded_at", 'scanned_at', a."scanned_at", 'metadata', a."metadata", 'version', a."version", 'width', a."width", 'height', a."height", 'pages', a."pages", 'document_type_id', a."document_type_id", 'source', a."source", 'external_id', a."external_id", 'storage_status', a."storage_status", 'source_path', a."source_path") order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a;
  return v_files;
end;
$$;

create or replace function "better_supabase"."get_attachment"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', a."id", 'organization_id', a."organization_id", 'subject_type', a."subject_type", 'subject_id', a."subject_id", 'bucket', a."bucket", 'object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end), 'name', a."name", 'mime_type', a."mime_type", 'size', a."size", 'status', a."status", 'scan_detail', a."scan_detail", 'uploaded_by', a."uploaded_by", 'created_at', a."created_at", 'uploaded_at', a."uploaded_at", 'scanned_at', a."scanned_at", 'metadata', a."metadata", 'version', a."version", 'width', a."width", 'height', a."height", 'pages', a."pages", 'document_type_id', a."document_type_id", 'source', a."source", 'external_id', a."external_id", 'storage_status', a."storage_status", 'source_path', a."source_path") from "better_supabase"."attachments" a where a."id" = get_attachment.id
$$;


-- Starts a new version of a file: the current one, once uploaded, moves to
-- attachment_versions, and the caller uploads the new file to the returned
-- object_path and confirms it, which scans it again. A file whose upload
-- never finished is replaced in place.
create or replace function "better_supabase"."replace_attachment"(
  id uuid,
  name text,
  mime_type text,
  size bigint,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_next integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = replace_attachment.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", better_supabase.as_column_type(v_row."status"::text, (null::"better_supabase"."attachment_versions")."status"), v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  select greatest(v_row."version" - case when v_row."uploaded_at" is null then 1 else 0 end, coalesce(max(v."version"), 0)) + 1
  into v_next
  from "better_supabase"."attachment_versions" v where v."attachment_id" = v_row."id";
  update "better_supabase"."attachments" a set
    "version" = v_next,
    "name" = replace_attachment.name,
    "mime_type" = lower(replace_attachment.mime_type),
    "size" = replace_attachment.size,
    "width" = replace_attachment.width,
    "height" = replace_attachment.height,
    "pages" = replace_attachment.pages,
    "status" = 'pending',
    "scan_detail" = null,
    "uploaded_by" = coalesce(auth.uid(), a."uploaded_by"),
    "uploaded_at" = null,
    "scanned_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'bucket', v_row."bucket", 'object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), 'name', v_row."name", 'mime_type', v_row."mime_type", 'size', v_row."size", 'status', v_row."status", 'scan_detail', v_row."scan_detail", 'uploaded_by', v_row."uploaded_by", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'scanned_at', v_row."scanned_at", 'metadata', v_row."metadata", 'version', v_row."version", 'width', v_row."width", 'height', v_row."height", 'pages', v_row."pages", 'document_type_id', v_row."document_type_id", 'source', v_row."source", 'external_id', v_row."external_id", 'storage_status', v_row."storage_status", 'source_path', v_row."source_path");
end;
$$;

-- Makes an earlier version current again; the current one, once uploaded,
-- becomes an earlier version. No object moves.
create or replace function "better_supabase"."restore_attachment_version"(id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_old "better_supabase"."attachment_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = restore_attachment_version.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may restore has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."attachment_versions" v
  where v."attachment_id" = v_row."id" and v."version" = restore_attachment_version.version
  for update;
  if v_old."id" is null then
    raise exception 'The file has no earlier version with this number' using errcode = 'P0002', hint = 'ATTACHMENT_VERSION_NOT_FOUND';
  end if;
  delete from "better_supabase"."attachment_versions" v where v."id" = v_old."id";
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("organization_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."organization_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", better_supabase.as_column_type(v_row."status"::text, (null::"better_supabase"."attachment_versions")."status"), v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  update "better_supabase"."attachments" a set
    "version" = v_old."version",
    "name" = v_old."name",
    "mime_type" = v_old."mime_type",
    "size" = v_old."size",
    "width" = v_old."width",
    "height" = v_old."height",
    "pages" = v_old."pages",
    "status" = better_supabase.as_column_type(v_old."status"::text, (null::"better_supabase"."attachments")."status"),
    "scan_detail" = v_old."scan_detail",
    "uploaded_by" = v_old."uploaded_by",
    "uploaded_at" = v_old."uploaded_at",
    "scanned_at" = v_old."scanned_at"
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'bucket', v_row."bucket", 'object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), 'name', v_row."name", 'mime_type', v_row."mime_type", 'size', v_row."size", 'status', v_row."status", 'scan_detail', v_row."scan_detail", 'uploaded_by', v_row."uploaded_by", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'scanned_at', v_row."scanned_at", 'metadata', v_row."metadata", 'version', v_row."version", 'width', v_row."width", 'height', v_row."height", 'pages', v_row."pages", 'document_type_id', v_row."document_type_id", 'source', v_row."source", 'external_id', v_row."external_id", 'storage_status', v_row."storage_status", 'source_path', v_row."source_path");
end;
$$;

-- A file's earlier versions, newest first.
create or replace function "better_supabase"."list_attachment_versions"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'organization_id', v."organization_id", 'attachment_id', v."attachment_id", 'version', v."version", 'bucket', v."bucket", 'object_path', v."object_path", 'name', v."name", 'mime_type', v."mime_type", 'size', v."size", 'width', v."width", 'height', v."height", 'pages', v."pages", 'status', v."status", 'scan_detail', v."scan_detail", 'uploaded_by', v."uploaded_by", 'uploaded_at', v."uploaded_at", 'scanned_at', v."scanned_at", 'archived_at', v."archived_at") order by v."version" desc), '[]'::jsonb)
  from "better_supabase"."attachment_versions" v where v."attachment_id" = list_attachment_versions.id
$$;
revoke execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) from public, anon;
revoke execute on function "better_supabase"."restore_attachment_version"(uuid, integer) from public, anon;
revoke execute on function "better_supabase"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;
grant execute on function "better_supabase"."restore_attachment_version"(uuid, integer) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_versions"(uuid) to authenticated, service_role;

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
-- better_supabase.scanned_objects is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."scanned_objects" add column if not exists "bucket" text;
alter table "better_supabase"."scanned_objects" add column if not exists "object_path" text;
alter table "better_supabase"."scanned_objects" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'clean', 'infected', 'failed'));
alter table "better_supabase"."scanned_objects" add column if not exists "scan_detail" text;
alter table "better_supabase"."scanned_objects" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."scanned_objects" add column if not exists "scanned_at" timestamptz;
create unique index if not exists "bsb_scanned_objects_object_key" on "better_supabase"."scanned_objects" ("bucket", "object_path");
alter table "better_supabase"."scanned_objects" enable row level security;
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
  select jsonb_build_object('bucket', s."bucket", 'object_path', s."object_path", 'status', s."status", 'scan_detail', s."scan_detail", 'created_at', s."created_at", 'scanned_at', s."scanned_at") from "better_supabase"."scanned_objects" s
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
  values (set_object_scan.bucket, set_object_scan.path, better_supabase.as_column_type(set_object_scan.status, (null::"better_supabase"."scanned_objects")."status"), set_object_scan.detail,
    case when set_object_scan.status = 'pending' then null else now() end)
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at"
    where s."status" in ('pending', 'failed')
  returning * into v_row;
  if v_row."bucket" is null then
    select * into v_row from "better_supabase"."scanned_objects" s where s."bucket" = set_object_scan.bucket and s."object_path" = set_object_scan.path;
  end if;
  return jsonb_build_object('bucket', v_row."bucket", 'object_path', v_row."object_path", 'status', v_row."status", 'scan_detail', v_row."scan_detail", 'created_at', v_row."created_at", 'scanned_at', v_row."scanned_at");
end;
$$;
drop trigger if exists bsb_object_scan_pending on storage.objects;

revoke execute on function "better_supabase"."object_clean"(text, text) from public, anon;
revoke execute on function "better_supabase"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "better_supabase"."object_scan"(text, text) to service_role;
grant execute on function "better_supabase"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer) from public, anon;
revoke execute on function "better_supabase"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "better_supabase"."get_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment"(uuid) from public, anon;
grant execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer) to authenticated, service_role;
grant execute on function "better_supabase"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_attachment_status"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
create policy bsb_tenant_scope_select on "better_supabase"."attachments" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
create policy bsb_tenant_scope_insert on "better_supabase"."attachments" as restrictive
  for insert to public
  with check (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "organization_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "organization_id"))
  );
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
create policy bsb_tenant_scope_update on "better_supabase"."attachments" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
create policy bsb_tenant_scope_delete on "better_supabase"."attachments" as restrictive
  for delete to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('attachments.manage')))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_document_types" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select better_supabase.tenant_ids_with('attachments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_document_types" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_document_types" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_document_types" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_versions" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_versions" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_versions" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_versions" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:dcd894555c7feed8442fdb2537836d5a60799ce09a4a91b898f5c7583445388c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block attachments@8 managed
-- @bsb-hash sha256:9cd9854ffd08b6970e0b73a570c401a095d38571bf8b343b5bd79bfc1c4e98bf
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
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
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types text, number, amount, date, expiry, boolean, select.
create table if not exists "better_supabase"."attachment_document_types" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  "name" text not null check (length(btrim("name")) between 1 and 200),
  "fields" jsonb not null default '{}'::jsonb check (jsonb_typeof("fields") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key")
);
alter table "better_supabase"."attachment_document_types" enable row level security;
revoke all on "better_supabase"."attachment_document_types" from public, anon, authenticated;
grant select on "better_supabase"."attachment_document_types" to authenticated;
grant all on "better_supabase"."attachment_document_types" to service_role;
drop policy if exists attachment_document_types_read on "better_supabase"."attachment_document_types";
create policy attachment_document_types_read on "better_supabase"."attachment_document_types"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('attachments.read')));

-- The reason a document type's field schema is invalid, or null.
create or replace function "better_supabase"."attachment_schema_error"(fields jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_def jsonb;
  v_type text;
begin
  if jsonb_typeof(attachment_schema_error.fields) is distinct from 'object' then
    return 'fields must be an object keyed by field key';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_schema_error.fields) f order by f.key loop
    if v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      return 'field key ' || v_key || ' must be lower case letters, digits and underscores';
    end if;
    if jsonb_typeof(v_def) is distinct from 'object' then
      return v_key || ' must be an object with a type';
    end if;
    v_type := v_def ->> 'type';
    if v_type is null or v_type not in ('text', 'number', 'amount', 'date', 'expiry', 'boolean', 'select') then
      return v_key || ' needs one of the types text, number, amount, date, expiry, boolean, select';
    end if;
    if v_def ? 'required' and jsonb_typeof(v_def -> 'required') <> 'boolean' then
      return v_key || ': required must be a boolean';
    end if;
    if v_type = 'select' and (jsonb_typeof(v_def -> 'options') is distinct from 'array' or jsonb_array_length(v_def -> 'options') = 0
      or exists (select 1 from jsonb_array_elements(v_def -> 'options') o where jsonb_typeof(o.value) <> 'string')) then
      return v_key || ': a select field needs a list of text options';
    end if;
  end loop;
  return null;
end;
$$;

-- The reason a record's metadata doesn't match a document type's fields, or
-- null. A key the type doesn't declare is left alone.
create or replace function "better_supabase"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(attachment_fields_error.data, '{}'::jsonb);
  v_key text;
  v_def jsonb;
  v_value jsonb;
  v_type text;
  v_date date;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    return 'metadata must be an object';
  end if;
  for v_key, v_def in select f.key, f.value from jsonb_each(attachment_fields_error.fields) f order by f.key loop
    v_value := v_data -> v_key;
    v_type := v_def ->> 'type';
    if v_value is null or jsonb_typeof(v_value) = 'null' then
      if coalesce((v_def ->> 'required')::boolean, false) then
        return v_key || ' is required';
      end if;
      continue;
    end if;
    if v_type = 'text' then
      if jsonb_typeof(v_value) <> 'string' then
        return v_key || ' must be text';
      end if;
    elsif v_type = 'number' then
      if jsonb_typeof(v_value) <> 'number' then
        return v_key || ' must be a number';
      end if;
    elsif v_type = 'boolean' then
      if jsonb_typeof(v_value) <> 'boolean' then
        return v_key || ' must be true or false';
      end if;
    elsif v_type in ('date', 'expiry') then
      if jsonb_typeof(v_value) <> 'string' or (v_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        return v_key || ' must be a date as YYYY-MM-DD';
      end if;
      begin
        v_date := (v_value #>> '{}')::date;
      exception when others then
        return v_key || ' must be a real date';
      end;
      if to_char(v_date, 'YYYY-MM-DD') <> (v_value #>> '{}') then
        return v_key || ' must be a real date';
      end if;
    elsif v_type = 'amount' then
      if jsonb_typeof(v_value) <> 'object'
        or jsonb_typeof(v_value -> 'amount') not in ('string', 'number')
        or (v_value ->> 'amount') !~ '^-?[0-9]{1,18}$'
        or coalesce(v_value ->> 'currency', '') !~ '^[A-Z]{3}$' then
        return v_key || ' must be { amount: minor units as an integer, currency: ISO code }';
      end if;
    elsif v_type = 'select' then
      if jsonb_typeof(v_value) <> 'string' or not (v_def -> 'options') @> jsonb_build_array(v_value) then
        return v_key || ' must be one of its options';
      end if;
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachment_schema_error"(jsonb) from public, anon;
revoke execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."attachment_schema_error"(jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."attachment_fields_error"(jsonb, jsonb) to authenticated, service_role;

-- Creates or changes the document type with key in an organization.
create or replace function "better_supabase"."define_attachment_document_type"(tenant uuid, key text, name text, fields jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachment_document_types";
  v_error text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', define_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  v_error := "better_supabase"."attachment_schema_error"(coalesce(define_attachment_document_type.fields, '{}'::jsonb));
  if v_error is not null then
    raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_SCHEMA_INVALID';
  end if;
  insert into "better_supabase"."attachment_document_types" as t ("org_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("org_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function "better_supabase"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "better_supabase"."attachment_document_types" t
  where t."org_id" = list_attachment_document_types.tenant
$$;

-- Deletes a document type that no attachment uses.
create or replace function "better_supabase"."delete_attachment_document_type"(tenant uuid, key text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', delete_attachment_document_type.tenant, 'attachments.manage'), false)) then
    raise exception 'not allowed to manage document types' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."attachment_document_types" t
  where t."org_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
  return found;
exception when foreign_key_violation then
  raise exception 'attachments still use this document type' using errcode = '23503', hint = 'ATTACHMENT_DOCUMENT_TYPE_IN_USE';
end;
$$;
revoke execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) from public, anon;
revoke execute on function "better_supabase"."list_attachment_document_types"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) from public, anon;
grant execute on function "better_supabase"."define_attachment_document_type"(uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_document_types"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment_document_type"(uuid, text) to authenticated, service_role;

create table if not exists "better_supabase"."attachments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text check (length("subject_id") between 1 and 200),
  "bucket" text not null default 'attachments',
  "object_path" text,
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
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table "better_supabase"."attachments" add column if not exists "version" integer not null default 1 check ("version" >= 1);
alter table "better_supabase"."attachments" add column if not exists "width" integer check ("width" > 0);
alter table "better_supabase"."attachments" add column if not exists "height" integer check ("height" > 0);
alter table "better_supabase"."attachments" add column if not exists "pages" integer check ("pages" > 0);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "better_supabase"."attachments" add column if not exists "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object');
-- Where a record came from and what it is (ADR 0157). storage_status follows
-- the upload: stored once uploaded_at is set, pending_upload until then, and
-- missing for a record whose file never arrived.
alter table "better_supabase"."attachments" add column if not exists "document_type_id" uuid references "better_supabase"."attachment_document_types" ("id") on delete restrict;
alter table "better_supabase"."attachments" add column if not exists "source" text check (length("source") between 1 and 200);
alter table "better_supabase"."attachments" add column if not exists "external_id" text check (length("external_id") between 1 and 500);
alter table "better_supabase"."attachments" add column if not exists "storage_status" text not null default 'pending_upload' check ("storage_status" in ('stored', 'pending_upload', 'missing'));
alter table "better_supabase"."attachments" add column if not exists "source_path" text check (length("source_path") between 1 and 2000);
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_external'
  ), 'pg_constraint'), '') <> 'better-supabase check 9237e50d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_external";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_external" check (("source" is null) = ("external_id" is null));
    comment on constraint "bsb_attachments_external" on "better_supabase"."attachments" is 'better-supabase check 9237e50d';
  end if;
end;
$$;
create unique index if not exists attachments_external_idx on "better_supabase"."attachments" ("org_id", "source", "external_id") where "source" is not null;
create index if not exists attachments_document_type_idx on "better_supabase"."attachments" ("document_type_id") where "document_type_id" is not null;
do $$
begin
  update "better_supabase"."attachments" set "storage_status" = 'stored' where "uploaded_at" is not null and "storage_status" = 'pending_upload';
end;
$$;

-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- "object_path" is a plain column a trigger fills: logical replication (PowerSync)
-- skips generated columns. An install from before keeps its values when the
-- expression is dropped.
do $$
begin
  if exists (
    select 1 from pg_attribute
    where attrelid = 'better_supabase.attachments'::regclass
      and attname = 'object_path' and attgenerated <> ''
  ) then
    alter table "better_supabase"."attachments" alter column "object_path" drop expression;
  end if;
end;
$$;
create or replace function "better_supabase"."attachment_object_path"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select "org_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_object_path"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_object_path on "better_supabase"."attachments";
create trigger bsb_attachments_object_path
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_object_path"();
-- options.path: the column comment records the template the path was built
-- from, so a changed template rewrites every row's path.
do $$
declare
  v_current text := coalesce(
    col_description('better_supabase.attachments'::regclass,
      (select attnum from pg_attribute where attrelid = 'better_supabase.attachments'::regclass and attname = 'object_path')::integer),
    'better-supabase path: {organization_id}/attachments/{id}');
begin
  if v_current is distinct from 'better-supabase path: {organization_id}/attachments/{id}' then
    update "better_supabase"."attachments" set "object_path" = null;
  end if;
end;
$$;
comment on column "better_supabase"."attachments"."object_path" is 'better-supabase path: {organization_id}/attachments/{id}';
alter table "better_supabase"."attachments" alter column "bucket" set default 'attachments';
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_bucket'
  ), 'pg_constraint'), '') <> 'better-supabase check 06ecf11d' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_bucket";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_bucket" check ("bucket" in ('attachments')) not valid;
    comment on constraint "bsb_attachments_bucket" on "better_supabase"."attachments" is 'better-supabase check 06ecf11d';
  end if;
end;
$$;
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."attachments"'::regclass and c.conname = 'bsb_attachments_size'
  ), 'pg_constraint'), '') <> 'better-supabase check 65b1c9ef' then
    alter table "better_supabase"."attachments" drop constraint if exists "bsb_attachments_size";
    alter table "better_supabase"."attachments" add constraint "bsb_attachments_size" check ("size" between 0 and 52428800);
    comment on constraint "bsb_attachments_size" on "better_supabase"."attachments" is 'better-supabase check 65b1c9ef';
  end if;
end;
$$;
alter table "better_supabase"."attachments" drop constraint if exists bsb_attachments_mime_type;
create unique index if not exists attachments_object_idx on "better_supabase"."attachments" ("bucket", "object_path");
create index if not exists attachments_subject_idx on "better_supabase"."attachments" ("org_id", "subject_type", "subject_id");
create index if not exists attachments_uploaded_by_idx on "better_supabase"."attachments" ("uploaded_by");
create or replace function "better_supabase"."attachment_document_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_types text[];
  v_fields jsonb;
  v_error text;
begin
  if new."storage_status" in ('stored', 'pending_upload') or new."uploaded_at" is not null then
    new."storage_status" := case when new."uploaded_at" is not null then 'stored' else
      case when new."storage_status" = 'missing' then 'missing' else 'pending_upload' end end;
  end if;
  if new."source" is not null and (tg_op = 'INSERT' or new."source" is distinct from old."source" or new."external_id" is distinct from old."external_id") then
    if not (new."source" = any (array[]::text[])) then
      raise exception 'the source is not in options.sources and has no import run' using errcode = '22023', hint = 'ATTACHMENT_SOURCE_UNKNOWN';
    end if;
    if new."org_id" is not null and exists (
      select 1 from "better_supabase"."attachments" x
      where x."org_id" = new."org_id" and x."source" = new."source" and x."external_id" = new."external_id" and x."id" <> new."id"
    ) then
      raise exception 'an attachment of this source already has this external id' using errcode = '23505', hint = 'ATTACHMENT_EXTERNAL_ID_TAKEN';
    end if;
  end if;
  if new."document_type_id" is not null and (tg_op = 'INSERT' or new."document_type_id" is distinct from old."document_type_id" or new."metadata" is distinct from old."metadata") then
    select y."fields" into v_fields from "better_supabase"."attachment_document_types" y
    where y."id" = new."document_type_id" and y."org_id" = new."org_id";
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
    v_error := "better_supabase"."attachment_fields_error"(v_fields, new."metadata");
    if v_error is not null then
      raise exception '%', v_error using errcode = '22023', hint = 'ATTACHMENT_FIELD_INVALID';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_document_guard"() from public, anon, authenticated;
drop trigger if exists bsb_attachments_documents on "better_supabase"."attachments";
create trigger bsb_attachments_documents
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_document_guard"();

alter table "better_supabase"."attachments" enable row level security;
revoke all on "better_supabase"."attachments" from public, anon, authenticated;
grant select, delete on "better_supabase"."attachments" to authenticated;
grant insert ("org_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata", "width", "height", "pages", "document_type_id", "source", "external_id", "source_path") on "better_supabase"."attachments" to authenticated;
grant all on "better_supabase"."attachments" to service_role;
-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission. Files
-- without a subject pass; with on, an unlisted type fails.
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

drop policy if exists attachments_read on "better_supabase"."attachments";
create policy attachments_read on "better_supabase"."attachments"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "org_id"));
drop policy if exists attachments_insert on "better_supabase"."attachments";
create policy attachments_insert on "better_supabase"."attachments"
  for insert to authenticated
  with check (("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "org_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "org_id")) and (select better_supabase.actor_may_write()));
drop policy if exists attachments_delete on "better_supabase"."attachments";
create policy attachments_delete on "better_supabase"."attachments"
  for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

-- Tells the tenant's topic which subject's files changed. The payload carries
-- ids only; files without a tenant broadcast nothing.
create or replace function "better_supabase"."attachments_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments"%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  if v_row."org_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."org_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_attachments_changed" on "better_supabase"."attachments";
create trigger "bsb_attachments_changed"
  after insert or update or delete on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachments_changed"();

-- Members join attachments:{tenant}; payloads name the subject whose files changed.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_attachments_receive on realtime.messages;
create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));
  end if;
end;
$do$;

-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
create table if not exists "better_supabase"."attachment_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "attachment_id" uuid not null references "better_supabase"."attachments" ("id") on delete cascade,
  "version" integer not null check ("version" >= 1),
  "bucket" text not null,
  "object_path" text not null,
  "name" text not null,
  "mime_type" text not null,
  "size" bigint not null,
  "width" integer,
  "height" integer,
  "pages" integer,
  "status" text not null check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null,
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  "archived_at" timestamptz not null default now(),
  unique ("attachment_id", "version"),
  unique ("bucket", "object_path")
);
create index if not exists attachment_versions_uploaded_by_idx on "better_supabase"."attachment_versions" ("uploaded_by");
alter table "better_supabase"."attachment_versions" enable row level security;
revoke all on "better_supabase"."attachment_versions" from public, anon, authenticated;
grant select on "better_supabase"."attachment_versions" to authenticated;
grant all on "better_supabase"."attachment_versions" to service_role;
drop policy if exists attachment_versions_read on "better_supabase"."attachment_versions";
create policy attachment_versions_read on "better_supabase"."attachment_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a clean file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.
drop policy if exists "bsb_attachments_insert" on storage.objects;
drop policy if exists "bsb_attachments_select" on storage.objects;
drop policy if exists "bsb_attachments_delete" on storage.objects;
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
    where a."bucket" = attachment_object_allowed.bucket and a."object_path" = any (array[attachment_object_allowed.path, regexp_replace(attachment_object_allowed.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."uploaded_at" is null and a."uploaded_by" = auth.uid()
        when 'select' then (a."status" = 'clean' and coalesce(better_supabase.can('tenant', a."org_id", 'attachments.read'), false))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."org_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."org_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    join "better_supabase"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" = 'clean' and coalesce(better_supabase.can('tenant', a."org_id", 'attachments.read'), false))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."org_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."org_id", 'attachments.manage'), false)
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
    where a."bucket" = attachment_object_visible.bucket and a."object_path" = any (array[attachment_object_visible.path, regexp_replace(attachment_object_visible.path, '-v[0-9]+$', '')]) and (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end) = attachment_object_visible.path
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    where v."bucket" = attachment_object_visible.bucket and v."object_path" = attachment_object_visible.path
  )
$$;
revoke execute on function "better_supabase"."attachment_object_visible"(text, text) from public, anon;
grant execute on function "better_supabase"."attachment_object_visible"(text, text) to authenticated, service_role;

drop trigger if exists "bsb_attachments_object_uploaded" on storage.objects;
drop trigger if exists "bsb_attachments_object_removed" on storage.objects;
drop trigger if exists "bsb_attachments_queue_cleanup" on "better_supabase"."attachments";

create policy bsb_attachments_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_select on storage.objects
  for select to authenticated
  using (bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'select'));
create policy bsb_attachments_delete on storage.objects
  for delete to authenticated
  using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_attachment"(
  tenant uuid,
  name text,
  mime_type text,
  size bigint,
  subject_type text default null,
  subject_id text default null,
  metadata jsonb default null,
  width integer default null,
  height integer default null,
  pages integer default null,
  document_type text default null,
  source text default null,
  external_id text default null,
  source_path text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row "better_supabase"."attachments";
  v_columns text;
begin
  v_row := jsonb_populate_record(null::"better_supabase"."attachments", (
    select coalesce(jsonb_object_agg(e.field_key, e.field_value), '{}'::jsonb)
    from jsonb_each('{}'::jsonb) as e (field_key, field_value)
    where e.field_key = any (array[]::text[])
  ));
  v_row."org_id" := create_attachment.tenant;
  v_row."bucket" := 'attachments';
  v_row."name" := create_attachment.name;
  v_row."mime_type" := lower(create_attachment.mime_type);
  v_row."size" := create_attachment.size;
  v_row."subject_type" := create_attachment.subject_type;
  v_row."subject_id" := create_attachment.subject_id;
  v_row."metadata" := coalesce(create_attachment.metadata, '{}');
  v_row."width" := create_attachment.width;
  v_row."height" := create_attachment.height;
  v_row."pages" := create_attachment.pages;

  if create_attachment.document_type is not null then
    select y."id" into v_row."document_type_id" from "better_supabase"."attachment_document_types" y
    where y."org_id" = create_attachment.tenant and y."key" = create_attachment.document_type;
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;
  v_row."source" := create_attachment.source;
  v_row."external_id" := create_attachment.external_id;
  v_row."source_path" := create_attachment.source_path;
  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array['"org_id"', '"bucket"', '"name"', '"mime_type"', '"size"', '"subject_type"', '"subject_id"', '"metadata"', '"width"', '"height"', '"pages"', '"document_type_id"', '"source"', '"external_id"', '"source_path"']
    || array(select quote_ident(k) from jsonb_object_keys('{}'::jsonb) as k
      where k = any (array[]::text[]))) as column_name;
  execute format('insert into "better_supabase"."attachments" as x (%1$s) select %1$s from (select ($1).*) r returning x.*', v_columns)
  into v_row
  using v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
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
    return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
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
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;


-- The caller takes the upload of a record whose file hasn't arrived (pending
-- upload or missing): they become its uploader, upload to its object_path and
-- call confirm_attachment. The service role leaves the uploader as it is.
create or replace function "better_supabase"."claim_attachment_upload"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = claim_attachment_upload.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."org_id", 'attachments.upload'), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to upload this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set
    "storage_status" = 'pending_upload',
    "uploaded_by" = case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then a."uploaded_by" else auth.uid() end
  where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Marks a record whose file will not arrive.
create or replace function "better_supabase"."mark_attachment_missing"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = mark_attachment_missing.id for update;
  if v_row."id" is null then
    raise exception 'No attachment has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_row."org_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'not allowed to manage this attachment' using errcode = '42501', hint = 'ATTACHMENT_FORBIDDEN';
  end if;
  if v_row."uploaded_at" is not null or v_row."storage_status" = 'stored' then
    raise exception 'the file is already stored' using errcode = '55000', hint = 'ATTACHMENT_NOT_CLAIMABLE';
  end if;
  update "better_supabase"."attachments" a set "storage_status" = 'missing' where a."id" = v_row."id"
  returning * into v_row;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;
revoke execute on function "better_supabase"."claim_attachment_upload"(uuid) from public, anon;
revoke execute on function "better_supabase"."mark_attachment_missing"(uuid) from public, anon;
grant execute on function "better_supabase"."claim_attachment_upload"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."mark_attachment_missing"(uuid) to authenticated, service_role;

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
    return case when v_row."id" is null then null else (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end))) end;
  end if;
  insert into "better_supabase"."scanned_objects" ("bucket", "object_path", "status", "scan_detail", "scanned_at")
  values (v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."status", v_row."scan_detail", now())
  on conflict ("bucket", "object_path") do update
    set "status" = excluded."status", "scan_detail" = excluded."scan_detail", "scanned_at" = excluded."scanned_at";
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

create or replace function "better_supabase"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."org_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  )
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a;
  return v_files;
end;
$$;

create or replace function "better_supabase"."get_attachment"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) from "better_supabase"."attachments" a where a."id" = get_attachment.id
$$;


-- Starts a new version of a file: the current one, once uploaded, moves to
-- attachment_versions, and the caller uploads the new file to the returned
-- object_path and confirms it, which scans it again. A file whose upload
-- never finished is replaced in place.
create or replace function "better_supabase"."replace_attachment"(
  id uuid,
  name text,
  mime_type text,
  size bigint,
  width integer default null,
  height integer default null,
  pages integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_next integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = replace_attachment.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."org_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."org_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("org_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."org_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  select greatest(v_row."version" - case when v_row."uploaded_at" is null then 1 else 0 end, coalesce(max(v."version"), 0)) + 1
  into v_next
  from "better_supabase"."attachment_versions" v where v."attachment_id" = v_row."id";
  update "better_supabase"."attachments" a set
    "version" = v_next,
    "name" = replace_attachment.name,
    "mime_type" = lower(replace_attachment.mime_type),
    "size" = replace_attachment.size,
    "width" = replace_attachment.width,
    "height" = replace_attachment.height,
    "pages" = replace_attachment.pages,
    "status" = 'pending',
    "scan_detail" = null,
    "uploaded_by" = coalesce(auth.uid(), a."uploaded_by"),
    "uploaded_at" = null,
    "scanned_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- Makes an earlier version current again; the current one, once uploaded,
-- becomes an earlier version. No object moves.
create or replace function "better_supabase"."restore_attachment_version"(id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."attachments";
  v_old "better_supabase"."attachment_versions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = restore_attachment_version.id for update;
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."org_id", 'attachments.upload'), false)) or coalesce(better_supabase.can('tenant', v_row."org_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may restore has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."attachment_versions" v
  where v."attachment_id" = v_row."id" and v."version" = restore_attachment_version.version
  for update;
  if v_old."id" is null then
    raise exception 'The file has no earlier version with this number' using errcode = 'P0002', hint = 'ATTACHMENT_VERSION_NOT_FOUND';
  end if;
  delete from "better_supabase"."attachment_versions" v where v."id" = v_old."id";
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("org_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at")
    values (v_row."org_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at");
  end if;
  update "better_supabase"."attachments" a set
    "version" = v_old."version",
    "name" = v_old."name",
    "mime_type" = v_old."mime_type",
    "size" = v_old."size",
    "width" = v_old."width",
    "height" = v_old."height",
    "pages" = v_old."pages",
    "status" = v_old."status",
    "scan_detail" = v_old."scan_detail",
    "uploaded_by" = v_old."uploaded_by",
    "uploaded_at" = v_old."uploaded_at",
    "scanned_at" = v_old."scanned_at"
  where a."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$$;

-- A file's earlier versions, newest first.
create or replace function "better_supabase"."list_attachment_versions"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(v) order by v."version" desc), '[]'::jsonb)
  from "better_supabase"."attachment_versions" v where v."attachment_id" = list_attachment_versions.id
$$;
revoke execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) from public, anon;
revoke execute on function "better_supabase"."restore_attachment_version"(uuid, integer) from public, anon;
revoke execute on function "better_supabase"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."replace_attachment"(uuid, text, text, bigint, integer, integer, integer) to authenticated, service_role;
grant execute on function "better_supabase"."restore_attachment_version"(uuid, integer) to authenticated, service_role;
grant execute on function "better_supabase"."list_attachment_versions"(uuid) to authenticated, service_role;

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
revoke all on "better_supabase"."scanned_objects" from public, anon, authenticated;
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
drop trigger if exists bsb_object_scan_pending on storage.objects;

revoke execute on function "better_supabase"."object_clean"(text, text) from public, anon;
revoke execute on function "better_supabase"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "better_supabase"."object_scan"(text, text) to service_role;
grant execute on function "better_supabase"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) from public, anon;
revoke execute on function "better_supabase"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_attachment_status"(uuid, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "better_supabase"."get_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment"(uuid) from public, anon;
grant execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_attachment_status"(uuid, text, text) to service_role;
grant execute on function "better_supabase"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."attachments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachments";
create policy bsb_tenant_scope_select on "better_supabase"."attachments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('attachments.read')) and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "org_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachments";
create policy bsb_tenant_scope_insert on "better_supabase"."attachments" as restrictive
  for insert to public
  with check (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid())
    and coalesce(better_supabase.can('tenant', "org_id", 'attachments.upload'), false)
    and "better_supabase"."attachment_subject_readable"("subject_type", "subject_id", "org_id"))
  );
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachments";
create policy bsb_tenant_scope_update on "better_supabase"."attachments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachments";
create policy bsb_tenant_scope_delete on "better_supabase"."attachments" as restrictive
  for delete to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('attachments.manage')))
  );
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_document_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_document_types" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('attachments.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_document_types" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_document_types" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_document_types";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_document_types" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."attachment_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_select on "better_supabase"."attachment_versions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_versions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_update on "better_supabase"."attachment_versions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."attachment_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_versions" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_034_attachments.sql
-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:dcd894555c7feed8442fdb2537836d5a60799ce09a4a91b898f5c7583445388c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
