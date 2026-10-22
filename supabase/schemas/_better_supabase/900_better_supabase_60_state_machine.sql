-- better-supabase module: state-machine (0.9.0)
-- @bs-module state-machine@2 managed
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.subjects type.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index if not exists status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
drop policy if exists status_history_read on "better_supabase"."status_history";
create policy status_history_read on "better_supabase"."status_history" for select to authenticated
  using (case "better_supabase"."status_history"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."status_history"."subject_id")::uuid)
      else false
    end);
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
revoke all on "better_supabase"."status_stages" from anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
drop policy if exists status_stages_read on "better_supabase"."status_stages";
create policy status_stages_read on "better_supabase"."status_stages" for select to authenticated
  using (case "better_supabase"."status_stages"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."status_stages"."subject_id")::uuid)
      else false
    end);
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
revoke all on "better_supabase"."subject_lifecycles" from anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
drop policy if exists subject_lifecycles_read on "better_supabase"."subject_lifecycles";
create policy subject_lifecycles_read on "better_supabase"."subject_lifecycles" for select to authenticated
  using (case "better_supabase"."subject_lifecycles"."subject_type"
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ("better_supabase"."subject_lifecycles"."subject_id")::uuid)
      else false
    end);


create or replace function better_supabase.bsb_transition_work_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new."state" is null then
      new."state" := 'backlog';
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  if not (case old."state" when 'triage' then new."state" = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state" = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state" = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state" = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state" = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state" = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason")
        values (new."tenant_id", 'work_item', new."id"::text, old."state", new."state", auth.uid(), nullif(current_setting('better_supabase.transition_reason', true), ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$$;
drop trigger if exists bsb_transition_work_item on "better_supabase"."work_items";
create trigger bsb_transition_work_item before insert or update of "state" on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_transition_work_item();

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  case transition.subject_type
    when 'work_item' then
      update "better_supabase"."work_items" s set "state" = transition.to_status
      where s."id" = (transition.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
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
revoke execute on function "better_supabase"."transition"(text, text, text, text) from public, anon;
grant execute on function "better_supabase"."transition"(text, text, text, text) to authenticated, service_role;

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
  case pause_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
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
  case resume_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
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
  case set_lifecycle_flag.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
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
  case status_state.subject_type
    when 'work_item' then
      select s."state"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."work_items" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_step := array_position('{triage,backlog,unstarted,started,completed}'::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'work_item', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb('{triage,backlog,unstarted,started,completed}'::text[]), 'step', v_step, 'steps', 5, 'progress', case when v_step is null then null when 5 = 1 then 1 else round((v_step - 1)::numeric / 4, 4) end,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
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
  case list_status_history.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'work_item'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
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
  case list_status_stages.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_stages.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return '[]'::jsonb;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."list_status_stages"(text, text) from public, anon;
grant execute on function "better_supabase"."list_status_stages"(text, text) to authenticated, service_role;

-- blocks.state-machine.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."transition"(subject_type text, subject_id text, to_status text, reason text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."transition"($1, $2, $3, $4) $$;
revoke execute on function "api"."transition"(text, text, text, text) from public, anon;
grant execute on function "api"."transition"(text, text, text, text) to authenticated, service_role;

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
