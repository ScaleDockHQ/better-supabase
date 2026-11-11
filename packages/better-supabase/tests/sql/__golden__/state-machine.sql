-- ==== alone: schema supabase/schemas/900_better_supabase_060_state_machine.sql
-- better-supabase module: state-machine
-- @bsb-block state-machine@3 managed
-- @bsb-hash sha256:206605b1ce64f247c47c159427da2bf6e6b0c69d8a24f731339de843a92021f7
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.recordTypes type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
create policy bsb_status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (false);
create table "better_supabase"."status_stages" (
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
create index status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
create policy bsb_status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
create table "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "pause_expires_at" timestamptz,
  "pause_reason" text,
  "paused_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
create policy bsb_subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user, and the id of the user the
-- service role acts for.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet, nullif(transition.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
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
  v_next text[];
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
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
-- @bsb-hash sha256:78752d9a418623779c69e0d45cd9492e3fe2fbf93d5e4cb2cbb1c1bf1c21b4dd
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.recordTypes type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create or replace function better_supabase.bsb_record_visible(p_table text, p_column text, p_id text)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_found boolean;
begin
  execute format('select exists (select 1 from %s s where s.%I::text = $1)', p_table::regclass, p_column)
    into v_found using p_id;
  return coalesce(v_found, false);
end;
$$;
revoke execute on function better_supabase.bsb_record_visible(text, text, text) from public, anon;
grant execute on function better_supabase.bsb_record_visible(text, text, text) to authenticated, service_role;
create index status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
create policy bsb_status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (case "better_supabase"."status_history"."subject_type"
      when 'warranty_claim' then better_supabase.bsb_record_visible('"better_supabase"."warranty_claims"', 'id', "better_supabase"."status_history"."subject_id")
      else false
    end);
create table "better_supabase"."status_stages" (
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
create index status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
create policy bsb_status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (case "better_supabase"."status_stages"."subject_type"
      when 'warranty_claim' then better_supabase.bsb_record_visible('"better_supabase"."warranty_claims"', 'id', "better_supabase"."status_stages"."subject_id")
      else false
    end);
create table "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "pause_expires_at" timestamptz,
  "pause_reason" text,
  "paused_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
create policy bsb_subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (case "better_supabase"."subject_lifecycles"."subject_type"
      when 'warranty_claim' then better_supabase.bsb_record_visible('"better_supabase"."warranty_claims"', 'id', "better_supabase"."subject_lifecycles"."subject_id")
      else false
    end);


create or replace function better_supabase.bsb_transition_warranty_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new."status" is null then
      new."status" := 'draft';
    end if;
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."status" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'warranty_claim', new."id"::text, null::text, new."status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."status" is not distinct from old."status" then
    return new;
  end if;
  -- An import may set a status the state machine would refuse. The import
  -- already checked the row.
  if better_supabase.import_run() is not null then
    return new;
  end if;
  if not (case old."status"::text when 'draft' then new."status"::text = any ('{submitted}'::text[]) when 'submitted' then new."status"::text = any ('{approved,denied}'::text[]) when 'approved' then new."status"::text = any ('{closed}'::text[]) when 'denied' then new."status"::text = any ('{closed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'warranty_claim', new."id"::text, old."status"::text, new."status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'warranty_claim', 'subjectId', new."id"::text, 'from', old."status"::text, 'to', new."status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/warranty_claim/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$$;

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user, and the id of the user the
-- service role acts for.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet, nullif(transition.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  case transition.subject_type
    when 'warranty_claim' then
      update "better_supabase"."warranty_claims" s set "status" = better_supabase.as_column_type(transition.to_status, (null::"better_supabase"."warranty_claims")."status")
      where s."id" = (transition.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
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
  case pause_lifecycle.subject_type
    when 'warranty_claim' then
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
    when 'warranty_claim' then
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
    when 'warranty_claim' then
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
  v_next text[];
begin
  case status_state.subject_type
    when 'warranty_claim' then
      select s."status"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."warranty_claims" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_next := case v_status when 'draft' then '{submitted}'::text[] when 'submitted' then '{approved,denied}'::text[] when 'approved' then '{closed}'::text[] when 'denied' then '{closed}'::text[] else '{}'::text[] end;
      v_step := array_position(null::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'warranty_claim', 'subjectId', status_state.subject_id,
        'status', v_status, 'next', to_jsonb(v_next), 'order', to_jsonb(null::text[]), 'step', v_step, 'steps', null, 'progress', null,
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
    when 'warranty_claim' then
      if not exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'warranty_claim'
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
    when 'warranty_claim' then
      if not exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (list_status_stages.subject_id)::uuid) then
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (case "better_supabase"."status_history"."subject_type"
      when 'warranty_claim' then better_supabase.bsb_record_visible('"better_supabase"."warranty_claims"', 'id', "better_supabase"."status_history"."subject_id")
      else false
    end)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (case "better_supabase"."status_stages"."subject_type"
      when 'warranty_claim' then better_supabase.bsb_record_visible('"better_supabase"."warranty_claims"', 'id', "better_supabase"."status_stages"."subject_id")
      else false
    end)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (case "better_supabase"."subject_lifecycles"."subject_type"
      when 'warranty_claim' then better_supabase.bsb_record_visible('"better_supabase"."warranty_claims"', 'id', "better_supabase"."subject_lifecycles"."subject_id")
      else false
    end)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
-- @bsb-hash sha256:b75a69c86e7276cc1b01c93a687fc88e56038bb64cb6833568d6312966b1333b
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.recordTypes type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
create table "app_private"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index status_history_subject_idx on "app_private"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "app_private"."status_history" enable row level security;
revoke all on "app_private"."status_history" from public, anon, authenticated;
grant select on "app_private"."status_history" to authenticated;
grant all on "app_private"."status_history" to service_role;
create policy bsb_status_history_read on "app_private"."status_history"
  for select to authenticated
  using (false);
create table "app_private"."status_stages" (
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
create index status_stages_subject_idx on "app_private"."status_stages" ("subject_type", "subject_id");
alter table "app_private"."status_stages" enable row level security;
revoke all on "app_private"."status_stages" from public, anon, authenticated;
grant select on "app_private"."status_stages" to authenticated;
grant all on "app_private"."status_stages" to service_role;
create policy bsb_status_stages_read on "app_private"."status_stages"
  for select to authenticated
  using (false);
create table "app_private"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "pause_expires_at" timestamptz,
  "pause_reason" text,
  "paused_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index subject_lifecycles_paused_idx on "app_private"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "app_private"."subject_lifecycles" enable row level security;
revoke all on "app_private"."subject_lifecycles" from public, anon, authenticated;
grant select on "app_private"."subject_lifecycles" to authenticated;
grant all on "app_private"."subject_lifecycles" to service_role;
create policy bsb_subject_lifecycles_read on "app_private"."subject_lifecycles"
  for select to authenticated
  using (false);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user, and the id of the user the
-- service role acts for.
create or replace function "app_private"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet, nullif(transition.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
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
  v_next text[];
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
create policy bsb_tenant_scope_select on "app_private"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "app_private"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "app_private"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "app_private"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."subject_lifecycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
-- @bsb-hash sha256:e953d6e31e7c6566a42c411824de8d3f31d714a8b10453d0124be602648cb6c6
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.recordTypes type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
create policy bsb_status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (false);
create table "better_supabase"."status_stages" (
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
create index status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
create policy bsb_status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
create table "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "pause_expires_at" timestamptz,
  "pause_reason" text,
  "paused_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
create policy bsb_subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user, and the id of the user the
-- service role acts for.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet, nullif(transition.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
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
  v_next text[];
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
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.state-machine.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."status_state"($1, $2) $$;
revoke execute on function "api"."status_state"(text, text) from public, anon;
grant execute on function "api"."status_state"(text, text) to authenticated, service_role;

create or replace function "api"."list_status_history"(subject_type text, subject_id text, before timestamptz default null, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_status_history"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_status_history"(text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."list_status_history"(text, text, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."list_status_stages"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_status_stages"($1, $2) $$;
revoke execute on function "api"."list_status_stages"(text, text) from public, anon;
grant execute on function "api"."list_status_stages"(text, text) to authenticated, service_role;

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
-- @bsb-hash sha256:dca97413d5dc0fe735534bd4b2642db3a75d3ac69b975c13cf917312f21578b5
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.recordTypes type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- better_supabase.status_history is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."status_history" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."status_history" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."status_history" add column if not exists "subject_type" text;
alter table "better_supabase"."status_history" add column if not exists "subject_id" text;
alter table "better_supabase"."status_history" add column if not exists "from_status" text;
alter table "better_supabase"."status_history" add column if not exists "to_status" text;
alter table "better_supabase"."status_history" add column if not exists "actor_id" uuid;
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
alter table "better_supabase"."subject_lifecycles" add column if not exists "pause_expires_at" timestamptz;
alter table "better_supabase"."subject_lifecycles" add column if not exists "pause_reason" text;
alter table "better_supabase"."subject_lifecycles" add column if not exists "paused_by" uuid;
alter table "better_supabase"."subject_lifecycles" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."subject_lifecycles" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("tenant_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
create policy bsb_subject_lifecycles_select on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user, and the id of the user the
-- service role acts for.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet, nullif(transition.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
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
  v_next text[];
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
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
-- @bsb-hash sha256:1300a96593e7b0b5f878b550951d332325b2546d9ca485dd5a7649f8113310eb
-- Allowed status transitions as the caller, a history row and a status.changed event. A machine can also write a stages timeline and keep a lifecycle row (pause, flags, pinned version). Each machine is a subject table named in options.machines, or a config.recordTypes type.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."status_history" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "from_status" text,
  "to_status" text not null,
  "actor_id" uuid,
  "actor_name" text,
  "actor_email" text,
  "ip_address" inet,
  "user_agent" text,
  "reason" text,
  "created_at" timestamptz not null default now()
);
create index status_history_subject_idx on "better_supabase"."status_history" ("subject_type", "subject_id", "created_at" desc);
alter table "better_supabase"."status_history" enable row level security;
revoke all on "better_supabase"."status_history" from public, anon, authenticated;
grant select on "better_supabase"."status_history" to authenticated;
grant all on "better_supabase"."status_history" to service_role;
create policy bsb_status_history_read on "better_supabase"."status_history"
  for select to authenticated
  using (false);
create table "better_supabase"."status_stages" (
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
create index status_stages_subject_idx on "better_supabase"."status_stages" ("subject_type", "subject_id");
alter table "better_supabase"."status_stages" enable row level security;
revoke all on "better_supabase"."status_stages" from public, anon, authenticated;
grant select on "better_supabase"."status_stages" to authenticated;
grant all on "better_supabase"."status_stages" to service_role;
create policy bsb_status_stages_read on "better_supabase"."status_stages"
  for select to authenticated
  using (false);
create table "better_supabase"."subject_lifecycles" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "version" integer not null default 1,
  "flags" text[] not null default '{}',
  "paused_at" timestamptz,
  "pause_expires_at" timestamptz,
  "pause_reason" text,
  "paused_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id")
);
create index subject_lifecycles_paused_idx on "better_supabase"."subject_lifecycles" ("org_id", "subject_type") where "paused_at" is not null;
alter table "better_supabase"."subject_lifecycles" enable row level security;
revoke all on "better_supabase"."subject_lifecycles" from public, anon, authenticated;
grant select on "better_supabase"."subject_lifecycles" to authenticated;
grant all on "better_supabase"."subject_lifecycles" to service_role;
create policy bsb_subject_lifecycles_read on "better_supabase"."subject_lifecycles"
  for select to authenticated
  using (false);

-- Sets the status as the caller, so the subject table's policies decide
-- whether they may update the record; the trigger checks the edge. actor
-- carries the name, email, ip and userAgent the history row keeps, e.g. for
-- a portal visitor who isn't an auth user, and the id of the user the
-- service role acts for.
create or replace function "better_supabase"."transition"(subject_type text, subject_id text, to_status text, reason text default null, actor jsonb default null)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet, nullif(transition.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
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
  v_next text[];
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
create policy bsb_tenant_scope_select on "better_supabase"."status_history" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_history" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_history" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_history" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."status_stages" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."status_stages" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."status_stages" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."status_stages" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."subject_lifecycles" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (false)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."subject_lifecycles" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."subject_lifecycles" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."subject_lifecycles" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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
