-- ==== alone: schema supabase/schemas/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block documents@1 managed
-- @bsb-hash sha256:c29e6fb9df3a8a3f90d33f3c746dd0bcca369a8ce2064d6d5605e875b2fd3eb3
-- Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, suggestions that editors accept into the log, and named versions through the versions module.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_updates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_snapshots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_suggestions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."documents" from public, anon, authenticated;
grant select on "better_supabase"."documents" to authenticated;
grant all on "better_supabase"."documents" to service_role;
drop policy if exists documents_read on "better_supabase"."documents";
create policy documents_read on "better_supabase"."documents"
  for select to authenticated
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
revoke all on "better_supabase"."document_updates" from public, anon, authenticated;
grant all on "better_supabase"."document_updates" to service_role;

create table if not exists "better_supabase"."document_snapshots" (
  "document_id" uuid primary key references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "state" bytea not null,
  "seq" bigint not null,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."document_snapshots" enable row level security;
revoke all on "better_supabase"."document_snapshots" from public, anon, authenticated;
grant all on "better_supabase"."document_snapshots" to service_role;

create table if not exists "better_supabase"."document_suggestions" (
  "id" uuid primary key default gen_random_uuid(),
  "document_id" uuid not null references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "payload" bytea not null,
  "summary" text check (length("summary") between 1 and 500),
  "status" text not null default 'open' check ("status" in ('open', 'accepted', 'rejected', 'withdrawn')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "note" text check (length("note") between 1 and 500)
);
create index if not exists "document_suggestions_document_idx" on "better_supabase"."document_suggestions" ("document_id", "status", "created_at");
alter table "better_supabase"."document_suggestions" enable row level security;
revoke all on "better_supabase"."document_suggestions" from public, anon, authenticated;
grant all on "better_supabase"."document_suggestions" to service_role;

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
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true);
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) then
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
      null;
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
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'canSuggest', v_write or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)),
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
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
    null;
  end if;
  return v_seq;
end;
$$;
revoke execute on function "better_supabase"."push_document_update"(uuid, text) from public, anon;
grant execute on function "better_supabase"."push_document_update"(uuid, text) to authenticated, service_role;

-- Stores a Yjs update (base64) as a suggestion instead of appending it.
-- Editors and readers with the suggest permission can suggest.
create or replace function "better_supabase"."suggest_document_change"(document_id uuid, payload text, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_bytes bytea;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = suggest_document_change.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true) or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)))) then
    raise exception 'not allowed to suggest changes to this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(suggest_document_change.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_suggestions" ("document_id", "tenant_id", "payload", "summary", "status", "created_by")
  values (v_doc."id", v_doc."tenant_id", v_bytes, nullif(trim(suggest_document_change.summary), ''), 'open', auth.uid())
  returning * into v_suggestion;
  null;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', ''));
end;
$$;
revoke execute on function "better_supabase"."suggest_document_change"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."suggest_document_change"(uuid, text, text) to authenticated, service_role;

-- Suggestions on a document, oldest first; status 'all' lists every one.
create or replace function "better_supabase"."list_document_suggestions"(document_id uuid, status text default 'open')
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
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_suggestions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'documentId', x."document_id", 'summary', x."summary", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'note', x."note", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."created_at", x."id"), '[]'::jsonb)
    from "better_supabase"."document_suggestions" x
    where x."document_id" = v_doc."id"
      and (coalesce(list_document_suggestions.status, 'all') = 'all' or x."status"::text = list_document_suggestions.status)
  );
end;
$$;
revoke execute on function "better_supabase"."list_document_suggestions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_document_suggestions"(uuid, text) to authenticated, service_role;

-- Accepting appends the suggestion to the update log with its author as the
-- actor and returns the sequence number as 'seq'. Editors accept or reject;
-- the author withdraws.
create or replace function "better_supabase"."decide_document_suggestion"(suggestion_id uuid, decision text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "better_supabase"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) or v_suggestion."created_by" = auth.uid()) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_suggestion."created_by" = auth.uid()) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = '55000', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    null;
  end if;
  end if;
  update "better_supabase"."document_suggestions" x
    set "status" = decide_document_suggestion.decision, "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    null;
  elsif v_suggestion."status" = 'rejected' then
    null;
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$$;
revoke execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) to authenticated, service_role;

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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
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
-- compaction sweep without the queue block.
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

-- Readers join documents:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_documents_receive on realtime.messages;
create policy bsb_documents_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and "better_supabase"."document_topic_access"((select realtime.topic()), false));
        drop policy if exists bsb_documents_send on realtime.messages;
create policy bsb_documents_send on realtime.messages
  for insert to authenticated
  with check (((realtime.messages.extension = 'broadcast' and "better_supabase"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "better_supabase"."document_topic_access"((select realtime.topic()), false))) and (select better_supabase.actor_may_write()));
  end if;
end;
$do$;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
create policy bsb_tenant_scope_select on "better_supabase"."documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
create policy bsb_tenant_scope_insert on "better_supabase"."documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
create policy bsb_tenant_scope_update on "better_supabase"."documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
create policy bsb_tenant_scope_delete on "better_supabase"."documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:a3907dcc75373f668c797d067d33e3661c05843c1b0474a550c3b0e322cbe981
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block documents@1 managed
-- @bsb-hash sha256:adfc643ab644cf11a03cc3f39f86d37b152d580ea89ecef98efd35696f693e25
-- Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, suggestions that editors accept into the log, and named versions through the versions module.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_updates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_snapshots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_suggestions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."documents" from public, anon, authenticated;
grant select on "better_supabase"."documents" to authenticated;
grant all on "better_supabase"."documents" to service_role;
drop policy if exists documents_read on "better_supabase"."documents";
create policy documents_read on "better_supabase"."documents"
  for select to authenticated
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
revoke all on "better_supabase"."document_updates" from public, anon, authenticated;
grant all on "better_supabase"."document_updates" to service_role;

