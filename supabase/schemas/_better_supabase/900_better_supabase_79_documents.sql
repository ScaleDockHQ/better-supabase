-- better-supabase module: documents (0.8.0)
-- @bs-module documents@1 managed
-- Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, and saved states through the versions module.
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
create table if not exists "better_supabase"."documents" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "name" text not null default 'body' check ("name" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "name")
);
create index if not exists "documents_tenant_idx" on "better_supabase"."documents" ("tenant_id", "updated_at" desc);
alter table "better_supabase"."documents" enable row level security;
revoke all on "better_supabase"."documents" from anon, authenticated;
grant select on "better_supabase"."documents" to authenticated;
grant all on "better_supabase"."documents" to service_role;
drop policy if exists "documents_read" on "better_supabase"."documents";
create policy "documents_read" on "better_supabase"."documents" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')));

create table if not exists "better_supabase"."document_updates" (
  "seq" bigint generated always as identity primary key,
  "document_id" uuid not null references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "payload" bytea not null,
  "actor" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "document_updates_document_idx" on "better_supabase"."document_updates" ("document_id", "seq");
alter table "better_supabase"."document_updates" enable row level security;
revoke all on "better_supabase"."document_updates" from anon, authenticated;
grant all on "better_supabase"."document_updates" to service_role;

create table if not exists "better_supabase"."document_snapshots" (
  "document_id" uuid primary key references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "state" bytea not null,
  "seq" bigint not null,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."document_snapshots" enable row level security;
revoke all on "better_supabase"."document_snapshots" from anon, authenticated;
grant all on "better_supabase"."document_snapshots" to service_role;

-- Whether the caller may read (or, with write, edit) a document. The
-- realtime policies call it with the id from the topic.
create or replace function "better_supabase"."document_access"(document_id uuid, write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = document_access.document_id;
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  if document_access.write then
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end and true);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end);
end;
$$;
revoke execute on function "better_supabase"."document_access"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."document_access"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."document_topic_access"(topic text, write boolean)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when document_topic_access.topic like 'documents:%'
      and substr(document_topic_access.topic, 11) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then "better_supabase"."document_access"(substr(document_topic_access.topic, 11)::uuid, document_topic_access.write)
    else false
  end
$$;
revoke execute on function "better_supabase"."document_topic_access"(text, boolean) from public, anon;
grant execute on function "better_supabase"."document_topic_access"(text, boolean) to authenticated, service_role;

-- The state to start from: the latest snapshot and the updates after it.
-- Creates the document on first open when the caller may edit it.
create or replace function "better_supabase"."open_document"(tenant uuid, subject_type text, subject_id text, name text default 'body')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
  v_write boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d
  where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
  if found and v_doc."tenant_id" <> open_document.tenant then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not found then
    v_doc."tenant_id" := open_document.tenant;
    v_doc."subject_type" := open_document.subject_type;
    v_doc."subject_id" := open_document.subject_id;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end and true)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end) then
        raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
      end if;
      raise exception 'not allowed to open this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name;
    end if;
  end;
    insert into "better_supabase"."documents" ("tenant_id", "subject_type", "subject_id", "name", "created_by")
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict ("subject_type", "subject_id", "name") do nothing
    returning * into v_doc;
    if found then
      perform better_supabase.audit_event(
    event_type => 'document.created',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name")
  );
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_doc."id";
    end if;
  end;
    else
      select * into v_doc from "better_supabase"."documents" d
      where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end and true);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'snapshot', case when v_snapshot."document_id" is null then null else replace(encode(v_snapshot."state", 'base64'), E'\n', '') end,
    'snapshotSeq', coalesce(v_snapshot."seq", 0),
    'updates', "better_supabase"."document_updates_after"(v_doc."id", coalesce(v_snapshot."seq", 0))
  );
end;
$$;
revoke execute on function "better_supabase"."open_document"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."open_document"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."document_updates_after"(document_id uuid, after_seq bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('seq', x."seq", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."seq"), '[]'::jsonb)
  from "better_supabase"."document_updates" x
  where x."document_id" = document_updates_after.document_id and x."seq" > document_updates_after.after_seq
$$;
revoke execute on function "better_supabase"."document_updates_after"(uuid, bigint) from public, anon, authenticated;

