-- better-supabase module: cases
-- @bsb-block cases@1 managed
-- @bsb-hash sha256:5c6f91a1ac4139935d486b8e8ee34f681edf1ff1bbf3af491bd34946dc15b306
-- Nonconformities, complaints, safety incidents, near misses, observations, improvements, change requests and audit findings, with a kind, actions, a root cause, an effectiveness check and a closure guard.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Cases: nonconformities, complaints, incidents, observations, improvements and
-- change requests, with a kind, actions, a root cause and a closure guard.

create table if not exists "better_supabase"."case_kinds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "name" text not null,
  "prefix" text not null check ("prefix" ~ '^[A-Z]{1,6}$'),
  "requires_root_cause" boolean not null default true,
  "requires_actions" boolean not null default true,
  "requires_effectiveness" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
alter table "better_supabase"."case_kinds" enable row level security;
revoke all on "better_supabase"."case_kinds" from public, anon, authenticated;
grant select on "better_supabase"."case_kinds" to authenticated;
grant all on "better_supabase"."case_kinds" to service_role;
create policy case_kinds_read on better_supabase.case_kinds
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."cases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind_id" uuid not null,
  "number" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "description" text,
  "severity" text,
  "source" text,
  "reporter_id" uuid,
  "owner_id" uuid,
  "occurred_at" timestamptz,
  "detected_at" timestamptz not null default now(),
  "due_on" date,
  "status" text not null default 'open' check ("status" in ('open', 'closed', 'canceled')),
  "root_cause" text,
  "effective" boolean,
  "effectiveness_due_on" date,
  "closed_at" timestamptz,
  "closed_by" uuid,
  "close_note" text,
  "archived_at" timestamptz,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  foreign key ("tenant_id", "kind_id") references "better_supabase"."case_kinds" ("tenant_id", "id")
);
create index if not exists cases_status_idx on "better_supabase"."cases" ("tenant_id", "status");
create index if not exists cases_kind_idx on "better_supabase"."cases" ("tenant_id", "kind_id");
create index if not exists cases_owner_idx on "better_supabase"."cases" ("owner_id") where "owner_id" is not null;
alter table "better_supabase"."cases" enable row level security;
revoke all on "better_supabase"."cases" from public, anon, authenticated;
grant select on "better_supabase"."cases" to authenticated;
grant all on "better_supabase"."cases" to service_role;
create policy cases_read on better_supabase.cases
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create table if not exists "better_supabase"."case_actions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "case_id" uuid not null,
  "type" text not null check ("type" in ('containment', 'correction', 'corrective', 'preventive', 'improvement')),
  "title" text not null check (length("title") between 1 and 200),
  "assignee_id" uuid,
  "due_at" timestamptz,
  "required" boolean not null default true,
  "completed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  foreign key ("case_id") references "better_supabase"."cases" ("id") on delete cascade
);
create index if not exists case_actions_parent_idx on "better_supabase"."case_actions" ("case_id");
alter table "better_supabase"."case_actions" enable row level security;
revoke all on "better_supabase"."case_actions" from public, anon, authenticated;
grant select on "better_supabase"."case_actions" to authenticated;
grant all on "better_supabase"."case_actions" to service_role;
create policy case_actions_read on better_supabase.case_actions
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')));