create table if not exists "better_supabase"."document_snapshots" (
  "document_id" uuid primary key references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "state" bytea not null,
  "seq" bigint not null,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."document_snapshots" enable row level security;
revoke all on "better_supabase"."document_snapshots" from public, anon, authenticated;
grant all on "better_supabase"."document_snapshots" to service_role;

create table if not exists "better_supabase"."document_suggestions" (
  "id" uuid primary key default gen_random_uuid(),
  "document_id" uuid not null references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "payload" bytea not null,
  "summary" text check (length("summary") between 1 and 500),
  "status" text not null default 'open' check ("status" in ('open', 'accepted', 'rejected', 'withdrawn')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "note" text check (length("note") between 1 and 500)
);
create index if not exists "document_suggestions_document_idx" on "better_supabase"."document_suggestions" ("document_id", "status", "created_at");
alter table "better_supabase"."document_suggestions" enable row level security;
revoke all on "better_supabase"."document_suggestions" from public, anon, authenticated;
grant all on "better_supabase"."document_suggestions" to service_role;

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
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true);
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) then
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
      perform "better_supabase".emit_event('document.created', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
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
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'canSuggest', v_write or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)),
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
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

-- Stores a Yjs update (base64) as a suggestion instead of appending it.
-- Editors and readers with the suggest permission can suggest.
create or replace function "better_supabase"."suggest_document_change"(document_id uuid, payload text, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_bytes bytea;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = suggest_document_change.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true) or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)))) then
    raise exception 'not allowed to suggest changes to this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(suggest_document_change.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_suggestions" ("document_id", "tenant_id", "payload", "summary", "status", "created_by")
  values (v_doc."id", v_doc."tenant_id", v_bytes, nullif(trim(suggest_document_change.summary), ''), 'open', auth.uid())
  returning * into v_suggestion;
  perform "better_supabase".emit_event('document.suggested', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', ''));
end;
$$;
revoke execute on function "better_supabase"."suggest_document_change"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."suggest_document_change"(uuid, text, text) to authenticated, service_role;

-- Suggestions on a document, oldest first; status 'all' lists every one.
create or replace function "better_supabase"."list_document_suggestions"(document_id uuid, status text default 'open')
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
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_suggestions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'documentId', x."document_id", 'summary', x."summary", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'note', x."note", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."created_at", x."id"), '[]'::jsonb)
    from "better_supabase"."document_suggestions" x
    where x."document_id" = v_doc."id"
      and (coalesce(list_document_suggestions.status, 'all') = 'all' or x."status"::text = list_document_suggestions.status)
  );
end;
$$;
revoke execute on function "better_supabase"."list_document_suggestions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_document_suggestions"(uuid, text) to authenticated, service_role;

-- Accepting appends the suggestion to the update log with its author as the
-- actor and returns the sequence number as 'seq'. Editors accept or reject;
-- the author withdraws.
create or replace function "better_supabase"."decide_document_suggestion"(suggestion_id uuid, decision text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "better_supabase"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) or v_suggestion."created_by" = auth.uid()) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_suggestion."created_by" = auth.uid()) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = '55000', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  end if;
  update "better_supabase"."document_suggestions" x
    set "status" = decide_document_suggestion.decision, "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    perform "better_supabase".emit_event('document.suggestion_accepted', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.suggestion_accepted',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status")
  );
  elsif v_suggestion."status" = 'rejected' then
    perform "better_supabase".emit_event('document.suggestion_rejected', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.suggestion_rejected',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status")
  );
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$$;
revoke execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) to authenticated, service_role;

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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
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
-- compaction sweep without the queue block.
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."number" desc), '[]'::jsonb)
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
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

-- Names a version, which keeps it out of retention; a null or blank label
-- removes the name. Editors of the document can name its versions.
create or replace function "better_supabase"."name_document_version"(document_id uuid, version_id uuid, label text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_frozen boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = name_document_version.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
    raise exception 'not allowed to name versions of this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  select x."frozen" into v_frozen from "better_supabase"."versions" x
  where x."id" = name_document_version.version_id
    and x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text
  for update;
  if v_frozen is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'DOCUMENT_VERSION_NOT_FOUND';
  end if;
  if v_frozen then
    raise exception 'a frozen version keeps its name' using errcode = '55000', hint = 'DOCUMENT_VERSION_FROZEN';
  end if;
  update "better_supabase"."versions" x set "label" = nullif(trim(name_document_version.label), '')
  where x."id" = name_document_version.version_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."name_document_version"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."name_document_version"(uuid, uuid, text) to authenticated, service_role;

-- Readers join documents:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_documents_receive on realtime.messages;
create policy bsb_documents_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and "better_supabase"."document_topic_access"((select realtime.topic()), false));
        drop policy if exists bsb_documents_send on realtime.messages;
create policy bsb_documents_send on realtime.messages
  for insert to authenticated
  with check (((realtime.messages.extension = 'broadcast' and "better_supabase"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "better_supabase"."document_topic_access"((select realtime.topic()), false))) and (select better_supabase.actor_may_write()));
  end if;
