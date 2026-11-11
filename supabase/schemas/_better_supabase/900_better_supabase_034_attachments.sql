-- better-supabase module: attachments
-- @bsb-block attachments@9 managed
-- @bsb-hash sha256:d86dfd8691b7e7464f05199faee42e8c8a6a262ba19934adb156e4f10f9fd14f
-- Files linked to records in a tenant: a record per file, a private bucket whose policies only accept an upload a pending record expects, and reads only for scanned files. confirm_attachment() emits attachment.uploaded for the app's scan job. options.publicBuckets serves chosen buckets by public URL, for media such as product images.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Files linked to records. Each object lives at options.path (default
-- {organization_id}/attachments/{id}) in the attachments bucket, or its
-- subject's bucket; the record is created first, so the storage policies
-- below only accept an upload a pending record expects.
-- Document types (ADR 0157): a key and a name per organization, and the fields
-- a file of that type carries in its metadata: { <key>: { type, required?,
-- options? } } with the types text, number, amount, date, expiry, boolean, select.
create table "better_supabase"."attachment_document_types" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null constraint bsb_attachment_document_types_key_check check ("key" ~ '^[a-z][a-z0-9_.-]{0,62}$'),
  "name" text not null constraint bsb_attachment_document_types_name_check check (length(btrim("name")) between 1 and 200),
  "fields" jsonb not null default '{}'::jsonb constraint bsb_attachment_document_types_fields_check check (jsonb_typeof("fields") = 'object'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."attachment_document_types" enable row level security;
revoke all on "better_supabase"."attachment_document_types" from public, anon, authenticated;
grant select on "better_supabase"."attachment_document_types" to authenticated;
grant all on "better_supabase"."attachment_document_types" to service_role;
create policy bsb_attachment_document_types_read on "better_supabase"."attachment_document_types"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('attachments.read')));

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
  insert into "better_supabase"."attachment_document_types" as t ("tenant_id", "key", "name", "fields")
  values (define_attachment_document_type.tenant, define_attachment_document_type.key, define_attachment_document_type.name, coalesce(define_attachment_document_type.fields, '{}'::jsonb))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "fields" = excluded."fields", "updated_at" = now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

-- The document types of an organization, by key.
create or replace function "better_supabase"."list_attachment_document_types"(tenant uuid)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t."key"), '[]'::jsonb)
  from "better_supabase"."attachment_document_types" t
  where t."tenant_id" = list_attachment_document_types.tenant
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
  where t."tenant_id" = delete_attachment_document_type.tenant and t."key" = delete_attachment_document_type.key;
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

