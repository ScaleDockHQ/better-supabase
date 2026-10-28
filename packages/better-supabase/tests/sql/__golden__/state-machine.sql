-- ==== alone: schema supabase/schemas/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:7ac42669cebc09abe6af914fe769787b2c14fe9a3246fcf24dfc02e5024a8658
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_user_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
drop policy if exists status_history_read on "better_supabase"."status_history";
create policy status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."status_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "label" text not null,
  "outcome" text,
  "display" integer not null,
  "cleared_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
drop policy if exists status_stages_read on "better_supabase"."status_stages";
create policy status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "paused_until" timestamptz,
  "pause_reason" text,
  "paused_by_user_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index if not exists subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
drop policy if exists subject_lifecycles_read on "better_supabase"."subject_lifecycles";
create policy subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);



drop function if exists "better_supabase"."transition"(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function "better_supabase"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function "better_supabase"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "better_supabase"."resume_lifecycle"(text, text) to authenticated, service_role;

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function "better_supabase"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function "better_supabase"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."status_state"(text, text) from public, anon;
grant execute on function "better_supabase"."status_state"(text, text) to authenticated, service_role;

-- The record's status changes, newest first, as the caller.
create or replace function "better_supabase"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function "better_supabase"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_stages"(text, text) from public, anon;
grant execute on function "better_supabase"."list_status_stages"(text, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:eed0cde016d3acd0ea24fb6d8c5faf9cfd3417857dd07b02e0b4266dfa97fe1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:7ac42669cebc09abe6af914fe769787b2c14fe9a3246fcf24dfc02e5024a8658
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_user_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
drop policy if exists status_history_read on "better_supabase"."status_history";
create policy status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."status_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "label" text not null,
  "outcome" text,
  "display" integer not null,
  "cleared_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
drop policy if exists status_stages_read on "better_supabase"."status_stages";
create policy status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "paused_until" timestamptz,
  "pause_reason" text,
  "paused_by_user_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index if not exists subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
drop policy if exists subject_lifecycles_read on "better_supabase"."subject_lifecycles";
create policy subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);



drop function if exists "better_supabase"."transition"(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function "better_supabase"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function "better_supabase"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "better_supabase"."resume_lifecycle"(text, text) to authenticated, service_role;

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function "better_supabase"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function "better_supabase"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."status_state"(text, text) from public, anon;
grant execute on function "better_supabase"."status_state"(text, text) to authenticated, service_role;

-- The record's status changes, newest first, as the caller.
create or replace function "better_supabase"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function "better_supabase"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_stages"(text, text) from public, anon;
grant execute on function "better_supabase"."list_status_stages"(text, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:eed0cde016d3acd0ea24fb6d8c5faf9cfd3417857dd07b02e0b4266dfa97fe1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:1d29054c206fe449c000f0ee62eee06e74b358d8d0dede8f2fa19bb0bf2d2c76
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."status_history";
    drop policy if exists bsb_tenant_scope_select on "app_private"."status_history";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."status_history";
    drop policy if exists bsb_tenant_scope_update on "app_private"."status_history";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."status_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."status_stages";
    drop policy if exists bsb_tenant_scope_select on "app_private"."status_stages";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."status_stages";
    drop policy if exists bsb_tenant_scope_update on "app_private"."status_stages";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."status_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_select on "app_private"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_update on "app_private"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."subject_lifecycles";
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
create table if not exists "app_private"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_user_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists status_history_subject_idx on "app_private"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "app_private"."status_history" enable row level security;
revoke all on "app_private"."status_history" from public, anon, authenticated;
grant select on "app_private"."status_history" to authenticated;
grant all on "app_private"."status_history" to service_role;
drop policy if exists status_history_read on "app_private"."status_history";
create policy status_history_read on "app_private"."status_history"
  for select to authenticated
  using (false);
create table if not exists "app_private"."status_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "label" text not null,
  "outcome" text,
  "display" integer not null,
  "cleared_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists status_stages_subject_idx on "app_private"."status_stages" ("subject_type", "subject_id");
alter table "app_private"."status_stages" enable row level security;
revoke all on "app_private"."status_stages" from public, anon, authenticated;
grant select on "app_private"."status_stages" to authenticated;
grant all on "app_private"."status_stages" to service_role;
drop policy if exists status_stages_read on "app_private"."status_stages";
create policy status_stages_read on "app_private"."status_stages"
  for select to authenticated
  using (false);
create table if not exists "app_private"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "paused_until" timestamptz,
  "pause_reason" text,
  "paused_by_user_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index if not exists subject_lifecycles_paused_idx on "app_private"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "app_private"."subject_lifecycles" enable row level security;
revoke all on "app_private"."subject_lifecycles" from public, anon, authenticated;
grant select on "app_private"."subject_lifecycles" to authenticated;
grant all on "app_private"."subject_lifecycles" to service_role;
drop policy if exists subject_lifecycles_read on "app_private"."subject_lifecycles";
create policy subject_lifecycles_read on "app_private"."subject_lifecycles"
  for select to authenticated
  using (false);



drop function if exists "app_private"."transition"(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user.
create or replace function "app_private"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "app_private"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "app_private"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function "app_private"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "app_private"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "app_private"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function "app_private"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "app_private"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "app_private"."resume_lifecycle"(text, text) to authenticated, service_role;

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function "app_private"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "app_private"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "app_private"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function "app_private"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "app_private"."status_state"(text, text) from public, anon;
grant execute on function "app_private"."status_state"(text, text) to authenticated, service_role;

-- The record's status changes, newest first, as the caller.
create or replace function "app_private"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "app_private"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "app_private"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function "app_private"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "app_private"."list_status_stages"(text, text) from public, anon;
grant execute on function "app_private"."list_status_stages"(text, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."status_history";
drop policy if exists bsb_tenant_scope_select on "app_private"."status_history";
create policy bsb_tenant_scope_select on "app_private"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."status_history";
create policy bsb_tenant_scope_insert on "app_private"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."status_history";
create policy bsb_tenant_scope_update on "app_private"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."status_history";
create policy bsb_tenant_scope_delete on "app_private"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."status_stages";
drop policy if exists bsb_tenant_scope_select on "app_private"."status_stages";
create policy bsb_tenant_scope_select on "app_private"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."status_stages";
create policy bsb_tenant_scope_insert on "app_private"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."status_stages";
create policy bsb_tenant_scope_update on "app_private"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."status_stages";
create policy bsb_tenant_scope_delete on "app_private"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."subject_lifecycles";
drop policy if exists bsb_tenant_scope_select on "app_private"."subject_lifecycles";
create policy bsb_tenant_scope_select on "app_private"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."subject_lifecycles";
create policy bsb_tenant_scope_insert on "app_private"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."subject_lifecycles";
create policy bsb_tenant_scope_update on "app_private"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."subject_lifecycles";
create policy bsb_tenant_scope_delete on "app_private"."subject_lifecycles" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:eed0cde016d3acd0ea24fb6d8c5faf9cfd3417857dd07b02e0b4266dfa97fe1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:9f2ea6a006996a35db8c627a65a3ea44434f8b34e1c94267ca33e66d783a19c2
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_user_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
drop policy if exists status_history_read on "better_supabase"."status_history";
create policy status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."status_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "label" text not null,
  "outcome" text,
  "display" integer not null,
  "cleared_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
drop policy if exists status_stages_read on "better_supabase"."status_stages";
create policy status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "paused_until" timestamptz,
  "pause_reason" text,
  "paused_by_user_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index if not exists subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
drop policy if exists subject_lifecycles_read on "better_supabase"."subject_lifecycles";
create policy subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);



drop function if exists "better_supabase"."transition"(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function "better_supabase"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function "better_supabase"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "better_supabase"."resume_lifecycle"(text, text) to authenticated, service_role;

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function "better_supabase"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function "better_supabase"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."status_state"(text, text) from public, anon;
grant execute on function "better_supabase"."status_state"(text, text) to authenticated, service_role;

-- The record's status changes, newest first, as the caller.
create or replace function "better_supabase"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function "better_supabase"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_stages"(text, text) from public, anon;
grant execute on function "better_supabase"."list_status_stages"(text, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.state-machine.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."transition"(text, text, text, text);

create or replace function "api"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."transition"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "api"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pause_lifecycle"($1, $2, $3, $4) $$;
revoke execute on function "api"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "api"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

create or replace function "api"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resume_lifecycle"($1, $2) $$;
revoke execute on function "api"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "api"."resume_lifecycle"(text, text) to authenticated, service_role;

create or replace function "api"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_lifecycle_flag"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "api"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

create or replace function "api"."status_state"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."status_state"($1, $2) $$;
revoke execute on function "api"."status_state"(text, text) from public, anon;
grant execute on function "api"."status_state"(text, text) to authenticated, service_role;

create or replace function "api"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_status_history"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_status_stages"($1, $2) $$;
revoke execute on function "api"."list_status_stages"(text, text) from public, anon;
grant execute on function "api"."list_status_stages"(text, text) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:eed0cde016d3acd0ea24fb6d8c5faf9cfd3417857dd07b02e0b4266dfa97fe1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:54869e3739e787d963d819f42f253a14a6f50eff5f64b790ca62cbc4b78ae5ad
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.status_history is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."status_history" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."status_history" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."status_history" add column if not exists "subject_type" text;
alter table "better_supabase"."status_history" add column if not exists "subject_id" text;
alter table "better_supabase"."status_history" add column if not exists "from_status" text;
alter table "better_supabase"."status_history" add column if not exists "to_status" text;
alter table "better_supabase"."status_history" add column if not exists "actor_user_id" uuid;
alter table "better_supabase"."status_history" add column if not exists "actor_name" text;
alter table "better_supabase"."status_history" add column if not exists "actor_email" text;
alter table "better_supabase"."status_history" add column if not exists "ip_address" inet;
alter table "better_supabase"."status_history" add column if not exists "user_agent" text;
alter table "better_supabase"."status_history" add column if not exists "reason" text;
alter table "better_supabase"."status_history" add column if not exists "created_at" timestamptz not null default now();
create index if not exists status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
drop policy if exists bsb_status_history_select on "better_supabase"."status_history";
create policy bsb_status_history_select on "better_supabase"."status_history"
  for select to authenticated
  using (false);
-- better_supabase.status_stages is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."status_stages" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."status_stages" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."status_stages" add column if not exists "subject_type" text;
alter table "better_supabase"."status_stages" add column if not exists "subject_id" text;
alter table "better_supabase"."status_stages" add column if not exists "label" text;
alter table "better_supabase"."status_stages" add column if not exists "outcome" text;
alter table "better_supabase"."status_stages" add column if not exists "display" integer;
alter table "better_supabase"."status_stages" add column if not exists "cleared_at" timestamptz;
alter table "better_supabase"."status_stages" add column if not exists "created_at" timestamptz not null default now();
create index if not exists status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
drop policy if exists bsb_status_stages_select on "better_supabase"."status_stages";
create policy bsb_status_stages_select on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
-- better_supabase.subject_lifecycles is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."subject_lifecycles" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."subject_lifecycles" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."subject_lifecycles" add column if not exists "subject_type" text;
alter table "better_supabase"."subject_lifecycles" add column if not exists "subject_id" text;
alter table "better_supabase"."subject_lifecycles" add column if not exists "version" integer not null default 1;
alter table "better_supabase"."subject_lifecycles" add column if not exists "flags" text[] not null default '{}';
alter table "better_supabase"."subject_lifecycles" add column if not exists "paused_at" timestamptz;
alter table "better_supabase"."subject_lifecycles" add column if not exists "paused_until" timestamptz;
alter table "better_supabase"."subject_lifecycles" add column if not exists "pause_reason" text;
alter table "better_supabase"."subject_lifecycles" add column if not exists "paused_by_user_id" uuid;
alter table "better_supabase"."subject_lifecycles" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."subject_lifecycles" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
drop policy if exists bsb_subject_lifecycles_select on "better_supabase"."subject_lifecycles";
create policy bsb_subject_lifecycles_select on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);



drop function if exists "better_supabase"."transition"(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function "better_supabase"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function "better_supabase"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "better_supabase"."resume_lifecycle"(text, text) to authenticated, service_role;

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function "better_supabase"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function "better_supabase"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."status_state"(text, text) from public, anon;
grant execute on function "better_supabase"."status_state"(text, text) to authenticated, service_role;

-- The record's status changes, newest first, as the caller.
create or replace function "better_supabase"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function "better_supabase"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_stages"(text, text) from public, anon;
grant execute on function "better_supabase"."list_status_stages"(text, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:eed0cde016d3acd0ea24fb6d8c5faf9cfd3417857dd07b02e0b4266dfa97fe1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:99f5637579752e677d48f5d10e8f5e548f070d747c754dd34ecd7430be1c7775
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_user_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
drop policy if exists status_history_read on "better_supabase"."status_history";
create policy status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."status_stages" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "label" text not null,
  "outcome" text,
  "display" integer not null,
  "cleared_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
drop policy if exists status_stages_read on "better_supabase"."status_stages";
create policy status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
create table if not exists "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "paused_until" timestamptz,
  "pause_reason" text,
  "paused_by_user_id" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index if not exists subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("org_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
drop policy if exists subject_lifecycles_read on "better_supabase"."subject_lifecycles";
create policy subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);



drop function if exists "better_supabase"."transition"(text, text, text, text);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."transition"(text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."transition"(text, text, text, text, jsonb) to authenticated, service_role;

-- Pauses the record until a time (or until resume_lifecycle when null); the
-- trigger refuses transitions meanwhile (STATE_PAUSED). As the caller.
create or replace function "better_supabase"."pause_lifecycle"(subject_type text, subject_id text, until timestamptz, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."pause_lifecycle"(text, text, timestamptz, text) to authenticated, service_role;

-- Ends a pause. Returns false when the record wasn't paused. As the caller.
create or replace function "better_supabase"."resume_lifecycle"(subject_type text, subject_id text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."resume_lifecycle"(text, text) from public, anon;
grant execute on function "better_supabase"."resume_lifecycle"(text, text) to authenticated, service_role;

-- Turns one of options.machines.<name>.flags on or off. Returns false when
-- the flag already had that value. As the caller.
create or replace function "better_supabase"."set_lifecycle_flag"(subject_type text, subject_id text, flag text, enabled boolean)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_lifecycle_flag"(text, text, text, boolean) to authenticated, service_role;

-- The record's status, progress through options.machines.<name>.order and,
-- with lifecycle: true, its flags, pause and pinned version. It runs as the
-- caller: a record they can't see is STATE_SUBJECT_NOT_FOUND.
create or replace function "better_supabase"."status_state"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."status_state"(text, text) from public, anon;
grant execute on function "better_supabase"."status_state"(text, text) to authenticated, service_role;

-- The record's status changes, newest first, as the caller.
create or replace function "better_supabase"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

-- The record's stages timeline in display order, as the caller; empty for a
-- machine without stages: true.
create or replace function "better_supabase"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
end;
$$;
revoke execute on function "better_supabase"."list_status_stages"(text, text) from public, anon;
grant execute on function "better_supabase"."list_status_stages"(text, text) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."status_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_history";
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_history";
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_history";
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_history";
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."status_stages";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."status_stages";
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."status_stages";
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."status_stages";
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."status_stages";
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_lifecycles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles";
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block-data state-machine
-- @bsb-hash sha256:eed0cde016d3acd0ea24fb6d8c5faf9cfd3417857dd07b02e0b4266dfa97fe1c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('state-machine', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