end;
$do$;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
create policy bsb_tenant_scope_select on "better_supabase"."documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
create policy bsb_tenant_scope_insert on "better_supabase"."documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
create policy bsb_tenant_scope_update on "better_supabase"."documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
create policy bsb_tenant_scope_delete on "better_supabase"."documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:a3907dcc75373f668c797d067d33e3661c05843c1b0474a550c3b0e322cbe981
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block documents@1 managed
-- @bsb-hash sha256:06a351aab56d898cbb224764352a716b17b57c341f93659838edeb4c084335b0
-- Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, suggestions that editors accept into the log, and named versions through the versions module.
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
    drop policy if exists bsb_tenant_scope on "app_private"."documents";
    drop policy if exists bsb_tenant_scope_select on "app_private"."documents";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."documents";
    drop policy if exists bsb_tenant_scope_update on "app_private"."documents";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."document_updates";
    drop policy if exists bsb_tenant_scope_select on "app_private"."document_updates";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."document_updates";
    drop policy if exists bsb_tenant_scope_update on "app_private"."document_updates";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."document_updates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."document_snapshots";
    drop policy if exists bsb_tenant_scope_select on "app_private"."document_snapshots";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."document_snapshots";
    drop policy if exists bsb_tenant_scope_update on "app_private"."document_snapshots";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."document_snapshots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."document_suggestions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."document_suggestions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."document_suggestions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."document_suggestions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."document_suggestions";
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
create table if not exists "app_private"."documents" (
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
create index if not exists "documents_tenant_idx" on "app_private"."documents" ("tenant_id", "updated_at" desc);
alter table "app_private"."documents" enable row level security;
revoke all on "app_private"."documents" from public, anon, authenticated;
grant select on "app_private"."documents" to authenticated;
grant all on "app_private"."documents" to service_role;
drop policy if exists documents_read on "app_private"."documents";
create policy documents_read on "app_private"."documents"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')));

create table if not exists "app_private"."document_updates" (
  "seq" bigint generated always as identity primary key,
  "document_id" uuid not null references "app_private"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "payload" bytea not null,
  "actor" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "document_updates_document_idx" on "app_private"."document_updates" ("document_id", "seq");
alter table "app_private"."document_updates" enable row level security;
revoke all on "app_private"."document_updates" from public, anon, authenticated;
grant all on "app_private"."document_updates" to service_role;

create table if not exists "app_private"."document_snapshots" (
  "document_id" uuid primary key references "app_private"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "state" bytea not null,
  "seq" bigint not null,
  "created_at" timestamptz not null default now()
);
alter table "app_private"."document_snapshots" enable row level security;
revoke all on "app_private"."document_snapshots" from public, anon, authenticated;
grant all on "app_private"."document_snapshots" to service_role;

create table if not exists "app_private"."document_suggestions" (
  "id" uuid primary key default gen_random_uuid(),
  "document_id" uuid not null references "app_private"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "payload" bytea not null,
  "summary" text check (length("summary") between 1 and 500),
  "status" text not null default 'open' check ("status" in ('open', 'accepted', 'rejected', 'withdrawn')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "note" text check (length("note") between 1 and 500)
);
create index if not exists "document_suggestions_document_idx" on "app_private"."document_suggestions" ("document_id", "status", "created_at");
alter table "app_private"."document_suggestions" enable row level security;
revoke all on "app_private"."document_suggestions" from public, anon, authenticated;
grant all on "app_private"."document_suggestions" to service_role;

-- Whether the caller may read (or, with write, edit) a document. The
-- realtime policies call it with the id from the topic.
create or replace function "app_private"."document_access"(document_id uuid, write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
begin
  select * into v_doc from "app_private"."documents" d where d."id" = document_access.document_id;
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  if document_access.write then
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true);
end;
$$;
revoke execute on function "app_private"."document_access"(uuid, boolean) from public, anon;
grant execute on function "app_private"."document_access"(uuid, boolean) to authenticated, service_role;

create or replace function "app_private"."document_topic_access"(topic text, write boolean)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when document_topic_access.topic like 'documents:%'
      and substr(document_topic_access.topic, 11) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then "app_private"."document_access"(substr(document_topic_access.topic, 11)::uuid, document_topic_access.write)
    else false
  end
$$;
revoke execute on function "app_private"."document_topic_access"(text, boolean) from public, anon;
grant execute on function "app_private"."document_topic_access"(text, boolean) to authenticated, service_role;

-- The state to start from: the latest snapshot and the updates after it.
-- Creates the document on first open when the caller may edit it.
create or replace function "app_private"."open_document"(tenant uuid, subject_type text, subject_id text, name text default 'body')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
  v_snapshot "app_private"."document_snapshots"%rowtype;
  v_write boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "app_private"."documents" d
  where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
  if found and v_doc."tenant_id" <> open_document.tenant then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not found then
    v_doc."tenant_id" := open_document.tenant;
    v_doc."subject_type" := open_document.subject_type;
    v_doc."subject_id" := open_document.subject_id;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) then
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
    insert into "app_private"."documents" ("tenant_id", "subject_type", "subject_id", "name", "created_by")
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict ("subject_type", "subject_id", "name") do nothing
    returning * into v_doc;
    if found then
      null;
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_doc."id";
    end if;
  end;
    else
      select * into v_doc from "app_private"."documents" d
      where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  select * into v_snapshot from "app_private"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'canSuggest', v_write or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)),
    'snapshot', case when v_snapshot."document_id" is null then null else replace(encode(v_snapshot."state", 'base64'), E'\n', '') end,
    'snapshotSeq', coalesce(v_snapshot."seq", 0),
    'updates', "app_private"."document_updates_after"(v_doc."id", coalesce(v_snapshot."seq", 0))
  );
end;
$$;
revoke execute on function "app_private"."open_document"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."open_document"(uuid, text, text, text) to authenticated, service_role;

create or replace function "app_private"."document_updates_after"(document_id uuid, after_seq bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('seq', x."seq", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."seq"), '[]'::jsonb)
  from "app_private"."document_updates" x
  where x."document_id" = document_updates_after.document_id and x."seq" > document_updates_after.after_seq
$$;
revoke execute on function "app_private"."document_updates_after"(uuid, bigint) from public, anon, authenticated;

-- Appends a Yjs update (base64) and returns its sequence number. Past
-- options.compactAfter updates since the snapshot, enqueues documents.compact.
create or replace function "app_private"."push_document_update"(document_id uuid, payload text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
  v_bytes bytea;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "app_private"."documents" d where d."id" = push_document_update.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
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
  insert into "app_private"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_bytes, auth.uid())
  returning "seq" into v_seq;
  update "app_private"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "app_private"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "app_private"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    null;
  end if;
  return v_seq;
