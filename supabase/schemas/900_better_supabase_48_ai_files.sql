-- better-supabase module: ai-files (0.5.1)
-- @bs-module ai-files@1 managed
-- Files and documents for AI chats: a private bucket whose policies only accept an upload a reserved record expects, provider file references with expiry, versioned documents with suggested edits, and a purge that hands back the objects to remove.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Files for AI chats: uploads, generated images and audio, and what a
-- provider's file API returned for them. Objects live in the private
-- ai-files bucket at {organization_id}/{owner_id}/{id}/{filename}; the record is
-- reserved first, so the storage policies only accept the upload it expects.
create table if not exists "better_supabase"."ai_files" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "owner_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "project_id" uuid,
  "bucket" text not null,
  "filename" text not null check (length("filename") between 1 and 255 and "filename" !~ '[/\\]' and "filename" not in ('.', '..')),
  "path" text generated always as ("organization_id"::text || '/' || "owner_id"::text || '/' || "id"::text || '/' || "filename") stored,
  "media_type" text not null check ("media_type" ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$'),
  "byte_size" bigint not null check ("byte_size" between 0 and 52428800),
  "sha256" text check ("sha256" ~ '^[0-9a-f]{64}$'),
  "status" text not null default 'pending' check ("status" in ('pending', 'ready', 'failed')),
  "source" text not null default 'upload' check ("source" in ('upload', 'generated', 'provider')),
  "created_at" timestamptz not null default now(),
  "uploaded_at" timestamptz,
  "expires_at" timestamptz
);
create unique index if not exists ai_files_object_idx on "better_supabase"."ai_files" ("bucket", "path");
create index if not exists ai_files_owner_idx on "better_supabase"."ai_files" ("owner_id");
create index if not exists ai_files_tenant_idx on "better_supabase"."ai_files" ("organization_id");
create index if not exists ai_files_chat_idx on "better_supabase"."ai_files" ("chat_id") where "chat_id" is not null;
create index if not exists ai_files_pending_idx on "better_supabase"."ai_files" ("created_at") where "status" = 'pending';
alter table "better_supabase"."ai_files" enable row level security;
revoke all on "better_supabase"."ai_files" from anon, authenticated;
grant select on "better_supabase"."ai_files" to authenticated;
grant all on "better_supabase"."ai_files" to service_role;
drop policy if exists ai_files_read on "better_supabase"."ai_files";
create policy ai_files_read on "better_supabase"."ai_files" for select to authenticated
  using (("owner_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')) or ("chat_id" is not null and "better_supabase"."ai_chat_can_read"("chat_id"))));

-- What a provider's file API returned for a file (an OpenAI file id, a
-- Gemini file URI), so the next call reuses it until it expires.
create table if not exists "better_supabase"."ai_provider_files" (
  "file_id" uuid not null references "better_supabase"."ai_files" ("id") on delete cascade,
  "provider" text not null check (length("provider") between 1 and 100),
  "reference" text not null check (length("reference") between 1 and 2000),
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now(),
  primary key ("file_id", "provider")
);
create index if not exists ai_provider_files_expires_idx on "better_supabase"."ai_provider_files" ("expires_at") where "expires_at" is not null;
alter table "better_supabase"."ai_provider_files" enable row level security;
revoke all on "better_supabase"."ai_provider_files" from anon, authenticated;
grant all on "better_supabase"."ai_provider_files" to service_role;

-- Documents an assistant writes and the user edits beside the chat (text,
-- code, sheets, images), with every version kept.
create table if not exists "better_supabase"."ai_documents" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "owner_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "kind" text not null check ("kind" in ('text', 'code', 'sheet', 'image')),
  "title" text not null check (length("title") between 1 and 500),
  "current_version" integer not null default 1 check ("current_version" >= 1),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists ai_documents_owner_idx on "better_supabase"."ai_documents" ("owner_id");
create index if not exists ai_documents_tenant_idx on "better_supabase"."ai_documents" ("organization_id");
create index if not exists ai_documents_chat_idx on "better_supabase"."ai_documents" ("chat_id") where "chat_id" is not null;
alter table "better_supabase"."ai_documents" enable row level security;
revoke all on "better_supabase"."ai_documents" from anon, authenticated;
grant select on "better_supabase"."ai_documents" to authenticated;
grant all on "better_supabase"."ai_documents" to service_role;
drop policy if exists ai_documents_read on "better_supabase"."ai_documents";
create policy ai_documents_read on "better_supabase"."ai_documents" for select to authenticated
  using (("owner_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')) or ("chat_id" is not null and "better_supabase"."ai_chat_can_read"("chat_id"))));

create table if not exists "better_supabase"."ai_document_versions" (
  "document_id" uuid not null references "better_supabase"."ai_documents" ("id") on delete cascade,
  "version" integer not null check ("version" >= 1),
  "content" text,
  "storage_path" text,
  "created_by_message_id" text,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  primary key ("document_id", "version"),
  check ("content" is not null or "storage_path" is not null)
);
create index if not exists ai_document_versions_created_by_idx on "better_supabase"."ai_document_versions" ("created_by") where "created_by" is not null;
alter table "better_supabase"."ai_document_versions" enable row level security;
revoke all on "better_supabase"."ai_document_versions" from anon, authenticated;
grant select on "better_supabase"."ai_document_versions" to authenticated;
grant all on "better_supabase"."ai_document_versions" to service_role;
drop policy if exists ai_document_versions_read on "better_supabase"."ai_document_versions";
create policy ai_document_versions_read on "better_supabase"."ai_document_versions" for select to authenticated
  using (exists (select 1 from "better_supabase"."ai_documents" doc where doc."id" = "document_id"));

create table if not exists "better_supabase"."ai_suggestions" (
  "id" uuid primary key default gen_random_uuid(),
  "document_id" uuid not null references "better_supabase"."ai_documents" ("id") on delete cascade,
  "version" integer not null,
  "original_text" text not null,
  "suggested_text" text not null,
  "description" text,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "resolved_at" timestamptz,
  "accepted" boolean
);
create index if not exists ai_suggestions_document_idx on "better_supabase"."ai_suggestions" ("document_id");
create index if not exists ai_suggestions_created_by_idx on "better_supabase"."ai_suggestions" ("created_by") where "created_by" is not null;
alter table "better_supabase"."ai_suggestions" enable row level security;
revoke all on "better_supabase"."ai_suggestions" from anon, authenticated;
grant select on "better_supabase"."ai_suggestions" to authenticated;
grant all on "better_supabase"."ai_suggestions" to service_role;
drop policy if exists ai_suggestions_read on "better_supabase"."ai_suggestions";
create policy ai_suggestions_read on "better_supabase"."ai_suggestions" for select to authenticated
  using (exists (select 1 from "better_supabase"."ai_documents" doc where doc."id" = "document_id"));

-- Whether the caller may run action (insert, select or delete) on the
-- object at path in bucket: an upload needs the caller's pending record, a
-- read the owner, an ai_chat admin or a reader of the file's chat, a delete
-- the owner or an admin. It reads the table as its owner, so the storage
-- policies don't depend on the table's own policies.
create or replace function "better_supabase"."ai_file_object_allowed"(bucket text, path text, action text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."ai_files" a
    where a."bucket" = ai_file_object_allowed.bucket and a."path" = ai_file_object_allowed.path
      and case ai_file_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."owner_id" = auth.uid()
        when 'select' then a."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'ai_chat.admin'), false) or (a."chat_id" is not null and "better_supabase"."ai_chat_can_read"(a."chat_id"))
        when 'delete' then a."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'ai_chat.admin'), false)
        else false
      end
  )
$$;
revoke execute on function "better_supabase"."ai_file_object_allowed"(text, text, text) from public, anon;
grant execute on function "better_supabase"."ai_file_object_allowed"(text, text, text) to authenticated, service_role;

drop policy if exists bs_ai_files_insert on storage.objects;
drop policy if exists bs_ai_files_select on storage.objects;
drop policy if exists bs_ai_files_delete on storage.objects;
create policy bs_ai_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'ai-files' and "better_supabase"."ai_file_object_allowed"(bucket_id, name, 'insert'));
create policy bs_ai_files_select on storage.objects for select to authenticated
  using (bucket_id = 'ai-files' and "better_supabase"."ai_file_object_allowed"(bucket_id, name, 'select'));
create policy bs_ai_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'ai-files' and "better_supabase"."ai_file_object_allowed"(bucket_id, name, 'delete'));

-- Reserves a file for the caller, who then uploads to its path (a signed
-- upload URL, or TUS for large files). The size and type are checked here
-- and again by the bucket.
create or replace function "better_supabase"."reserve_ai_file"(
  tenant uuid,
  filename text,
  media_type text,
  byte_size bigint,
  chat_id uuid default null,
  project_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', reserve_ai_file.tenant, 'ai_chat.create'), false) then
    raise exception 'you may not upload files here' using errcode = '42501', hint = 'AI_FILE_FORBIDDEN';
  end if;
  if byte_size < 0 or byte_size > 52428800 then
    raise exception 'files are limited to % bytes', 52428800 using errcode = '22023', hint = 'AI_FILE_TOO_LARGE';
  end if;
  insert into "better_supabase"."ai_files" ("organization_id", "owner_id", "chat_id", "project_id", "bucket", "filename", "media_type", "byte_size")
  values (reserve_ai_file.tenant, auth.uid(), reserve_ai_file.chat_id, reserve_ai_file.project_id, 'ai-files', reserve_ai_file.filename, lower(reserve_ai_file.media_type), reserve_ai_file.byte_size)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$$;
revoke execute on function "better_supabase"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) to authenticated, service_role;

-- Marks an upload done once its object exists, taking the stored size.
create or replace function "better_supabase"."confirm_ai_file"(file_id uuid, sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_files"%rowtype;
  v_size bigint;
begin
  select * into v_row from "better_supabase"."ai_files" x where x."id" = confirm_ai_file.file_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid()) then
    raise exception 'file % not found', file_id using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  if v_row."status" <> 'pending' then
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
  end if;
  select (o.metadata ->> 'size')::bigint into v_size
  from storage.objects o where o.bucket_id = v_row."bucket" and o.name = v_row."path";
  if not found then
    raise exception 'file % has no uploaded object yet', file_id using errcode = 'P0001', hint = 'AI_FILE_NOT_UPLOADED';
  end if;
  update "better_supabase"."ai_files" x set
    "status" = 'ready',
    "uploaded_at" = now(),
    "byte_size" = coalesce(v_size, x."byte_size"),
    "sha256" = coalesce(lower(confirm_ai_file.sha256), x."sha256")
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$$;
revoke execute on function "better_supabase"."confirm_ai_file"(uuid, text) from public, anon;
grant execute on function "better_supabase"."confirm_ai_file"(uuid, text) to authenticated, service_role;

-- A file the caller may read, by id or by object path; null otherwise.
create or replace function "better_supabase"."get_ai_file"(file_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") from "better_supabase"."ai_files" x where x."id" = get_ai_file.file_id
$$;
revoke execute on function "better_supabase"."get_ai_file"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ai_file"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."get_ai_file_by_path"(bucket text, path text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") from "better_supabase"."ai_files" x
  where x."bucket" = get_ai_file_by_path.bucket and x."path" = get_ai_file_by_path.path
$$;
revoke execute on function "better_supabase"."get_ai_file_by_path"(text, text) from public, anon;
grant execute on function "better_supabase"."get_ai_file_by_path"(text, text) to authenticated, service_role;

-- The files of a chat the caller can read, oldest first.
create or replace function "better_supabase"."list_ai_files"(chat_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'bucket', x."bucket", 'path', x."path", 'media_type', x."media_type", 'filename', x."filename", 'byte_size', x."byte_size", 'sha256', x."sha256", 'status', x."status", 'source', x."source", 'created_at', x."created_at", 'uploaded_at', x."uploaded_at", 'expires_at', x."expires_at") order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."ai_files" x where x."chat_id" = list_ai_files.chat_id
$$;
revoke execute on function "better_supabase"."list_ai_files"(uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_files"(uuid) to authenticated, service_role;

-- Deletes the record; returns { bucket, path } for the Storage API to
-- remove the object, or null when the caller may not delete it.
create or replace function "better_supabase"."delete_ai_file"(file_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_files" x where x."id" = delete_ai_file.file_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_files" x where x."id" = v_row."id";
  return jsonb_build_object('bucket', v_row."bucket", 'path', v_row."path");
end;
$$;
revoke execute on function "better_supabase"."delete_ai_file"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_file"(uuid) to authenticated, service_role;

-- A ready file the server writes itself (a generated image, speech, a file
-- a provider returned), owned by owner; the caller uploads to its path.
create or replace function "better_supabase"."store_ai_file"(
  tenant uuid,
  owner uuid,
  filename text,
  media_type text,
  byte_size bigint,
  chat_id uuid default null,
  source text default 'generated',
  sha256 text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  insert into "better_supabase"."ai_files" ("organization_id", "owner_id", "chat_id", "bucket", "filename", "media_type", "byte_size", "status", "source", "sha256", "uploaded_at")
  values (store_ai_file.tenant, store_ai_file.owner, store_ai_file.chat_id, 'ai-files', store_ai_file.filename, lower(store_ai_file.media_type), store_ai_file.byte_size, 'ready', coalesce(store_ai_file.source, 'generated'), lower(store_ai_file.sha256), now())
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$$;
revoke execute on function "better_supabase"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) to service_role;

create or replace function "better_supabase"."set_ai_provider_file"(file_id uuid, provider text, reference text, expires_at timestamptz default null)
returns boolean
language sql
set search_path = ''
as $$
  insert into "better_supabase"."ai_provider_files" ("file_id", "provider", "reference", "expires_at")
  values (set_ai_provider_file.file_id, set_ai_provider_file.provider, set_ai_provider_file.reference, set_ai_provider_file.expires_at)
  on conflict ("file_id", "provider") do update
    set "reference" = excluded."reference", "expires_at" = excluded."expires_at", "created_at" = now()
  returning true
$$;
revoke execute on function "better_supabase"."set_ai_provider_file"(uuid, text, text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."set_ai_provider_file"(uuid, text, text, timestamptz) to service_role;

-- The provider's reference while it is still valid, or null.
create or replace function "better_supabase"."get_ai_provider_file"(file_id uuid, provider text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('file_id', p."file_id", 'provider', p."provider", 'reference', p."reference", 'expires_at', p."expires_at")
  from "better_supabase"."ai_provider_files" p
  where p."file_id" = get_ai_provider_file.file_id and p."provider" = get_ai_provider_file.provider
    and (p."expires_at" is null or p."expires_at" > now())
$$;
revoke execute on function "better_supabase"."get_ai_provider_file"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."get_ai_provider_file"(uuid, text) to service_role;

-- Provider references that expire within horizon, for a refresh job.
create or replace function "better_supabase"."expiring_ai_provider_files"(horizon interval default '1 day', batch integer default 100)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('file_id', p."file_id", 'provider', p."provider", 'reference', p."reference", 'expires_at', p."expires_at")), '[]'::jsonb)
  from (
    select * from "better_supabase"."ai_provider_files"
    where "expires_at" is not null and "expires_at" <= now() + coalesce(horizon, interval '1 day')
    order by "expires_at"
    limit greatest(coalesce(batch, 100), 1)
  ) p
$$;
revoke execute on function "better_supabase"."expiring_ai_provider_files"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expiring_ai_provider_files"(interval, integer) to service_role;

-- Deletes pending uploads older than older_than, expired files and, with
-- ai-chat installed, the files of deleted chats. Returns the { bucket, path }
-- objects for the Storage API to remove.
create or replace function "better_supabase"."purge_ai_files"(older_than interval default '1 day', batch integer default 500)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_removed jsonb;
begin
  with doomed as (
    select x."id" from "better_supabase"."ai_files" x
    where (x."status" = 'pending' and x."created_at" <= now() - coalesce(older_than, interval '1 day'))
      or x."expires_at" <= now()
      or (x."chat_id" is not null and not exists (select 1 from "better_supabase"."ai_chats" ch where ch."id" = x."chat_id"))
    limit greatest(coalesce(batch, 500), 1)
  ),
  gone as (
    delete from "better_supabase"."ai_files" x using doomed where x."id" = doomed."id"
    returning x."bucket" as bucket, x."path" as path
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', gone.bucket, 'path', gone.path)), '[]'::jsonb) into v_removed from gone;
  return v_removed;
end;
$$;
revoke execute on function "better_supabase"."purge_ai_files"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."purge_ai_files"(interval, integer) to service_role;

-- A document with its first version. The caller needs upload rights in the
-- organization; the service role writes for an owner.
create or replace function "better_supabase"."create_ai_document"(
  tenant uuid,
  kind text,
  title text,
  content text default null,
  chat_id uuid default null,
  message_id text default null,
  owner uuid default null,
  storage_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_ai_document.owner else auth.uid() end;
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  if v_owner is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_ai_document.tenant, 'ai_chat.create'), false)) then
    raise exception 'you may not create documents here' using errcode = '42501', hint = 'AI_DOCUMENT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_documents" ("organization_id", "owner_id", "chat_id", "kind", "title")
  values (create_ai_document.tenant, v_owner, create_ai_document.chat_id, create_ai_document.kind, create_ai_document.title)
  returning * into v_row;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", 1, create_ai_document.content, create_ai_document.storage_path, create_ai_document.message_id, v_owner);
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) to authenticated, service_role;

-- A new version of the document. expected_version guards against two
-- writers: when it is set and not the current version, nothing changes.
create or replace function "better_supabase"."update_ai_document"(
  document_id uuid,
  content text default null,
  title text default null,
  message_id text default null,
  expected_version integer default null,
  storage_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = update_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  if expected_version is not null and expected_version <> v_row."current_version" then
    raise exception 'document % is at version %', document_id, v_row."current_version" using errcode = '40001', hint = 'AI_DOCUMENT_CONFLICT';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, update_ai_document.content, update_ai_document.storage_path, update_ai_document.message_id, auth.uid());
  update "better_supabase"."ai_documents" x set
    "current_version" = v_row."current_version" + 1,
    "title" = coalesce(update_ai_document.title, x."title"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_ai_document"(uuid, text, text, text, integer, text) from public, anon;
grant execute on function "better_supabase"."update_ai_document"(uuid, text, text, text, integer, text) to authenticated, service_role;

-- Writes version as the newest version again.
create or replace function "better_supabase"."rollback_ai_document"(document_id uuid, version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
  v_old "better_supabase"."ai_document_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = rollback_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."ai_document_versions" x where x."document_id" = v_row."id" and x."version" = rollback_ai_document.version;
  if not found then
    raise exception 'document % has no version %', document_id, rollback_ai_document.version using errcode = 'P0002', hint = 'AI_DOCUMENT_VERSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, v_old."content", v_old."storage_path", null, auth.uid());
  update "better_supabase"."ai_documents" x set "current_version" = v_row."current_version" + 1, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."rollback_ai_document"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."rollback_ai_document"(uuid, integer) to authenticated, service_role;

create or replace function "better_supabase"."get_ai_document"(document_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'chat_id', x."chat_id", 'kind', x."kind", 'title', x."title", 'current_version', x."current_version", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('content', vv."content", 'storage_path', vv."storage_path")
  from "better_supabase"."ai_documents" x
  join "better_supabase"."ai_document_versions" vv on vv."document_id" = x."id" and vv."version" = x."current_version"
  where x."id" = get_ai_document.document_id
$$;
revoke execute on function "better_supabase"."get_ai_document"(uuid) from public, anon;
grant execute on function "better_supabase"."get_ai_document"(uuid) to authenticated, service_role;

-- Every version of a document the caller can read, newest first.
create or replace function "better_supabase"."list_ai_document_versions"(document_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('document_id', x."document_id", 'version', x."version", 'content', x."content", 'storage_path', x."storage_path", 'created_by_message_id', x."created_by_message_id", 'created_by', x."created_by", 'created_at', x."created_at") order by x."version" desc), '[]'::jsonb)
  from "better_supabase"."ai_document_versions" x where x."document_id" = list_ai_document_versions.document_id
$$;
revoke execute on function "better_supabase"."list_ai_document_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."list_ai_document_versions"(uuid) to authenticated, service_role;

-- A suggested edit on the current version; the assistant or a reader of the
-- document writes it, the owner resolves it.
create or replace function "better_supabase"."suggest_ai_document_edit"(document_id uuid, original_text text, suggested_text text, description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_doc "better_supabase"."ai_documents"%rowtype;
  v_row "better_supabase"."ai_suggestions"%rowtype;
begin
  select * into v_doc from "better_supabase"."ai_documents" x where x."id" = suggest_ai_document_edit.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_doc."owner_id" = (select auth.uid()) or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai_chat.admin'), false) or (v_doc."chat_id" is not null and "better_supabase"."ai_chat_can_read"(v_doc."chat_id")))) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_suggestions" ("document_id", "version", "original_text", "suggested_text", "description", "created_by")
  values (v_doc."id", v_doc."current_version", suggest_ai_document_edit.original_text, suggest_ai_document_edit.suggested_text, suggest_ai_document_edit.description, auth.uid())
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
end;
$$;
revoke execute on function "better_supabase"."suggest_ai_document_edit"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."suggest_ai_document_edit"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_ai_suggestions"(document_id uuid, open_only boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'document_id', x."document_id", 'version', x."version", 'original_text', x."original_text", 'suggested_text', x."suggested_text", 'description', x."description", 'created_by', x."created_by", 'created_at', x."created_at", 'resolved_at', x."resolved_at", 'accepted', x."accepted") order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."ai_suggestions" x
  where x."document_id" = list_ai_suggestions.document_id
    and (not coalesce(open_only, true) or x."resolved_at" is null)
$$;
revoke execute on function "better_supabase"."list_ai_suggestions"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_ai_suggestions"(uuid, boolean) to authenticated, service_role;

-- Accepts or rejects a suggestion; accepting doesn't edit the document, the
-- client writes the new version with update_ai_document.
create or replace function "better_supabase"."resolve_ai_suggestion"(suggestion_id uuid, accepted boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_suggestions"%rowtype;
  v_doc "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_suggestions" x where x."id" = resolve_ai_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."ai_documents" x where x."id" = v_row."document_id";
  end if;
  if v_doc."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_doc."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'suggestion % not found', suggestion_id using errcode = 'P0002', hint = 'AI_SUGGESTION_NOT_FOUND';
  end if;
  update "better_supabase"."ai_suggestions" x set "resolved_at" = now(), "accepted" = resolve_ai_suggestion.accepted
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
end;
$$;
revoke execute on function "better_supabase"."resolve_ai_suggestion"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."resolve_ai_suggestion"(uuid, boolean) to authenticated, service_role;

-- Deletes a document and its versions; true when the caller could.
create or replace function "better_supabase"."delete_ai_document"(document_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = delete_ai_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_documents" x where x."id" = v_row."id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_document"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_document"(uuid) to authenticated, service_role;

-- sql.modules.ai-files.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."ai_file_object_allowed"(text, text, text);

create or replace function "api"."reserve_ai_file"(tenant uuid, filename text, media_type text, byte_size bigint, chat_id uuid default null, project_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reserve_ai_file"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) from public, anon;
grant execute on function "api"."reserve_ai_file"(uuid, text, text, bigint, uuid, uuid) to authenticated, service_role;

create or replace function "api"."confirm_ai_file"(file_id uuid, sha256 text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."confirm_ai_file"($1, $2) $$;
revoke execute on function "api"."confirm_ai_file"(uuid, text) from public, anon;
grant execute on function "api"."confirm_ai_file"(uuid, text) to authenticated, service_role;

create or replace function "api"."get_ai_file"(file_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_file"($1) $$;
revoke execute on function "api"."get_ai_file"(uuid) from public, anon;
grant execute on function "api"."get_ai_file"(uuid) to authenticated, service_role;

create or replace function "api"."get_ai_file_by_path"(bucket text, path text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_file_by_path"($1, $2) $$;
revoke execute on function "api"."get_ai_file_by_path"(text, text) from public, anon;
grant execute on function "api"."get_ai_file_by_path"(text, text) to authenticated, service_role;

create or replace function "api"."list_ai_files"(chat_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_files"($1) $$;
revoke execute on function "api"."list_ai_files"(uuid) from public, anon;
grant execute on function "api"."list_ai_files"(uuid) to authenticated, service_role;

create or replace function "api"."delete_ai_file"(file_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_ai_file"($1) $$;
revoke execute on function "api"."delete_ai_file"(uuid) from public, anon;
grant execute on function "api"."delete_ai_file"(uuid) to authenticated, service_role;

create or replace function "api"."store_ai_file"(tenant uuid, owner uuid, filename text, media_type text, byte_size bigint, chat_id uuid default null, source text default 'generated', sha256 text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."store_ai_file"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text) to service_role;

create or replace function "api"."set_ai_provider_file"(file_id uuid, provider text, reference text, expires_at timestamptz default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_ai_provider_file"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_ai_provider_file"(uuid, text, text, timestamptz) from public, anon, authenticated;
grant execute on function "api"."set_ai_provider_file"(uuid, text, text, timestamptz) to service_role;

create or replace function "api"."get_ai_provider_file"(file_id uuid, provider text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_provider_file"($1, $2) $$;
revoke execute on function "api"."get_ai_provider_file"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."get_ai_provider_file"(uuid, text) to service_role;

create or replace function "api"."expiring_ai_provider_files"(horizon interval default '1 day', batch integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expiring_ai_provider_files"($1, $2) $$;
revoke execute on function "api"."expiring_ai_provider_files"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."expiring_ai_provider_files"(interval, integer) to service_role;

create or replace function "api"."purge_ai_files"(older_than interval default '1 day', batch integer default 500)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_ai_files"($1, $2) $$;
revoke execute on function "api"."purge_ai_files"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."purge_ai_files"(interval, integer) to service_role;

create or replace function "api"."create_ai_document"(tenant uuid, kind text, title text, content text default null, chat_id uuid default null, message_id text default null, owner uuid default null, storage_path text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_ai_document"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) from public, anon;
grant execute on function "api"."create_ai_document"(uuid, text, text, text, uuid, text, uuid, text) to authenticated, service_role;

create or replace function "api"."update_ai_document"(document_id uuid, content text default null, title text default null, message_id text default null, expected_version integer default null, storage_path text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_ai_document"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."update_ai_document"(uuid, text, text, text, integer, text) from public, anon;
grant execute on function "api"."update_ai_document"(uuid, text, text, text, integer, text) to authenticated, service_role;

create or replace function "api"."rollback_ai_document"(document_id uuid, version integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rollback_ai_document"($1, $2) $$;
revoke execute on function "api"."rollback_ai_document"(uuid, integer) from public, anon;
grant execute on function "api"."rollback_ai_document"(uuid, integer) to authenticated, service_role;

create or replace function "api"."get_ai_document"(document_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_ai_document"($1) $$;
revoke execute on function "api"."get_ai_document"(uuid) from public, anon;
grant execute on function "api"."get_ai_document"(uuid) to authenticated, service_role;

create or replace function "api"."list_ai_document_versions"(document_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_document_versions"($1) $$;
revoke execute on function "api"."list_ai_document_versions"(uuid) from public, anon;
grant execute on function "api"."list_ai_document_versions"(uuid) to authenticated, service_role;

create or replace function "api"."suggest_ai_document_edit"(document_id uuid, original_text text, suggested_text text, description text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."suggest_ai_document_edit"($1, $2, $3, $4) $$;
revoke execute on function "api"."suggest_ai_document_edit"(uuid, text, text, text) from public, anon;
grant execute on function "api"."suggest_ai_document_edit"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."list_ai_suggestions"(document_id uuid, open_only boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_suggestions"($1, $2) $$;
revoke execute on function "api"."list_ai_suggestions"(uuid, boolean) from public, anon;
grant execute on function "api"."list_ai_suggestions"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."resolve_ai_suggestion"(suggestion_id uuid, accepted boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_ai_suggestion"($1, $2) $$;
revoke execute on function "api"."resolve_ai_suggestion"(uuid, boolean) from public, anon;
grant execute on function "api"."resolve_ai_suggestion"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."delete_ai_document"(document_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_ai_document"($1) $$;
revoke execute on function "api"."delete_ai_document"(uuid) from public, anon;
grant execute on function "api"."delete_ai_document"(uuid) to authenticated, service_role;

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