create table "better_supabase"."attachments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text constraint bsb_attachments_subject_type_check check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text constraint bsb_attachments_subject_id_check check (length("subject_id") >= 1 and length("subject_id") <= 200),
  "bucket" text not null default 'attachments',
  "object_path" text,
  "name" text not null constraint bsb_attachments_name_check check (length("name") >= 1 and length("name") <= 255),
  "mime_type" text not null constraint bsb_attachments_mime_type_check check ("mime_type" ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  "size" bigint not null,
  "status" text not null default 'pending' constraint bsb_attachments_status_check check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null default auth.uid(),
  "created_at" timestamptz not null default clock_timestamp(),
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  constraint bsb_attachments_check check (("subject_type" is null) = ("subject_id" is null))
);
-- The current version (replace_attachment() adds one) and the image or
-- document size the client measured: width and height in pixels, pages.
alter table "better_supabase"."attachments" add column "version" integer not null default 1 constraint bsb_attachments_version_check check ("version" >= 1);
-- The SHA-256 of the file's bytes, hex, recorded by the scan step from the
-- stored object. A client never supplies it.
alter table "better_supabase"."attachments" add column "sha256" text constraint bsb_attachments_sha256_check check ("sha256" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."attachments" add column "hash_verified_at" timestamptz;
alter table "better_supabase"."attachments" add column "width" integer constraint bsb_attachments_width_check check ("width" > 0);
alter table "better_supabase"."attachments" add column "height" integer constraint bsb_attachments_height_check check ("height" > 0);
alter table "better_supabase"."attachments" add column "pages" integer constraint bsb_attachments_pages_check check ("pages" > 0);
-- App data about the file (a caption, the source, a page count), set on create.
alter table "better_supabase"."attachments" add column "metadata" jsonb not null default '{}' constraint bsb_attachments_metadata_check check (jsonb_typeof("metadata") = 'object');
-- Where a record came from and what it is (ADR 0157). storage_status follows
-- the upload: stored once uploaded_at is set, pending_upload until then, and
-- missing for a record whose file never arrived.
alter table "better_supabase"."attachments" add column "document_type_id" uuid references "better_supabase"."attachment_document_types" ("id") on delete restrict;
alter table "better_supabase"."attachments" add column "source" text constraint bsb_attachments_source_check check (length("source") >= 1 and length("source") <= 200);
alter table "better_supabase"."attachments" add column "external_id" text constraint bsb_attachments_external_id_check check (length("external_id") >= 1 and length("external_id") <= 500);
alter table "better_supabase"."attachments" add column "storage_status" text not null default 'pending_upload' constraint bsb_attachments_storage_status_check check ("storage_status" in ('stored', 'pending_upload', 'missing'));
alter table "better_supabase"."attachments" add column "source_path" text constraint bsb_attachments_source_path_check check (length("source_path") >= 1 and length("source_path") <= 2000);
alter table "better_supabase"."attachments" add constraint "bsb_attachments_external"
  check (("source" is null) = ("external_id" is null));
create unique index attachments_external_idx on "better_supabase"."attachments" ("tenant_id", "source", "external_id") where "source" is not null;
create index attachments_document_type_idx on "better_supabase"."attachments" ("document_type_id") where "document_type_id" is not null;

-- The bucket, size limit and MIME types come from the module options, so a
-- re-run applies changed options to an existing table.
-- "object_path" is a plain column a trigger fills: logical replication (PowerSync)
-- skips generated columns. An install from before keeps its values when the
-- expression is dropped.
create or replace function "better_supabase"."attachment_object_path"()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  select "tenant_id"::text || '/attachments/' || "id"::text into new."object_path" from (select new.*) as r;
  return new;
end;
$$;
revoke execute on function "better_supabase"."attachment_object_path"() from public, anon, authenticated;
create trigger bsb_attachments_object_path
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_object_path"();
-- options.path: the data file recomputes the path of a row that no longer
-- matches the template, so a changed template rewrites it.
comment on column "better_supabase"."attachments"."object_path" is 'better-supabase path: {organization_id}/attachments/{id}';
alter table "better_supabase"."attachments" alter column "bucket" set default 'attachments';
alter table "better_supabase"."attachments" add constraint "bsb_attachments_bucket"
  check ("bucket" in ('attachments')) not valid;
alter table "better_supabase"."attachments" add constraint "bsb_attachments_size"
  check ("size" >= 0 and "size" <= 52428800);
create unique index attachments_object_idx on "better_supabase"."attachments" ("bucket", "object_path");
create index attachments_subject_idx on "better_supabase"."attachments" ("tenant_id", "subject_type", "subject_id");
create index attachments_uploaded_by_idx on "better_supabase"."attachments" ("uploaded_by");
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
    if cardinality(v_types) > 0 and new."subject_type" <> all (v_types) and new."subject_type" <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'ledger_account', 'invoice', 'product', 'product_variant', 'rfq', 'till', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'maintenance_plan', 'dam_usage_right', 'lims_sample', 'tax_code', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'content_entry', 'document', 'customer', 'drive_node', 'organization', 'application', 'change_request', 'project', 'task']::text[]) then
      raise exception 'the subject type is not a registered subject type' using errcode = '22023', hint = 'ATTACHMENT_SUBJECT_UNKNOWN';
    end if;
  end if;
  if new."source" is not null and (tg_op = 'INSERT' or new."source" is distinct from old."source" or new."external_id" is distinct from old."external_id") then
    if not (new."source" = any (array[]::text[])
      or exists (
        select 1 from "better_supabase"."import_runs" r
        where r."tenant_id" = new."tenant_id" and r."source" = new."source"
      )) then
      raise exception 'the source is not in options.sources and has no import run' using errcode = '22023', hint = 'ATTACHMENT_SOURCE_UNKNOWN';
    end if;
    if new."tenant_id" is not null and exists (
      select 1 from "better_supabase"."attachments" x
      where x."tenant_id" = new."tenant_id" and x."source" = new."source" and x."external_id" = new."external_id" and x."id" <> new."id"
    ) then
      raise exception 'an attachment of this source already has this external id' using errcode = '23505', hint = 'ATTACHMENT_EXTERNAL_ID_TAKEN';
    end if;
  end if;
  if new."document_type_id" is not null and (tg_op = 'INSERT' or new."document_type_id" is distinct from old."document_type_id" or new."metadata" is distinct from old."metadata") then
    select y."fields" into v_fields from "better_supabase"."attachment_document_types" y
    where y."id" = new."document_type_id" and y."tenant_id" = new."tenant_id";
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
create trigger bsb_attachments_documents
  before insert or update on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachment_document_guard"();