end;
$$;
revoke execute on function "app_private"."push_document_update"(uuid, text) from public, anon;
grant execute on function "app_private"."push_document_update"(uuid, text) to authenticated, service_role;

-- Stores a Yjs update (base64) as a suggestion instead of appending it.
-- Editors and readers with the suggest permission can suggest.
create or replace function "app_private"."suggest_document_change"(document_id uuid, payload text, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
  v_suggestion "app_private"."document_suggestions"%rowtype;
  v_bytes bytea;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "app_private"."documents" d where d."id" = suggest_document_change.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true) or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)))) then
    raise exception 'not allowed to suggest changes to this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(suggest_document_change.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "app_private"."document_suggestions" ("document_id", "tenant_id", "payload", "summary", "status", "created_by")
  values (v_doc."id", v_doc."tenant_id", v_bytes, nullif(trim(suggest_document_change.summary), ''), 'open', auth.uid())
  returning * into v_suggestion;
  null;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', ''));
end;
$$;
revoke execute on function "app_private"."suggest_document_change"(uuid, text, text) from public, anon;
grant execute on function "app_private"."suggest_document_change"(uuid, text, text) to authenticated, service_role;

-- Suggestions on a document, oldest first; status 'all' lists every one.
create or replace function "app_private"."list_document_suggestions"(document_id uuid, status text default 'open')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
begin
  select * into v_doc from "app_private"."documents" d where d."id" = list_document_suggestions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'documentId', x."document_id", 'summary', x."summary", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'note', x."note", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."created_at", x."id"), '[]'::jsonb)
    from "app_private"."document_suggestions" x
    where x."document_id" = v_doc."id"
      and (coalesce(list_document_suggestions.status, 'all') = 'all' or x."status"::text = list_document_suggestions.status)
  );
end;
$$;
revoke execute on function "app_private"."list_document_suggestions"(uuid, text) from public, anon;
grant execute on function "app_private"."list_document_suggestions"(uuid, text) to authenticated, service_role;

-- Accepting appends the suggestion to the update log with its author as the
-- actor and returns the sequence number as 'seq'. Editors accept or reject;
-- the author withdraws.
create or replace function "app_private"."decide_document_suggestion"(suggestion_id uuid, decision text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
  v_suggestion "app_private"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "app_private"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "app_private"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) or v_suggestion."created_by" = auth.uid()) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_suggestion."created_by" = auth.uid()) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = '55000', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "app_private"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "app_private"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "app_private"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "app_private"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    null;
  end if;
  end if;
  update "app_private"."document_suggestions" x
    set "status" = decide_document_suggestion.decision, "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    null;
  elsif v_suggestion."status" = 'rejected' then
    null;
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$$;
revoke execute on function "app_private"."decide_document_suggestion"(uuid, text, text) from public, anon;
grant execute on function "app_private"."decide_document_suggestion"(uuid, text, text) to authenticated, service_role;

-- Updates after a sequence number, for a client that reconnects. When they
-- were compacted away, the snapshot comes back too.
create or replace function "app_private"."pull_document_updates"(document_id uuid, after_seq bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
  v_snapshot "app_private"."document_snapshots"%rowtype;
begin
  select * into v_doc from "app_private"."documents" d where d."id" = pull_document_updates.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select * into v_snapshot from "app_private"."document_snapshots" x where x."document_id" = v_doc."id";
  if v_snapshot."document_id" is not null and pull_document_updates.after_seq < v_snapshot."seq" then
    return jsonb_build_object(
      'snapshot', replace(encode(v_snapshot."state", 'base64'), E'\n', ''),
      'snapshotSeq', v_snapshot."seq",
      'updates', "app_private"."document_updates_after"(v_doc."id", v_snapshot."seq")
    );
  end if;
  return jsonb_build_object('updates', "app_private"."document_updates_after"(v_doc."id", pull_document_updates.after_seq));
end;
$$;
revoke execute on function "app_private"."pull_document_updates"(uuid, bigint) from public, anon;
grant execute on function "app_private"."pull_document_updates"(uuid, bigint) to authenticated, service_role;

-- Stores the merged state of every update through a sequence number and
-- drops those updates. Yjs merges in JavaScript, so the compaction job (or
-- a manager) sends the state.
create or replace function "app_private"."compact_document"(document_id uuid, state text, through_seq bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "app_private"."documents"%rowtype;
  v_current bigint;
  v_last bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "app_private"."documents" d where d."id" = compact_document.document_id for update;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.manage'), false)) then
    raise exception 'not allowed to compact this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  select x."seq" into v_current from "app_private"."document_snapshots" x where x."document_id" = v_doc."id";
  select max(x."seq") into v_last from "app_private"."document_updates" x where x."document_id" = v_doc."id";
  if compact_document.through_seq <= coalesce(v_current, 0) then
    return false;
  end if;
  if v_last is null or compact_document.through_seq > v_last then
    raise exception 'through_seq is past the last update' using errcode = '22023', hint = 'DOCUMENT_COMPACT_INVALID';
  end if;
  insert into "app_private"."document_snapshots" ("document_id", "tenant_id", "state", "seq")
  values (v_doc."id", v_doc."tenant_id", decode(compact_document.state, 'base64'), compact_document.through_seq)
  on conflict ("document_id") do update
    set "state" = excluded."state", "seq" = excluded."seq", "created_at" = now();
  delete from "app_private"."document_updates" x where x."document_id" = v_doc."id" and x."seq" <= compact_document.through_seq;
  return true;
end;
$$;
revoke execute on function "app_private"."compact_document"(uuid, text, bigint) from public, anon;
grant execute on function "app_private"."compact_document"(uuid, text, bigint) to authenticated, service_role;

-- Documents with at least min_updates updates since their snapshot, for a
-- compaction sweep without the queue block.
create or replace function "app_private"."documents_to_compact"(min_updates integer default 200, max_documents integer default 50)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(t.document_id), '{}'::uuid[]) from (
  select x."document_id" as document_id
  from "app_private"."document_updates" x
  left join "app_private"."document_snapshots" y on y."document_id" = x."document_id"
  where x."seq" > coalesce(y."seq", 0)
  group by x."document_id"
  having count(*) >= greatest(coalesce(documents_to_compact.min_updates, 1), 1)
  order by count(*) desc
  limit greatest(coalesce(documents_to_compact.max_documents, 50), 1)
  ) t
$$;
revoke execute on function "app_private"."documents_to_compact"(integer, integer) from public, anon, authenticated;
grant execute on function "app_private"."documents_to_compact"(integer, integer) to service_role;

-- Readers join documents:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_documents_receive on realtime.messages;
create policy bsb_documents_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and "app_private"."document_topic_access"((select realtime.topic()), false));
        drop policy if exists bsb_documents_send on realtime.messages;