create or replace function "better_supabase"."save_case_kind"(tenant uuid, key text, name text, prefix text, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, kind_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."case_kinds"%rowtype;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', save_case_kind.tenant, 'cases.manage'), false) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if save_case_kind.key !~ '^[a-z][a-z0-9_]{0,40}$' or save_case_kind.prefix !~ '^[A-Z]{1,6}$' then
    raise exception 'key and prefix are invalid' using errcode = '22023', hint = 'CASE_KIND_INVALID';
  end if;
  if save_case_kind.kind_id is null then
    insert into "better_supabase"."case_kinds" ("tenant_id", "key", "name", "prefix", "requires_root_cause", "requires_actions", "requires_effectiveness")
    values (save_case_kind.tenant, save_case_kind.key, trim(save_case_kind.name), save_case_kind.prefix, coalesce(save_case_kind.requires_root_cause, true), coalesce(save_case_kind.requires_actions, true), coalesce(save_case_kind.requires_effectiveness, false))
    on conflict ("tenant_id", "key") do update
      set "name" = excluded."name", "prefix" = excluded."prefix",
        "requires_root_cause" = excluded."requires_root_cause",
        "requires_actions" = excluded."requires_actions",
        "requires_effectiveness" = excluded."requires_effectiveness",
        "updated_at" = now()
    returning * into v_row;
    v_created := true;
  else
    update "better_supabase"."case_kinds" x set "key" = save_case_kind.key, "name" = trim(save_case_kind.name), "prefix" = save_case_kind.prefix,
      "requires_root_cause" = coalesce(save_case_kind.requires_root_cause, true),
      "requires_actions" = coalesce(save_case_kind.requires_actions, true),
      "requires_effectiveness" = coalesce(save_case_kind.requires_effectiveness, false),
      "updated_at" = now()
      where x."id" = save_case_kind.kind_id and x."tenant_id" = save_case_kind.tenant
      returning * into v_row;
    if not found then
      raise exception 'case kind not found' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
    end if;
  end if;
  if v_created then
    perform "better_supabase".emit_event('case_kind.created', jsonb_build_object('organizationId', v_row."tenant_id", 'kindId', v_row."id", 'key', v_row."key"), 'case-kinds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_kind.created',
    category => 'data',
    target_type => 'case_kind',
    record_id => v_row."id"::text,
    summary => 'saved case kind',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'kindId', v_row."id", 'key', v_row."key")
  );
  else
    perform "better_supabase".emit_event('case_kind.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'kindId', v_row."id", 'key', v_row."key"), 'case-kinds/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case_kind.updated',
    category => 'data',
    target_type => 'case_kind',
    record_id => v_row."id"::text,
    summary => 'saved case kind',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'kindId', v_row."id", 'key', v_row."key")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."save_case_kind"(uuid, text, text, text, boolean, boolean, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."archive_case_kind"(kind_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."case_kinds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_kinds" x where x."id" = archive_case_kind.kind_id;
  if not found then
    raise exception 'case kind not found' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.manage'), false) then
    raise exception 'not allowed to manage case kinds' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  update "better_supabase"."case_kinds" x set "archived_at" = now(), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'prefix', v_row."prefix", 'requiresRootCause', v_row."requires_root_cause", 'requiresActions', v_row."requires_actions", 'requiresEffectiveness', v_row."requires_effectiveness", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_case_kind"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_case_kind"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'prefix', x."prefix", 'requiresRootCause', x."requires_root_cause", 'requiresActions', x."requires_actions", 'requiresEffectiveness', x."requires_effectiveness", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key"), '[]'::jsonb)
  from "better_supabase"."case_kinds" x
  where x."tenant_id" = $1 and (include_archived or x."archived_at" is null)
    and x."tenant_id" in (select better_supabase.tenant_ids_with('cases.read'))
$$;
revoke execute on function "better_supabase"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind "better_supabase"."case_kinds"%rowtype;
  v_row "better_supabase"."cases"%rowtype;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', open_case.tenant, 'cases.create'), false) then
    raise exception 'not allowed to create cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select * into v_kind from "better_supabase"."case_kinds" x where x."tenant_id" = open_case.tenant and x."key" = open_case.kind;
  if not found then
    raise exception 'case kind not found' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if open_case.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = open_case.tenant and m."user_id" = open_case.owner_id) then
    raise exception 'the owner must be a member' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  select v_kind."prefix" || '-' || to_char(current_date, 'YYYY') || '-' || lpad((count(*) + 1)::text, 4, '0') into v_number
    from "better_supabase"."cases" x where x."tenant_id" = open_case.tenant and x."kind_id" = v_kind."id";
  insert into "better_supabase"."cases" ("tenant_id", "kind_id", "number", "title", "description", "severity", "source", "occurred_at", "owner_id", "due_on")
  values (open_case.tenant, v_kind."id", v_number, trim(open_case.title), open_case.description, open_case.severity, open_case.source, open_case.occurred_at, open_case.owner_id, open_case.due_on)
  returning * into v_row;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  perform "better_supabase".emit_event('case.created', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', v_kind."key", 'number', v_row."number"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.created',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    summary => 'opened case ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', v_kind."key", 'number', v_row."number")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date) from public, anon;
grant execute on function "better_supabase"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date) to authenticated, service_role;