alter table "better_supabase"."attachments" enable row level security;
revoke all on "better_supabase"."attachments" from public, anon, authenticated;
grant select, delete on "better_supabase"."attachments" to authenticated;
grant insert ("tenant_id", "bucket", "subject_type", "subject_id", "name", "mime_type", "size", "metadata", "width", "height", "pages", "document_type_id", "source", "external_id", "source_path") on "better_supabase"."attachments" to authenticated;
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
  return attachment_subject_readable.subject_type is null or (((attachment_subject_readable.tenant)::text, (attachment_subject_readable.subject_type)::text, (attachment_subject_readable.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case attachment_subject_readable.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'employees.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'ledger.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'invoices.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant and (coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."id" = attachment_subject_readable.tenant)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant)
    else false
  end);
end;
$$;
revoke execute on function "better_supabase"."attachment_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."attachment_subject_readable"(text, text, uuid) to authenticated, service_role;

create policy bsb_attachments_read on "better_supabase"."attachments"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('attachments.read')) or (("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) and ("better_supabase"."attachments"."subject_type" is null or ((("better_supabase"."attachments"."tenant_id")::text, ("better_supabase"."attachments"."subject_type")::text, ("better_supabase"."attachments"."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case "better_supabase"."attachments"."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id") and "better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('customers.read'))
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."tenant_id" = "better_supabase"."attachments"."tenant_id" and ("better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."id" = "better_supabase"."attachments"."tenant_id")
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    else "better_supabase"."attachment_subject_readable"("better_supabase"."attachments"."subject_type", "better_supabase"."attachments"."subject_id", "better_supabase"."attachments"."tenant_id")
  end)));