create policy bsb_documents_send on realtime.messages
  for insert to authenticated
  with check (((realtime.messages.extension = 'broadcast' and "app_private"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "app_private"."document_topic_access"((select realtime.topic()), false))) and (select better_supabase.actor_may_write()));
  end if;
end;
$do$;

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
drop policy if exists bsb_tenant_scope on "app_private"."documents";
drop policy if exists bsb_tenant_scope_select on "app_private"."documents";
create policy bsb_tenant_scope_select on "app_private"."documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."documents";
create policy bsb_tenant_scope_insert on "app_private"."documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."documents";
create policy bsb_tenant_scope_update on "app_private"."documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."documents";
create policy bsb_tenant_scope_delete on "app_private"."documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:a3907dcc75373f668c797d067d33e3661c05843c1b0474a550c3b0e322cbe981
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block documents@1 managed
-- @bsb-hash sha256:56c6448e87c4b3ba406c30072e69f7dc560ea2ed188ef5ddede3e94b82e04893
-- Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, suggestions that editors accept into the log, and named versions through the versions module.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_updates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_snapshots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_suggestions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."documents" from public, anon, authenticated;
grant select on "better_supabase"."documents" to authenticated;
grant all on "better_supabase"."documents" to service_role;
drop policy if exists documents_read on "better_supabase"."documents";
create policy documents_read on "better_supabase"."documents"
  for select to authenticated
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
revoke all on "better_supabase"."document_updates" from public, anon, authenticated;
grant all on "better_supabase"."document_updates" to service_role;

create table if not exists "better_supabase"."document_snapshots" (
  "document_id" uuid primary key references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "state" bytea not null,
  "seq" bigint not null,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."document_snapshots" enable row level security;
revoke all on "better_supabase"."document_snapshots" from public, anon, authenticated;
grant all on "better_supabase"."document_snapshots" to service_role;

create table if not exists "better_supabase"."document_suggestions" (
  "id" uuid primary key default gen_random_uuid(),
  "document_id" uuid not null references "better_supabase"."documents" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "payload" bytea not null,
  "summary" text check (length("summary") between 1 and 500),
  "status" text not null default 'open' check ("status" in ('open', 'accepted', 'rejected', 'withdrawn')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "note" text check (length("note") between 1 and 500)
);
create index if not exists "document_suggestions_document_idx" on "better_supabase"."document_suggestions" ("document_id", "status", "created_at");
alter table "better_supabase"."document_suggestions" enable row level security;
revoke all on "better_supabase"."document_suggestions" from public, anon, authenticated;
grant all on "better_supabase"."document_suggestions" to service_role;

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
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true);
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) then
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
      null;
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
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'canSuggest', v_write or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)),
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
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
    null;
  end if;
  return v_seq;
end;
$$;
revoke execute on function "better_supabase"."push_document_update"(uuid, text) from public, anon;
grant execute on function "better_supabase"."push_document_update"(uuid, text) to authenticated, service_role;

-- Stores a Yjs update (base64) as a suggestion instead of appending it.
-- Editors and readers with the suggest permission can suggest.
create or replace function "better_supabase"."suggest_document_change"(document_id uuid, payload text, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_bytes bytea;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = suggest_document_change.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true) or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)))) then
    raise exception 'not allowed to suggest changes to this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(suggest_document_change.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_suggestions" ("document_id", "tenant_id", "payload", "summary", "status", "created_by")
  values (v_doc."id", v_doc."tenant_id", v_bytes, nullif(trim(suggest_document_change.summary), ''), 'open', auth.uid())
  returning * into v_suggestion;
  null;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', ''));
end;
$$;
revoke execute on function "better_supabase"."suggest_document_change"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."suggest_document_change"(uuid, text, text) to authenticated, service_role;

-- Suggestions on a document, oldest first; status 'all' lists every one.
create or replace function "better_supabase"."list_document_suggestions"(document_id uuid, status text default 'open')
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
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_suggestions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'documentId', x."document_id", 'summary', x."summary", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'note', x."note", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."created_at", x."id"), '[]'::jsonb)
    from "better_supabase"."document_suggestions" x
    where x."document_id" = v_doc."id"
      and (coalesce(list_document_suggestions.status, 'all') = 'all' or x."status"::text = list_document_suggestions.status)
  );
end;
$$;
revoke execute on function "better_supabase"."list_document_suggestions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_document_suggestions"(uuid, text) to authenticated, service_role;

-- Accepting appends the suggestion to the update log with its author as the
-- actor and returns the sequence number as 'seq'. Editors accept or reject;
-- the author withdraws.
create or replace function "better_supabase"."decide_document_suggestion"(suggestion_id uuid, decision text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "better_supabase"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) or v_suggestion."created_by" = auth.uid()) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_suggestion."created_by" = auth.uid()) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = '55000', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    null;
  end if;
  end if;
  update "better_supabase"."document_suggestions" x
    set "status" = decide_document_suggestion.decision, "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    null;
  elsif v_suggestion."status" = 'rejected' then
    null;
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$$;
revoke execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) to authenticated, service_role;

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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
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
-- compaction sweep without the queue block.
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