create or replace function "better_supabase"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_changed text[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = update_case.case_id for update;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false) then
    raise exception 'not allowed to change cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'a closed case can''t change' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if changes ? 'title' then v_row."title" := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row."description" := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'severity' then v_row."severity" := changes ->> 'severity'; v_changed := array_append(v_changed, 'severity'); end if;
  if changes ? 'ownerId' then v_row."owner_id" := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'dueOn' then v_row."due_on" := (changes ->> 'dueOn')::date; v_changed := array_append(v_changed, 'dueOn'); end if;
  if changes ? 'occurredAt' then v_row."occurred_at" := (changes ->> 'occurredAt')::timestamptz; v_changed := array_append(v_changed, 'occurredAt'); end if;
  update "better_supabase"."cases" x set "title" = v_row."title", "description" = v_row."description", "severity" = v_row."severity", "owner_id" = v_row."owner_id", "due_on" = v_row."due_on", "occurred_at" = v_row."occurred_at", "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('case.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number", 'changed', to_jsonb(v_changed)), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.updated',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    summary => 'changed case ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number", 'changed', to_jsonb(v_changed))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_case"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."record_case_root_cause"(case_id uuid, root_cause text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_root_cause.case_id for update;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false) then
    raise exception 'not allowed to change cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'a closed case can''t change' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  update "better_supabase"."cases" x set "root_cause" = trim(record_case_root_cause.root_cause), "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('case.root_cause_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.root_cause_recorded',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    summary => 'recorded root cause for ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_root_cause"(uuid, text) from public, anon;
grant execute on function "better_supabase"."record_case_root_cause"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_case "better_supabase"."cases"%rowtype;
  v_row "better_supabase"."case_actions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_case from "better_supabase"."cases" x where x."id" = create_case_action.case_id;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_case."tenant_id", 'cases.write'), false) then
    raise exception 'not allowed to change cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_case."status" <> 'open' then
    raise exception 'a closed case can''t change' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  if create_case_action.type not in ('containment', 'correction', 'corrective', 'preventive', 'improvement') then
    raise exception 'the action type is invalid' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  insert into "better_supabase"."case_actions" ("tenant_id", "case_id", "type", "title", "assignee_id", "due_at", "required")
  values (v_case."tenant_id", v_case."id", create_case_action.type, trim(create_case_action.title), create_case_action.assignee_id, create_case_action.due_at, coalesce(create_case_action.required, true))
  returning * into v_row;
  perform "better_supabase".emit_event('case.action_added', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."case_id", 'actionId', v_row."id", 'type', v_row."type"), 'cases/' || v_row."case_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.action_added',
    category => 'data',
    target_type => 'case_action',
    record_id => v_row."id"::text,
    summary => 'added case action',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."case_id", 'actionId', v_row."id", 'type', v_row."type")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'caseId', v_row."case_id", 'type', v_row."type", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'dueAt', v_row."due_at", 'required', v_row."required", 'completedAt', v_row."completed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "better_supabase"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

create or replace function "better_supabase"."complete_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."case_actions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_actions" x where x."id" = complete_case_action.action_id;
  if not found then
    raise exception 'case action not found' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false) then
    raise exception 'not allowed to change cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  update "better_supabase"."case_actions" x set "completed_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('case.action_completed', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."case_id", 'actionId', v_row."id"), 'cases/' || v_row."case_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.action_completed',
    category => 'data',
    target_type => 'case_action',
    record_id => v_row."id"::text,
    summary => 'completed case action',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."case_id", 'actionId', v_row."id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'caseId', v_row."case_id", 'type', v_row."type", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'dueAt', v_row."due_at", 'required', v_row."required", 'completedAt', v_row."completed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."complete_case_action"(uuid) from public, anon;