create policy bsb_attachments_insert on "better_supabase"."attachments"
  for insert to authenticated
  with check (("uploaded_by" = (select auth.uid())
    and ((("subject_type" = 'message' and ("tenant_id" in (select better_supabase.tenant_ids_with('messages.send')))) or ("subject_type" = 'conversation' and ("tenant_id" in (select better_supabase.tenant_ids_with('messages.send')))) or ("subject_type" = 'expense_line' and ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.submit')))) or (not coalesce("subject_type" in ('message', 'conversation', 'expense_line'), false) and "tenant_id" in (select better_supabase.tenant_ids_with('attachments.upload')))) or (("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))
    and ("better_supabase"."attachments"."subject_type" is null or ((("better_supabase"."attachments"."tenant_id")::text, ("better_supabase"."attachments"."subject_type")::text, ("better_supabase"."attachments"."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case "better_supabase"."attachments"."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id") and "better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('customers.read'))
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."tenant_id" = "better_supabase"."attachments"."tenant_id" and ("better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."id" = "better_supabase"."attachments"."tenant_id")
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    else "better_supabase"."attachment_subject_readable"("better_supabase"."attachments"."subject_type", "better_supabase"."attachments"."subject_id", "better_supabase"."attachments"."tenant_id")
  end))) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_delete on "better_supabase"."attachments"
  for delete to authenticated
  using (("uploaded_by" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('attachments.manage'))) and (select better_supabase.actor_may_write()));

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
  if v_row."tenant_id" is null then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'changed', 'attachments:' || v_row."tenant_id"::text, true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_changed"() from public, anon, authenticated;
create trigger "bsb_attachments_changed"
  after insert or update or delete on "better_supabase"."attachments"
  for each row execute function "better_supabase"."attachments_changed"();

-- Members join attachments:{tenant}; payloads name the subject whose files changed.
create policy bsb_attachments_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast'
        and (select realtime.topic()) like 'attachments:%'
        and substr((select realtime.topic()), 13) in (select x::text from better_supabase.tenant_ids_with('attachments.read') x));

-- The earlier versions of each file, written by replace_attachment() and
-- restore_attachment_version(). A reader of the file reads its versions; the
-- rows change only through those functions.
create table "better_supabase"."attachment_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "attachment_id" uuid not null references "better_supabase"."attachments" ("id") on delete cascade,
  "version" integer not null constraint bsb_attachment_versions_version_check check ("version" >= 1),
  "bucket" text not null,
  "object_path" text not null,
  "name" text not null,
  "mime_type" text not null,
  "size" bigint not null,
  "width" integer,
  "height" integer,
  "pages" integer,
  "status" text not null constraint bsb_attachment_versions_status_check check ("status" in ('pending', 'clean', 'infected', 'failed')),
  "scan_detail" text,
  "uploaded_by" uuid references auth.users (id) on delete set null,
  "uploaded_at" timestamptz,
  "scanned_at" timestamptz,
  "sha256" text,
  "hash_verified_at" timestamptz,
  "archived_at" timestamptz not null default now(),
  unique ("attachment_id", "version"),
  unique ("bucket", "object_path")
);
create index attachment_versions_uploaded_by_idx on "better_supabase"."attachment_versions" ("uploaded_by");
alter table "better_supabase"."attachment_versions" enable row level security;
revoke all on "better_supabase"."attachment_versions" from public, anon, authenticated;
grant select on "better_supabase"."attachment_versions" to authenticated;
grant all on "better_supabase"."attachment_versions" to service_role;
create policy bsb_attachment_versions_read on "better_supabase"."attachment_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read a not infected file or the uploader or attachments.manage, a delete
-- the uploader or attachments.manage. It reads the table as its owner, so
-- the storage policies don't depend on the table's own policies.

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
        when 'select' then (a."status" in ('pending', 'clean', 'failed') and (coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.read'), false) or ((a."tenant_id")::text, (a."subject_type")::text, (a."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))
          or a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
        else false
      end
  ) or exists (
    select 1 from "better_supabase"."attachment_versions" v
    join "better_supabase"."attachments" a on a."id" = v."attachment_id"
    where v."bucket" = attachment_object_allowed.bucket and v."object_path" = attachment_object_allowed.path
      and case attachment_object_allowed.action
        when 'select' then (v."status" in ('pending', 'clean', 'failed') and (coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.read'), false) or ((a."tenant_id")::text, (a."subject_type")::text, (a."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)))
          or v."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
        when 'delete' then a."uploaded_by" = auth.uid() or coalesce(better_supabase.can('tenant', a."tenant_id", 'attachments.manage'), false)
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

create policy bsb_attachments_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'insert')) and (select better_supabase.actor_may_write()));
create policy bsb_attachments_select on storage.objects
  for select to authenticated
  using (bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'select') and "better_supabase"."attachment_object_visible"(bucket_id, name));
create policy bsb_attachments_delete on storage.objects
  for delete to authenticated
  using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_allowed"(bucket_id, name, 'delete')) and (select better_supabase.actor_may_write()));

-- The caller's new record, for a signed upload URL to its object_path.

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
  v_row."tenant_id" := create_attachment.tenant;
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
    where y."tenant_id" = create_attachment.tenant and y."key" = create_attachment.document_type;
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22023', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;
  v_row."source" := create_attachment.source;
  v_row."external_id" := create_attachment.external_id;
  v_row."source_path" := create_attachment.source_path;
  select string_agg(column_name, ', ')
  into v_columns
  from unnest(array['"tenant_id"', '"bucket"', '"name"', '"mime_type"', '"size"', '"subject_type"', '"subject_id"', '"metadata"', '"width"', '"height"', '"pages"', '"document_type_id"', '"source"', '"external_id"', '"source_path"']
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
-- Without requireScan the file is clean right away.
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
    "mime_type" = coalesce(lower(v_meta ->> 'mimetype'), a."mime_type"),
    "status" = 'clean'
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.uploaded', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'mimeType', v_row."mime_type", 'size', v_row."size", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.uploaded',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'mimeType', v_row."mime_type", 'size', v_row."size", 'version', v_row."version")
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
  if not ((coalesce(better_supabase.can('tenant', v_row."tenant_id", case v_row."subject_type" when 'message' then 'messages.send' when 'conversation' then 'messages.send' when 'expense_line' then 'expenses.submit' else 'attachments.upload' end), false) or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
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
  if not (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
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
    where y."tenant_id" = v_tenant and y."key" = v_data ->> 'documentType';
    if not found then
      raise exception 'the document type doesn''t exist in this organization' using errcode = '22022', hint = 'ATTACHMENT_DOCUMENT_TYPE_UNKNOWN';
    end if;
  end if;

  select a."id" into v_id from "better_supabase"."attachments" a
  where a."tenant_id" = v_tenant and a."source" = v_source and a."external_id" = v_key;
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
    insert into "better_supabase"."attachments" ("tenant_id", "name", "mime_type", "size", "subject_type", "subject_id", "document_type_id", "metadata", "source", "external_id", "source_path", "storage_status", "uploaded_by")
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
create or replace function "better_supabase"."set_attachment_status"(id uuid, status text, detail text default null, sha256 text default null)
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
  if set_attachment_status.sha256 is not null and set_attachment_status.sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'sha256 must be 64 lowercase hex characters' using errcode = '22023', hint = 'ATTACHMENT_HASH_INVALID';
  end if;
  update "better_supabase"."attachments" a set
    "status" = set_attachment_status.status,
    "scan_detail" = set_attachment_status.detail,
    "scanned_at" = now(),
    "sha256" = coalesce(set_attachment_status.sha256, a."sha256"),
    "hash_verified_at" = case when set_attachment_status.sha256 is null then a."hash_verified_at" else now() end
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
  perform "better_supabase".emit_event('attachment.scanned', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'status', v_row."status", 'uploadedBy', v_row."uploaded_by"), 'attachments/' || v_row."id"::text, (v_row."tenant_id")::text, 'attachment.scanned:' || v_row."id"::text || ':' || v_row."status", 'better-supabase/attachments');
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
    and (y."tenant_id" in (select better_supabase.tenant_ids_with('attachments.read')) or ((y."tenant_id")::text, (y."subject_type")::text, (y."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g))
$$;
revoke execute on function "better_supabase"."attachment_authors"(uuid[]) from public, anon;
grant execute on function "better_supabase"."attachment_authors"(uuid[]) to authenticated, service_role;

create or replace function "better_supabase"."list_attachments"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_files jsonb;
begin
  with page as (
    select * from "better_supabase"."attachments" y
    where y."tenant_id" is not distinct from list_attachments.tenant
      and (list_attachments.subject_type is null or y."subject_type" = list_attachments.subject_type)
      and (list_attachments.subject_id is null or y."subject_id" = list_attachments.subject_id)
  ),
  m as (select "better_supabase"."attachment_authors"(array(select p."id" from page p)) as authors)
  select coalesce(jsonb_agg((to_jsonb(a) || jsonb_build_object('object_path', (case when a."version" > 1 then a."object_path" || '-v' || a."version"::text else a."object_path" end))) || jsonb_build_object('author', m.authors -> a."id"::text) order by a."created_at", a."id"), '[]'::jsonb) into v_files
  from page a, m;
  if jsonb_array_length(v_files) > 0 and list_attachments.subject_type is not null and list_attachments.subject_id is not null then
    perform "better_supabase"."record_subject_read"(list_attachments.subject_type, list_attachments.subject_id, null, 'attachments', 'list_attachments');
  end if;
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
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and (coalesce(better_supabase.can('tenant', v_row."tenant_id", case v_row."subject_type" when 'message' then 'messages.send' when 'conversation' then 'messages.send' when 'expense_line' then 'expenses.submit' else 'attachments.upload' end), false) or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No attachment you may replace has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    insert into "better_supabase"."attachment_versions" ("tenant_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at", "sha256", "hash_verified_at")
    values (v_row."tenant_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at", v_row."sha256", v_row."hash_verified_at");
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
    "scanned_at" = null,
    "sha256" = null,
    "hash_verified_at" = null
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.replaced', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.replaced',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'version', v_row."version")
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
  if v_row."id" is null or not ((coalesce(v_row."uploaded_by" = auth.uid(), false) and (coalesce(better_supabase.can('tenant', v_row."tenant_id", case v_row."subject_type" when 'message' then 'messages.send' when 'conversation' then 'messages.send' when 'expense_line' then 'expenses.submit' else 'attachments.upload' end), false) or ((v_row."tenant_id")::text, (v_row."subject_type")::text, (v_row."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'attachments.manage'), false) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
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
    insert into "better_supabase"."attachment_versions" ("tenant_id", "attachment_id", "version", "bucket", "object_path", "name", "mime_type", "size", "width", "height", "pages", "status", "scan_detail", "uploaded_by", "uploaded_at", "scanned_at", "sha256", "hash_verified_at")
    values (v_row."tenant_id", v_row."id", v_row."version", v_row."bucket", (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end), v_row."name", v_row."mime_type", v_row."size", v_row."width", v_row."height", v_row."pages", v_row."status", v_row."scan_detail", v_row."uploaded_by", v_row."uploaded_at", v_row."scanned_at", v_row."sha256", v_row."hash_verified_at");
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
    "scanned_at" = v_old."scanned_at",
    "sha256" = v_old."sha256",
    "hash_verified_at" = v_old."hash_verified_at"
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.restored', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.restored',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'version', v_row."version")
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
create table "better_supabase"."scanned_objects" (
  "bucket" text not null,
  "object_path" text not null,
  "status" text not null default 'pending' constraint bsb_scanned_objects_status_check check ("status" in ('pending', 'clean', 'infected', 'failed')),
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

-- on with cascade: deleting a subject row deletes its attachments rows.
create or replace function "better_supabase"."attachments_subject_deleted_product"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_subject_deleted_product"() from public, anon, authenticated;
create trigger "bsb_attachments_product_cascade"
  after delete on "better_supabase"."products"
  for each row execute function "better_supabase"."attachments_subject_deleted_product"();

create or replace function "better_supabase"."attachments_subject_deleted_product_variant"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."attachments" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."attachments_subject_deleted_product_variant"() from public, anon, authenticated;
create trigger "bsb_attachments_product_variant_cascade"
  after delete on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."attachments_subject_deleted_product_variant"();

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."attachments_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.activities' then array['activity'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.rfqs' then array['rfq'] when 'better_supabase.tills' then array['till'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.leases' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.compliance_policies' then array['compliance_policy'] when 'better_supabase.qualification_types' then array['qualification_type'] when 'better_supabase.risks' then array['risk'] when 'better_supabase.cases' then array['case'] when 'better_supabase.inspections' then array['inspection'] when 'better_supabase.inspection_programs' then array['inspection_program'] when 'better_supabase.inspection_findings' then array['inspection_finding'] when 'better_supabase.forms' then array['form'] when 'better_supabase.meetings' then array['meeting'] when 'better_supabase.meeting_decisions' then array['meeting_decision'] when 'better_supabase.maintenance_plans' then array['maintenance_plan'] when 'better_supabase.dam_usage_rights' then array['dam_usage_right'] when 'better_supabase.lims_samples' then array['lims_sample'] when 'better_supabase.tax_codes' then array['tax_code'] when 'better_supabase.production_orders' then array['production_order'] when 'better_supabase.work_centers' then array['work_center'] when 'better_supabase.bank_accounts' then array['bank_account'] when 'better_supabase.care_plans' then array['care_plan'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'public.organizations' then array['organization'] when 'better_supabase.applications' then array['application'] when 'public.change_requests' then array['change_request'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."attachments" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."attachments_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."attachments_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

revoke execute on function "better_supabase"."object_clean"(text, text) from public, anon;
revoke execute on function "better_supabase"."object_scan"(text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."set_object_scan"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."object_clean"(text, text) to authenticated, service_role;
grant execute on function "better_supabase"."object_scan"(text, text) to service_role;
grant execute on function "better_supabase"."set_object_scan"(text, text, text, text) to service_role;
revoke execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) from public, anon;
revoke execute on function "better_supabase"."confirm_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."set_attachment_status"(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."list_attachments"(uuid, text, text) from public, anon;
revoke execute on function "better_supabase"."get_attachment"(uuid) from public, anon;
revoke execute on function "better_supabase"."delete_attachment"(uuid) from public, anon;
grant execute on function "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, text, text, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."confirm_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."set_attachment_status"(uuid, text, text, text) to service_role;
grant execute on function "better_supabase"."list_attachments"(uuid, text, text) to authenticated, service_role;
grant execute on function "better_supabase"."get_attachment"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."delete_attachment"(uuid) to authenticated, service_role;
-- Seeds the rows every organization starts with for attachments. Safe to run
-- again: a row whose key exists is kept. It is not an entry point.
create or replace function "better_supabase"."seed_attachments_defaults"(p_tenant uuid, p_variant text default null, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'contract', 'Contract', '{"counterparty":{"type":"text","required":true},"signed_on":{"type":"date"},"expires_on":{"type":"expiry"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'contract');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'invoice', 'Invoice', '{"number":{"type":"text","required":true},"issued_on":{"type":"date"},"amount":{"type":"amount"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'invoice');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'receipt', 'Receipt', '{"merchant":{"type":"text"},"paid_on":{"type":"date"},"amount":{"type":"amount"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'receipt');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'identity', 'Identity document', '{"number":{"type":"text"},"expires_on":{"type":"expiry"}}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'identity');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'report', 'Report', '{}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'report');
  insert into "better_supabase"."attachment_document_types" ("tenant_id", "key", "name", "fields")
  select p_tenant, 'other', 'Other', '{}'::jsonb
  where not exists (select 1 from "better_supabase"."attachment_document_types" x where x."tenant_id" = p_tenant and x."key" is not distinct from 'other');
end;
$$;
revoke execute on function "better_supabase"."seed_attachments_defaults"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."seed_attachments_defaults"(uuid, text, text) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."attachments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('attachments.read')) or (("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) and ("better_supabase"."attachments"."subject_type" is null or ((("better_supabase"."attachments"."tenant_id")::text, ("better_supabase"."attachments"."subject_type")::text, ("better_supabase"."attachments"."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case "better_supabase"."attachments"."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id") and "better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('customers.read'))
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."tenant_id" = "better_supabase"."attachments"."tenant_id" and ("better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."id" = "better_supabase"."attachments"."tenant_id")
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    else "better_supabase"."attachment_subject_readable"("better_supabase"."attachments"."subject_type", "better_supabase"."attachments"."subject_id", "better_supabase"."attachments"."tenant_id")
  end)))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."attachments" as restrictive
  for insert to public
  with check (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid())
    and ((("subject_type" = 'message' and ("tenant_id" in (select better_supabase.tenant_ids_with('messages.send')))) or ("subject_type" = 'conversation' and ("tenant_id" in (select better_supabase.tenant_ids_with('messages.send')))) or ("subject_type" = 'expense_line' and ("tenant_id" in (select better_supabase.tenant_ids_with('expenses.submit')))) or (not coalesce("subject_type" in ('message', 'conversation', 'expense_line'), false) and "tenant_id" in (select better_supabase.tenant_ids_with('attachments.upload')))) or (("tenant_id")::text, ("subject_type")::text, ("subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('upload') g))
    and ("better_supabase"."attachments"."subject_type" is null or ((("better_supabase"."attachments"."tenant_id")::text, ("better_supabase"."attachments"."subject_type")::text, ("better_supabase"."attachments"."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case "better_supabase"."attachments"."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id") and "better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('customers.read'))
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."tenant_id" = "better_supabase"."attachments"."tenant_id" and ("better_supabase"."attachments"."tenant_id" in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."id" = "better_supabase"."attachments"."tenant_id")
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ("better_supabase"."attachments"."subject_id")::uuid and s."organization_id" = "better_supabase"."attachments"."tenant_id")
    else "better_supabase"."attachment_subject_readable"("better_supabase"."attachments"."subject_type", "better_supabase"."attachments"."subject_id", "better_supabase"."attachments"."tenant_id")
  end)))
  );
create policy bsb_tenant_scope_update on "better_supabase"."attachments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."attachments" as restrictive
  for delete to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("uploaded_by" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('attachments.manage')))
  );
create policy bsb_tenant_scope_select on "better_supabase"."attachment_document_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('attachments.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_document_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."attachment_document_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_document_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."attachment_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."attachments" a where a."id" = "attachment_id"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."attachment_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."attachment_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."attachment_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.attachments deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"attachment","event_prefix":"attachment"}');

-- blocks.attachments.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.


create or replace function "api"."attachment_schema_error"(fields jsonb)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$ select "better_supabase"."attachment_schema_error"($1) $$;
revoke execute on function "api"."attachment_schema_error"(jsonb) from public, anon;
grant execute on function "api"."attachment_schema_error"(jsonb) to authenticated, service_role;

create or replace function "api"."attachment_fields_error"(fields jsonb, data jsonb)
returns text
language sql
stable
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

create or replace function "api"."import_attachment"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_attachment"($1, $2, $3) $$;
revoke execute on function "api"."import_attachment"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_attachment"(uuid, jsonb, text) to service_role;

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
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_attachment_versions"($1) $$;
revoke execute on function "api"."list_attachment_versions"(uuid) from public, anon;
grant execute on function "api"."list_attachment_versions"(uuid) to authenticated, service_role;

create or replace function "api"."object_scan"(bucket text, path text)
returns jsonb
language sql
stable
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

create or replace function "api"."set_attachment_status"(id uuid, status text, detail text default null, sha256 text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_attachment_status"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_attachment_status"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "api"."set_attachment_status"(uuid, text, text, text) to service_role;

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
stable
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

create or replace function "api"."seed_attachments_defaults"(p_tenant uuid, p_variant text default null, p_locale text default 'en')
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."seed_attachments_defaults"($1, $2, $3) $$;
revoke execute on function "api"."seed_attachments_defaults"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."seed_attachments_defaults"(uuid, text, text) to service_role;