-- Appends a Yjs update (base64) and returns its sequence number. Past
-- options.compactAfter updates since the snapshot, enqueues documents.compact.
create or replace function "better_supabase"."push_document_update"(document_id uuid, payload text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_bytes bytea;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = push_document_update.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end and true)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(push_document_update.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_bytes, auth.uid())
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  return v_seq;
end;
$$;
revoke execute on function "better_supabase"."push_document_update"(uuid, text) from public, anon;
grant execute on function "better_supabase"."push_document_update"(uuid, text) to authenticated, service_role;

-- Updates after a sequence number, for a client that reconnects. When they
-- were compacted away, the snapshot comes back too.
create or replace function "better_supabase"."pull_document_updates"(document_id uuid, after_seq bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = pull_document_updates.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  if v_snapshot."document_id" is not null and pull_document_updates.after_seq < v_snapshot."seq" then
    return jsonb_build_object(
      'snapshot', replace(encode(v_snapshot."state", 'base64'), E'\n', ''),
      'snapshotSeq', v_snapshot."seq",
      'updates', "better_supabase"."document_updates_after"(v_doc."id", v_snapshot."seq")
    );
  end if;
  return jsonb_build_object('updates', "better_supabase"."document_updates_after"(v_doc."id", pull_document_updates.after_seq));
end;
$$;
revoke execute on function "better_supabase"."pull_document_updates"(uuid, bigint) from public, anon;
grant execute on function "better_supabase"."pull_document_updates"(uuid, bigint) to authenticated, service_role;

-- Stores the merged state of every update through a sequence number and
-- drops those updates. Yjs merges in JavaScript, so the compaction job (or
-- a manager) sends the state.
create or replace function "better_supabase"."compact_document"(document_id uuid, state text, through_seq bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_current bigint;
  v_last bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = compact_document.document_id for update;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.manage'), false)) then
    raise exception 'not allowed to compact this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  select x."seq" into v_current from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  select max(x."seq") into v_last from "better_supabase"."document_updates" x where x."document_id" = v_doc."id";
  if compact_document.through_seq <= coalesce(v_current, 0) then
    return false;
  end if;
  if v_last is null or compact_document.through_seq > v_last then
    raise exception 'through_seq is past the last update' using errcode = '22023', hint = 'DOCUMENT_COMPACT_INVALID';
  end if;
  insert into "better_supabase"."document_snapshots" ("document_id", "tenant_id", "state", "seq")
  values (v_doc."id", v_doc."tenant_id", decode(compact_document.state, 'base64'), compact_document.through_seq)
  on conflict ("document_id") do update
    set "state" = excluded."state", "seq" = excluded."seq", "created_at" = now();
  delete from "better_supabase"."document_updates" x where x."document_id" = v_doc."id" and x."seq" <= compact_document.through_seq;
  return true;
end;
$$;
revoke execute on function "better_supabase"."compact_document"(uuid, text, bigint) from public, anon;
grant execute on function "better_supabase"."compact_document"(uuid, text, bigint) to authenticated, service_role;

-- Documents with at least min_updates updates since their snapshot, for a
-- compaction sweep without the jobs module.
create or replace function "better_supabase"."documents_to_compact"(min_updates integer default 200, max_documents integer default 50)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(t.document_id), '{}'::uuid[]) from (
  select x."document_id" as document_id
  from "better_supabase"."document_updates" x
  left join "better_supabase"."document_snapshots" y on y."document_id" = x."document_id"
  where x."seq" > coalesce(y."seq", 0)
  group by x."document_id"
  having count(*) >= greatest(coalesce(documents_to_compact.min_updates, 1), 1)
  order by count(*) desc
  limit greatest(coalesce(documents_to_compact.max_documents, 50), 1)
  ) t
$$;
revoke execute on function "better_supabase"."documents_to_compact"(integer, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."documents_to_compact"(integer, integer) to service_role;

-- Saves the client's merged state as a version of subject 'document'.
create or replace function "better_supabase"."save_document_version"(document_id uuid, state text, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = save_document_version.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end and true)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  return "better_supabase"."version_insert"(v_doc."tenant_id", 'document', v_doc."id"::text,
    jsonb_build_object('state', save_document_version.state, 'name', v_doc."name"),
    null, nullif(trim(save_document_version.label), ''), 'manual', false, auth.uid());
end;
$$;
revoke execute on function "better_supabase"."save_document_version"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_document_version"(uuid, text, text) to authenticated, service_role;

create or replace function "better_supabase"."list_document_versions"(document_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_versions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."number" desc), '[]'::jsonb)
    from "better_supabase"."versions" x
    where x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text
  );