-- Readers join documents:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_documents_receive on realtime.messages;
create policy bsb_documents_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and "better_supabase"."document_topic_access"((select realtime.topic()), false));
        drop policy if exists bsb_documents_send on realtime.messages;
create policy bsb_documents_send on realtime.messages
  for insert to authenticated
  with check (((realtime.messages.extension = 'broadcast' and "better_supabase"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "better_supabase"."document_topic_access"((select realtime.topic()), false))) and (select better_supabase.actor_may_write()));
  end if;
end;
$do$;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
create policy bsb_tenant_scope_select on "better_supabase"."documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
create policy bsb_tenant_scope_insert on "better_supabase"."documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
create policy bsb_tenant_scope_update on "better_supabase"."documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
create policy bsb_tenant_scope_delete on "better_supabase"."documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

create or replace function "api"."suggest_document_change"(document_id uuid, payload text, summary text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."suggest_document_change"($1, $2, $3) $$;
revoke execute on function "api"."suggest_document_change"(uuid, text, text) from public, anon;
grant execute on function "api"."suggest_document_change"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_document_suggestions"(document_id uuid, status text default 'open')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_document_suggestions"($1, $2) $$;
revoke execute on function "api"."list_document_suggestions"(uuid, text) from public, anon;
grant execute on function "api"."list_document_suggestions"(uuid, text) to authenticated, service_role;

create or replace function "api"."decide_document_suggestion"(suggestion_id uuid, decision text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_document_suggestion"($1, $2, $3) $$;
revoke execute on function "api"."decide_document_suggestion"(uuid, text, text) from public, anon;
grant execute on function "api"."decide_document_suggestion"(uuid, text, text) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:a3907dcc75373f668c797d067d33e3661c05843c1b0474a550c3b0e322cbe981
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block documents@1 managed
-- @bsb-hash sha256:7788c441a35bd521e06a54e88af5cafc8d1a222f08ed35c5e9c2683bd5aa1792
-- Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, suggestions that editors accept into the log, and named versions through the versions module.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_updates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_snapshots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_suggestions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.documents is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."documents" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."documents" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."documents" add column if not exists "subject_type" text;
alter table "better_supabase"."documents" add column if not exists "subject_id" text;
alter table "better_supabase"."documents" add column if not exists "name" text not null default 'body' check ("name" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."documents" add column if not exists "created_by" uuid;
alter table "better_supabase"."documents" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."documents" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_documents_subject_key" on "better_supabase"."documents" ("subject_type", "subject_id", "name");
create index if not exists "documents_tenant_idx" on "better_supabase"."documents" ("tenant_id", "updated_at" desc);
alter table "better_supabase"."documents" enable row level security;
grant select on "better_supabase"."documents" to authenticated;
grant all on "better_supabase"."documents" to service_role;
drop policy if exists bsb_documents_select on "better_supabase"."documents";
create policy bsb_documents_select on "better_supabase"."documents"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')));

-- better_supabase.document_updates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."document_updates" add column if not exists "seq" bigint generated always as identity;
alter table "better_supabase"."document_updates" add column if not exists "document_id" uuid references "better_supabase"."documents" ("id") on delete cascade;
alter table "better_supabase"."document_updates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."document_updates" add column if not exists "payload" bytea;
alter table "better_supabase"."document_updates" add column if not exists "actor" uuid;
alter table "better_supabase"."document_updates" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "document_updates_document_idx" on "better_supabase"."document_updates" ("document_id", "seq");
alter table "better_supabase"."document_updates" enable row level security;
grant all on "better_supabase"."document_updates" to service_role;

-- better_supabase.document_snapshots is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."document_snapshots" add column if not exists "document_id" uuid references "better_supabase"."documents" ("id") on delete cascade;
alter table "better_supabase"."document_snapshots" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."document_snapshots" add column if not exists "state" bytea;
alter table "better_supabase"."document_snapshots" add column if not exists "seq" bigint;
alter table "better_supabase"."document_snapshots" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_document_snapshots_document_key" on "better_supabase"."document_snapshots" ("document_id");
alter table "better_supabase"."document_snapshots" enable row level security;
grant all on "better_supabase"."document_snapshots" to service_role;

-- better_supabase.document_suggestions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."document_suggestions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."document_suggestions" add column if not exists "document_id" uuid references "better_supabase"."documents" ("id") on delete cascade;
alter table "better_supabase"."document_suggestions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."document_suggestions" add column if not exists "payload" bytea;
alter table "better_supabase"."document_suggestions" add column if not exists "summary" text check (length("summary") between 1 and 500);
alter table "better_supabase"."document_suggestions" add column if not exists "status" text not null default 'open' check ("status" in ('open', 'accepted', 'rejected', 'withdrawn'));
alter table "better_supabase"."document_suggestions" add column if not exists "created_by" uuid;
alter table "better_supabase"."document_suggestions" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."document_suggestions" add column if not exists "decided_by" uuid;
alter table "better_supabase"."document_suggestions" add column if not exists "decided_at" timestamptz;
alter table "better_supabase"."document_suggestions" add column if not exists "note" text check (length("note") between 1 and 500);
create index if not exists "document_suggestions_document_idx" on "better_supabase"."document_suggestions" ("document_id", "status", "created_at");
alter table "better_supabase"."document_suggestions" enable row level security;
grant all on "better_supabase"."document_suggestions" to service_role;

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
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true);
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) then
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
      null;
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
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'canSuggest', v_write or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)),
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
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
    null;
  end if;
  return v_seq;
end;
$$;
revoke execute on function "better_supabase"."push_document_update"(uuid, text) from public, anon;
grant execute on function "better_supabase"."push_document_update"(uuid, text) to authenticated, service_role;