grant execute on function "better_supabase"."complete_case_action"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."remove_case_action"(action_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."case_actions"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."case_actions" x where x."id" = remove_case_action.action_id;
  if not found then
    raise exception 'case action not found' using errcode = 'P0002', hint = 'CASE_ACTION_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false) then
    raise exception 'not allowed to change cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  delete from "better_supabase"."case_actions" x where x."id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'caseId', v_row."case_id", 'type', v_row."type", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'dueAt', v_row."due_at", 'required', v_row."required", 'completedAt', v_row."completed_at", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."remove_case_action"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_case_action"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."record_case_effectiveness"(case_id uuid, effective boolean, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = record_case_effectiveness.case_id for update;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.write'), false) then
    raise exception 'not allowed to change cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  update "better_supabase"."cases" x set "effective" = record_case_effectiveness.effective, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('case.effectiveness_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number", 'effective', v_row."effective"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.effectiveness_recorded',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    summary => 'recorded effectiveness for ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number", 'effective', v_row."effective")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."record_case_effectiveness"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."case_close_blockers"(case_id uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_case "better_supabase"."cases"%rowtype;
  v_kind "better_supabase"."case_kinds"%rowtype;
  v_blockers text[] := '{}';
begin
  select * into v_case from "better_supabase"."cases" x where x."id" = case_close_blockers.case_id;
  if not found then
    return v_blockers;
  end if;
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = v_case."kind_id";
  if v_kind."requires_root_cause" and v_case."root_cause" is null then
    v_blockers := array_append(v_blockers, 'CASE_ROOT_CAUSE_REQUIRED');
  end if;
  if v_kind."requires_actions" and not exists (select 1 from "better_supabase"."case_actions" x where x."case_id" = v_case."id") then
    v_blockers := array_append(v_blockers, 'CASE_ACTIONS_REQUIRED');
  end if;
  if exists (select 1 from "better_supabase"."case_actions" x where x."case_id" = v_case."id" and x."required" and x."completed_at" is null) then
    v_blockers := array_append(v_blockers, 'CASE_ACTIONS_OPEN');
  end if;
  if v_kind."requires_effectiveness" and v_case."effective" is distinct from true then
    v_blockers := array_append(v_blockers, 'CASE_EFFECTIVENESS_REQUIRED');
  end if;
  return v_blockers;
end;
$$;
revoke execute on function "better_supabase"."case_close_blockers"(uuid) from public, anon;
grant execute on function "better_supabase"."case_close_blockers"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."close_case"(case_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_blockers text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = close_case.case_id for update;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false) then
    raise exception 'not allowed to close cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'the case is not open' using errcode = '55000', hint = 'CASE_CLOSED';
  end if;
  v_blockers := "better_supabase"."case_close_blockers"(v_row."id");
  if cardinality(v_blockers) > 0 then
    raise exception 'the case has open blockers' using errcode = '22023', hint = 'CASE_ACTIONS_OPEN';
  end if;
  update "better_supabase"."cases" x set "status" = 'closed', "closed_at" = now(), "closed_by" = auth.uid(), "close_note" = close_case.note, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('case.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.closed',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    summary => 'closed case ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."close_case"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."reopen_case"(case_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = reopen_case.case_id for update;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false) then
    raise exception 'not allowed to reopen cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  update "better_supabase"."cases" x set "status" = 'open', "closed_at" = null, "closed_by" = null, "close_note" = null, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('case.reopened', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.reopened',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    summary => 'reopened case ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reopen_case"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."cancel_case"(case_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."cases" x where x."id" = cancel_case.case_id for update;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.close'), false) then
    raise exception 'not allowed to cancel cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  update "better_supabase"."cases" x set "status" = 'canceled', "close_note" = cancel_case.reason, "updated_at" = now() where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('case.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.cancelled',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    summary => 'canceled case ' || v_row."number",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', '', 'number', v_row."number")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_case"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_case"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."get_case"(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."cases"%rowtype;
  v_actions jsonb;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = get_case.case_id;
  if not found then
    raise exception 'case not found' using errcode = 'P0002', hint = 'CASE_NOT_FOUND';
  end if;
  if not (select auth.uid()) is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false) then
    raise exception 'not allowed to read cases' using errcode = '42501', hint = 'CASE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'caseId', x."case_id", 'type', x."type", 'title', x."title", 'assigneeId', x."assignee_id", 'dueAt', x."due_at", 'required', x."required", 'completedAt', x."completed_at", 'createdAt', x."created_at") order by x."created_at"), '[]'::jsonb) into v_actions from "better_supabase"."case_actions" x where x."case_id" = v_row."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kindId', v_row."kind_id", 'number', v_row."number", 'title', v_row."title", 'description', v_row."description", 'severity', v_row."severity", 'source', v_row."source", 'reporterId', v_row."reporter_id", 'ownerId', v_row."owner_id", 'occurredAt', v_row."occurred_at", 'detectedAt', v_row."detected_at", 'dueOn', v_row."due_on", 'status', v_row."status", 'rootCause', v_row."root_cause", 'effective', v_row."effective", 'effectivenessDueOn', v_row."effectiveness_due_on", 'closedAt', v_row."closed_at", 'closedBy', v_row."closed_by", 'closeNote', v_row."close_note", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('actions', v_actions, 'blockers', to_jsonb("better_supabase"."case_close_blockers"(v_row."id")));