end;
$$;
revoke execute on function "better_supabase"."list_document_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."list_document_versions"(uuid) to authenticated, service_role;

-- A saved state, for a preview or for the client to restore from.
create or replace function "better_supabase"."get_document_version"(document_id uuid, version_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_state text;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = get_document_version.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select x."content" ->> 'state' into v_state from "better_supabase"."versions" x
  where x."id" = get_document_version.version_id
    and x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text;
  if v_state is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'DOCUMENT_VERSION_NOT_FOUND';
  end if;
  return v_state;
end;
$$;
revoke execute on function "better_supabase"."get_document_version"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."get_document_version"(uuid, uuid) to authenticated, service_role;

-- Readers join documents:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists "bs_documents_receive" on realtime.messages;
    create policy "bs_documents_receive" on realtime.messages for select to authenticated
      using (
        realtime.messages.extension in ('broadcast', 'presence')
        and "better_supabase"."document_topic_access"((select realtime.topic()), false)
      );
    drop policy if exists "bs_documents_send" on realtime.messages;
    create policy "bs_documents_send" on realtime.messages for insert to authenticated
      with check ((
        (realtime.messages.extension = 'broadcast' and "better_supabase"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "better_supabase"."document_topic_access"((select realtime.topic()), false))
      ) and (select better_supabase.actor_may_write()));
  end if;
end;
$do$;

-- blocks.documents.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."document_access"(document_id uuid, write boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_access"($1, $2) $$;
revoke execute on function "api"."document_access"(uuid, boolean) from public, anon;
grant execute on function "api"."document_access"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."document_topic_access"(topic text, write boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."document_topic_access"($1, $2) $$;
revoke execute on function "api"."document_topic_access"(text, boolean) from public, anon;
grant execute on function "api"."document_topic_access"(text, boolean) to authenticated, service_role;

create or replace function "api"."open_document"(tenant uuid, subject_type text, subject_id text, name text default 'body')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_document"($1, $2, $3, $4) $$;
revoke execute on function "api"."open_document"(uuid, text, text, text) from public, anon;
grant execute on function "api"."open_document"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."push_document_update"(document_id uuid, payload text)
returns bigint
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."push_document_update"($1, $2) $$;
revoke execute on function "api"."push_document_update"(uuid, text) from public, anon;
grant execute on function "api"."push_document_update"(uuid, text) to authenticated, service_role;

create or replace function "api"."pull_document_updates"(document_id uuid, after_seq bigint)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pull_document_updates"($1, $2) $$;
revoke execute on function "api"."pull_document_updates"(uuid, bigint) from public, anon;
grant execute on function "api"."pull_document_updates"(uuid, bigint) to authenticated, service_role;

create or replace function "api"."compact_document"(document_id uuid, state text, through_seq bigint)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."compact_document"($1, $2, $3) $$;
revoke execute on function "api"."compact_document"(uuid, text, bigint) from public, anon;
grant execute on function "api"."compact_document"(uuid, text, bigint) to authenticated, service_role;

create or replace function "api"."documents_to_compact"(min_updates integer default 200, max_documents integer default 50)
returns uuid[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."documents_to_compact"($1, $2) $$;
revoke execute on function "api"."documents_to_compact"(integer, integer) from public, anon, authenticated;
grant execute on function "api"."documents_to_compact"(integer, integer) to service_role;

create or replace function "api"."save_document_version"(document_id uuid, state text, label text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_document_version"($1, $2, $3) $$;
revoke execute on function "api"."save_document_version"(uuid, text, text) from public, anon;
grant execute on function "api"."save_document_version"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_document_versions"(document_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_document_versions"($1) $$;
revoke execute on function "api"."list_document_versions"(uuid) from public, anon;
grant execute on function "api"."list_document_versions"(uuid) to authenticated, service_role;

create or replace function "api"."get_document_version"(document_id uuid, version_id uuid)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_document_version"($1, $2) $$;
revoke execute on function "api"."get_document_version"(uuid, uuid) from public, anon;
grant execute on function "api"."get_document_version"(uuid, uuid) to authenticated, service_role;

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