-- Stores a Yjs update (base64) as a suggestion instead of appending it.
-- Editors and readers with the suggest permission can suggest.
create or replace function "better_supabase"."suggest_document_change"(document_id uuid, payload text, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_bytes bytea;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = suggest_document_change.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true) or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)))) then
    raise exception 'not allowed to suggest changes to this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(suggest_document_change.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_suggestions" ("document_id", "tenant_id", "payload", "summary", "status", "created_by")
  values (v_doc."id", v_doc."tenant_id", v_bytes, nullif(trim(suggest_document_change.summary), ''), better_supabase.as_column_type('open', (null::"better_supabase"."document_suggestions")."status"), auth.uid())
  returning * into v_suggestion;
  null;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', ''));
end;
$$;
revoke execute on function "better_supabase"."suggest_document_change"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."suggest_document_change"(uuid, text, text) to authenticated, service_role;

-- Suggestions on a document, oldest first; status 'all' lists every one.
create or replace function "better_supabase"."list_document_suggestions"(document_id uuid, status text default 'open')
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
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_suggestions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'documentId', x."document_id", 'summary', x."summary", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'note', x."note", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."created_at", x."id"), '[]'::jsonb)
    from "better_supabase"."document_suggestions" x
    where x."document_id" = v_doc."id"
      and (coalesce(list_document_suggestions.status, 'all') = 'all' or x."status"::text = list_document_suggestions.status)
  );
end;
$$;
revoke execute on function "better_supabase"."list_document_suggestions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_document_suggestions"(uuid, text) to authenticated, service_role;

-- Accepting appends the suggestion to the update log with its author as the
-- actor and returns the sequence number as 'seq'. Editors accept or reject;
-- the author withdraws.
create or replace function "better_supabase"."decide_document_suggestion"(suggestion_id uuid, decision text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "better_supabase"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true) or v_suggestion."created_by" = auth.uid()) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_suggestion."created_by" = auth.uid()) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and true and true)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = '55000', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    null;
  end if;
  end if;
  update "better_supabase"."document_suggestions" x
    set "status" = better_supabase.as_column_type(decide_document_suggestion.decision, (null::"better_supabase"."document_suggestions")."status"), "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    null;
  elsif v_suggestion."status" = 'rejected' then
    null;
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$$;
revoke execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) to authenticated, service_role;

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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and true)) then
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
-- compaction sweep without the queue block.
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

-- Readers join documents:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_documents_receive on realtime.messages;
create policy bsb_documents_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and "better_supabase"."document_topic_access"((select realtime.topic()), false));
        drop policy if exists bsb_documents_send on realtime.messages;
create policy bsb_documents_send on realtime.messages
  for insert to authenticated
  with check (((realtime.messages.extension = 'broadcast' and "better_supabase"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "better_supabase"."document_topic_access"((select realtime.topic()), false))) and (select better_supabase.actor_may_write()));
  end if;
end;
$do$;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
create policy bsb_tenant_scope_select on "better_supabase"."documents" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('documents.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
create policy bsb_tenant_scope_insert on "better_supabase"."documents" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
create policy bsb_tenant_scope_update on "better_supabase"."documents" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
create policy bsb_tenant_scope_delete on "better_supabase"."documents" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:a3907dcc75373f668c797d067d33e3661c05843c1b0474a550c3b0e322cbe981
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block documents@1 managed
-- @bsb-hash sha256:0cdffb89746117cf83d16ed5b52d1b9f3ab5480bb82a661242280e472c89bd44
-- Yjs documents attached to any subject: an update log, a compacted snapshot, a private realtime topic per document for updates and presence, suggestions that editors accept into the log, and named versions through the versions module.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_updates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_updates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_snapshots";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_snapshots";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."document_suggestions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."document_suggestions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."documents" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "name" text not null default 'body' check ("name" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "name")
);
create index if not exists "documents_tenant_idx" on "better_supabase"."documents" ("org_id", "updated_at" desc);
alter table "better_supabase"."documents" enable row level security;
revoke all on "better_supabase"."documents" from public, anon, authenticated;
grant select on "better_supabase"."documents" to authenticated;
grant all on "better_supabase"."documents" to service_role;
drop policy if exists documents_read on "better_supabase"."documents";
create policy documents_read on "better_supabase"."documents"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('documents.read')));