end;
$$;
revoke execute on function "better_supabase"."get_case"(uuid) from public, anon;
grant execute on function "better_supabase"."get_case"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_cases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kindId', x."kind_id", 'number', x."number", 'title', x."title", 'description', x."description", 'severity', x."severity", 'source', x."source", 'reporterId', x."reporter_id", 'ownerId', x."owner_id", 'occurredAt', x."occurred_at", 'detectedAt', x."detected_at", 'dueOn', x."due_on", 'status', x."status", 'rootCause', x."root_cause", 'effective', x."effective", 'effectivenessDueOn', x."effectiveness_due_on", 'closedAt', x."closed_at", 'closedBy', x."closed_by", 'closeNote', x."close_note", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."detected_at" desc), '[]'::jsonb)
  from "better_supabase"."cases" x
  where x."tenant_id" = $1
    and x."tenant_id" in (select better_supabase.tenant_ids_with('cases.read'))
    and (not (filters ? 'status') or x."status" = filters ->> 'status')
    and (not (filters ? 'severity') or x."severity" = filters ->> 'severity')
    and (not (filters ? 'owner') or x."owner_id" = (filters ->> 'owner')::uuid)
    and (not (filters ? 'search') or x."title" ilike '%' || (filters ->> 'search') || '%' or x."number" ilike '%' || (filters ->> 'search') || '%')
  limit least(coalesce((filters ->> 'limit')::integer, 100), 200)
$$;
revoke execute on function "better_supabase"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_cases"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."case_stats"(tenant uuid, since date default null, until date default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', key, 'count', count) order by count desc), '[]'::jsonb)
  from (
    select coalesce(x."severity", 'unspecified') as key, count(*) as count
    from "better_supabase"."cases" x
    where x."tenant_id" = $1
      and x."tenant_id" in (select better_supabase.tenant_ids_with('cases.read'))
      and ($2 is null or x."detected_at"::date >= $2)
      and ($3 is null or x."detected_at"::date <= $3)
    group by 1
  ) s
$$;
revoke execute on function "better_supabase"."case_stats"(uuid, date, date) from public, anon;
grant execute on function "better_supabase"."case_stats"(uuid, date, date) to authenticated, service_role;

create or replace function "better_supabase"."notify_due_case_effectiveness"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from "better_supabase"."cases" x where x."status" = 'open' and x."effective" is null and x."effectiveness_due_on" is not null and x."effectiveness_due_on" <= current_date
  loop
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_due_case_effectiveness"() from public, anon;
grant execute on function "better_supabase"."notify_due_case_effectiveness"() to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."case_kinds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_select on "better_supabase"."case_kinds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_insert on "better_supabase"."case_kinds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_update on "better_supabase"."case_kinds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_kinds";
create policy bsb_tenant_scope_delete on "better_supabase"."case_kinds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."cases";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."cases";
create policy bsb_tenant_scope_select on "better_supabase"."cases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cases";
create policy bsb_tenant_scope_insert on "better_supabase"."cases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."cases";
create policy bsb_tenant_scope_update on "better_supabase"."cases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cases";
create policy bsb_tenant_scope_delete on "better_supabase"."cases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."case_actions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."case_actions";
create policy bsb_tenant_scope_select on "better_supabase"."case_actions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('cases.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."case_actions";
create policy bsb_tenant_scope_insert on "better_supabase"."case_actions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."case_actions";
create policy bsb_tenant_scope_update on "better_supabase"."case_actions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."case_actions";
create policy bsb_tenant_scope_delete on "better_supabase"."case_actions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

drop trigger if exists "bsb_search_case_index" on "better_supabase"."cases";
create trigger "bsb_search_case_index"
  after insert or delete or update of "id", "tenant_id", "title", "number", "description", "root_cause", "archived_at" on "better_supabase"."cases"
  for each row execute function "better_supabase"."search_index_row"('case', 'id');

-- blocks.cases.api: entry points for the Data API.
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