create table if not exists "better_supabase"."document_updates" (
  "seq" bigint generated always as identity primary key,
  "document_id" uuid not null references "better_supabase"."documents" ("id") on delete cascade,
  "org_id" uuid not null,
  "payload" bytea not null,
  "actor" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists "document_updates_document_idx" on "better_supabase"."document_updates" ("document_id", "seq");
alter table "better_supabase"."document_updates" enable row level security;
revoke all on "better_supabase"."document_updates" from public, anon, authenticated;
grant all on "better_supabase"."document_updates" to service_role;

create table if not exists "better_supabase"."document_snapshots" (
  "document_id" uuid primary key references "better_supabase"."documents" ("id") on delete cascade,
  "org_id" uuid not null,
  "state" bytea not null,
  "seq" bigint not null,
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."document_snapshots" enable row level security;
revoke all on "better_supabase"."document_snapshots" from public, anon, authenticated;
grant all on "better_supabase"."document_snapshots" to service_role;

create table if not exists "better_supabase"."document_suggestions" (
  "id" uuid primary key default gen_random_uuid(),
  "document_id" uuid not null references "better_supabase"."documents" ("id") on delete cascade,
  "org_id" uuid not null,
  "payload" bytea not null,
  "summary" text check (length("summary") between 1 and 500),
  "status" text not null default 'open' check ("status" in ('open', 'accepted', 'rejected', 'withdrawn')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "note" text check (length("note") between 1 and 500)
);
create index if not exists "document_suggestions_document_idx" on "better_supabase"."document_suggestions" ("document_id", "status", "created_at");
alter table "better_supabase"."document_suggestions" enable row level security;
revoke all on "better_supabase"."document_suggestions" from public, anon, authenticated;
grant all on "better_supabase"."document_suggestions" to service_role;

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
    return (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.write'), false) and true and true);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true);
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
  if found and v_doc."org_id" <> open_document.tenant then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not found then
    v_doc."org_id" := open_document.tenant;
    v_doc."subject_type" := open_document.subject_type;
    v_doc."subject_id" := open_document.subject_id;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.write'), false) and true and true)) then
      if (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true) then
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
    insert into "better_supabase"."documents" ("org_id", "subject_type", "subject_id", "name", "created_by")
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict ("subject_type", "subject_id", "name") do nothing
    returning * into v_doc;
    if found then
      null;
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
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.write'), false) and true and true);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."org_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'canSuggest', v_write or ((coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.suggest'), false)),
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.write'), false) and true and true)) then
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
  insert into "better_supabase"."document_updates" ("document_id", "org_id", "payload", "actor")
  values (v_doc."id", v_doc."org_id", v_bytes, auth.uid())
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    null;
  end if;
  return v_seq;
end;
$$;
revoke execute on function "better_supabase"."push_document_update"(uuid, text) from public, anon;
grant execute on function "better_supabase"."push_document_update"(uuid, text) to authenticated, service_role;

-- Stores a Yjs update (base64) as a suggestion instead of appending it.
-- Editors and readers with the suggest permission can suggest.
create or replace function "better_supabase"."suggest_document_change"(document_id uuid, payload text, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_bytes bytea;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = suggest_document_change.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.write'), false) and true and true) or ((coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true) and coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.suggest'), false)))) then
    raise exception 'not allowed to suggest changes to this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(suggest_document_change.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_suggestions" ("document_id", "org_id", "payload", "summary", "status", "created_by")
  values (v_doc."id", v_doc."org_id", v_bytes, nullif(trim(suggest_document_change.summary), ''), 'open', auth.uid())
  returning * into v_suggestion;
  null;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', ''));
end;
$$;
revoke execute on function "better_supabase"."suggest_document_change"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."suggest_document_change"(uuid, text, text) to authenticated, service_role;

-- Suggestions on a document, oldest first; status 'all' lists every one.
create or replace function "better_supabase"."list_document_suggestions"(document_id uuid, status text default 'open')
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
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_suggestions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'documentId', x."document_id", 'summary', x."summary", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'note', x."note", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."created_at", x."id"), '[]'::jsonb)
    from "better_supabase"."document_suggestions" x
    where x."document_id" = v_doc."id"
      and (coalesce(list_document_suggestions.status, 'all') = 'all' or x."status"::text = list_document_suggestions.status)
  );
end;
$$;
revoke execute on function "better_supabase"."list_document_suggestions"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_document_suggestions"(uuid, text) to authenticated, service_role;

-- Accepting appends the suggestion to the update log with its author as the
-- actor and returns the sequence number as 'seq'. Editors accept or reject;
-- the author withdraws.
create or replace function "better_supabase"."decide_document_suggestion"(suggestion_id uuid, decision text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "better_supabase"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true) or v_suggestion."created_by" = auth.uid()) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_suggestion."created_by" = auth.uid()) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.write'), false) and true and true)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = '55000', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "better_supabase"."document_updates" ("document_id", "org_id", "payload", "actor")
  values (v_doc."id", v_doc."org_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    null;
  end if;
  end if;
  update "better_supabase"."document_suggestions" x
    set "status" = decide_document_suggestion.decision, "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    null;
  elsif v_suggestion."status" = 'rejected' then
    null;
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$$;
revoke execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_document_suggestion"(uuid, text, text) to authenticated, service_role;

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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.read'), false) and true)) then
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_doc."org_id", 'documents.manage'), false)) then
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
  insert into "better_supabase"."document_snapshots" ("document_id", "org_id", "state", "seq")
  values (v_doc."id", v_doc."org_id", decode(compact_document.state, 'base64'), compact_document.through_seq)
  on conflict ("document_id") do update
    set "state" = excluded."state", "seq" = excluded."seq", "created_at" = now();
  delete from "better_supabase"."document_updates" x where x."document_id" = v_doc."id" and x."seq" <= compact_document.through_seq;
  return true;
end;
$$;
revoke execute on function "better_supabase"."compact_document"(uuid, text, bigint) from public, anon;
grant execute on function "better_supabase"."compact_document"(uuid, text, bigint) to authenticated, service_role;

-- Documents with at least min_updates updates since their snapshot, for a
-- compaction sweep without the queue block.
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

-- Readers join documents:{document} and track presence; editors broadcast
-- updates on it.
do $do$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_documents_receive on realtime.messages;
create policy bsb_documents_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension in ('broadcast', 'presence')
        and "better_supabase"."document_topic_access"((select realtime.topic()), false));
        drop policy if exists bsb_documents_send on realtime.messages;
create policy bsb_documents_send on realtime.messages
  for insert to authenticated
  with check (((realtime.messages.extension = 'broadcast' and "better_supabase"."document_topic_access"((select realtime.topic()), true))
        or (realtime.messages.extension = 'presence' and "better_supabase"."document_topic_access"((select realtime.topic()), false))) and (select better_supabase.actor_may_write()));
  end if;
end;
$do$;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."documents";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."documents";
create policy bsb_tenant_scope_select on "better_supabase"."documents" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('documents.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."documents";
create policy bsb_tenant_scope_insert on "better_supabase"."documents" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."documents";
create policy bsb_tenant_scope_update on "better_supabase"."documents" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."documents";
create policy bsb_tenant_scope_delete on "better_supabase"."documents" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_079_documents.sql
-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:a3907dcc75373f668c797d067d33e3661c05843c1b0474a550c3b0e322cbe981
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