create or replace function "api"."save_case_kind"(tenant uuid, key text, name text, prefix text, requires_root_cause boolean default true, requires_actions boolean default true, requires_effectiveness boolean default false, kind_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_case_kind"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."save_case_kind"(uuid, text, text, text, boolean, boolean, boolean, uuid) from public, anon;
grant execute on function "api"."save_case_kind"(uuid, text, text, text, boolean, boolean, boolean, uuid) to authenticated, service_role;

create or replace function "api"."archive_case_kind"(kind_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_case_kind"($1) $$;
revoke execute on function "api"."archive_case_kind"(uuid) from public, anon;
grant execute on function "api"."archive_case_kind"(uuid) to authenticated, service_role;

create or replace function "api"."list_case_kinds"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_case_kinds"($1, $2) $$;
revoke execute on function "api"."list_case_kinds"(uuid, boolean) from public, anon;
grant execute on function "api"."list_case_kinds"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."open_case"(tenant uuid, kind text, title text, description text default null, severity text default null, source text default 'internal', occurred_at timestamptz default null, owner_id uuid default null, due_on date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_case"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date) from public, anon;
grant execute on function "api"."open_case"(uuid, text, text, text, text, text, timestamptz, uuid, date) to authenticated, service_role;

create or replace function "api"."update_case"(case_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_case"($1, $2) $$;
revoke execute on function "api"."update_case"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_case"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."record_case_root_cause"(case_id uuid, root_cause text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_case_root_cause"($1, $2) $$;
revoke execute on function "api"."record_case_root_cause"(uuid, text) from public, anon;
grant execute on function "api"."record_case_root_cause"(uuid, text) to authenticated, service_role;

create or replace function "api"."create_case_action"(case_id uuid, type text, title text, assignee_id uuid default null, due_at timestamptz default null, required boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_case_action"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) from public, anon;
grant execute on function "api"."create_case_action"(uuid, text, text, uuid, timestamptz, boolean) to authenticated, service_role;

create or replace function "api"."complete_case_action"(action_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_case_action"($1) $$;
revoke execute on function "api"."complete_case_action"(uuid) from public, anon;
grant execute on function "api"."complete_case_action"(uuid) to authenticated, service_role;

create or replace function "api"."remove_case_action"(action_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_case_action"($1) $$;
revoke execute on function "api"."remove_case_action"(uuid) from public, anon;
grant execute on function "api"."remove_case_action"(uuid) to authenticated, service_role;

create or replace function "api"."record_case_effectiveness"(case_id uuid, effective boolean, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_case_effectiveness"($1, $2, $3) $$;
revoke execute on function "api"."record_case_effectiveness"(uuid, boolean, text) from public, anon;
grant execute on function "api"."record_case_effectiveness"(uuid, boolean, text) to authenticated, service_role;

create or replace function "api"."case_close_blockers"(case_id uuid)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."case_close_blockers"($1) $$;
revoke execute on function "api"."case_close_blockers"(uuid) from public, anon;
grant execute on function "api"."case_close_blockers"(uuid) to authenticated, service_role;

create or replace function "api"."close_case"(case_id uuid, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_case"($1, $2) $$;
revoke execute on function "api"."close_case"(uuid, text) from public, anon;
grant execute on function "api"."close_case"(uuid, text) to authenticated, service_role;

create or replace function "api"."reopen_case"(case_id uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reopen_case"($1, $2) $$;
revoke execute on function "api"."reopen_case"(uuid, text) from public, anon;
grant execute on function "api"."reopen_case"(uuid, text) to authenticated, service_role;

create or replace function "api"."cancel_case"(case_id uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_case"($1, $2) $$;
revoke execute on function "api"."cancel_case"(uuid, text) from public, anon;
grant execute on function "api"."cancel_case"(uuid, text) to authenticated, service_role;

create or replace function "api"."get_case"(case_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_case"($1) $$;
revoke execute on function "api"."get_case"(uuid) from public, anon;
grant execute on function "api"."get_case"(uuid) to authenticated, service_role;

create or replace function "api"."list_cases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_cases"($1, $2) $$;
revoke execute on function "api"."list_cases"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_cases"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."case_stats"(tenant uuid, since date default null, until date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."case_stats"($1, $2, $3) $$;
revoke execute on function "api"."case_stats"(uuid, date, date) from public, anon;
grant execute on function "api"."case_stats"(uuid, date, date) to authenticated, service_role;

create or replace function "api"."notify_due_case_effectiveness"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_due_case_effectiveness"() $$;
revoke execute on function "api"."notify_due_case_effectiveness"() from public, anon;
grant execute on function "api"."notify_due_case_effectiveness"() to authenticated, service_role;

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
