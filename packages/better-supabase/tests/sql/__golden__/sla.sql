-- ==== alone: schema supabase/schemas/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block sla@1 managed
-- @bsb-hash sha256:775645e339b74d1a2ec97e4a1a500fccd3574171b01ed60b4d1ee2716e9d1fa1
-- Service levels on any registered record: first response, next response and resolution clocks from a policy per type and priority, business hours, pauses while the record waits, and warnings and breaches a job records.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Service levels on any record: response and resolution clocks from a
-- policy per record type and priority, in business hours, paused while the
-- record waits, with warnings and breaches recorded by a job.
create table if not exists "better_supabase"."sla_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "priority" text,
  "first_response_minutes" integer check ("first_response_minutes" > 0),
  "next_response_minutes" integer check ("next_response_minutes" > 0),
  "resolution_minutes" integer check ("resolution_minutes" > 0),
  "warn_at_percent" smallint not null default 80 check ("warn_at_percent" between 1 and 99),
  "business_hours" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists sla_policies_match_idx on "better_supabase"."sla_policies" ("tenant_id", "subject_type", coalesce("priority", '')) where "archived_at" is null;
alter table "better_supabase"."sla_policies" enable row level security;
revoke all on "better_supabase"."sla_policies" from anon, authenticated;
grant select on "better_supabase"."sla_policies" to authenticated;
grant all on "better_supabase"."sla_policies" to service_role;
drop policy if exists sla_policies_read on "better_supabase"."sla_policies";
create policy sla_policies_read on "better_supabase"."sla_policies" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')));

create table if not exists "better_supabase"."sla_clocks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "policy_id" uuid references "better_supabase"."sla_policies" ("id") on delete set null,
  "metric" text not null check ("metric" in ('first_response', 'next_response', 'resolution')),
  "started_at" timestamptz not null,
  "due_at" timestamptz not null,
  "paused_at" timestamptz,
  "paused_seconds" integer not null default 0,
  "warned_at" timestamptz,
  "breached_at" timestamptz,
  "met_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists sla_clocks_open_idx on "better_supabase"."sla_clocks" ("subject_type", "subject_id", "metric") where "met_at" is null;
create index if not exists sla_clocks_due_idx on "better_supabase"."sla_clocks" ("due_at") where "met_at" is null and "paused_at" is null;
create index if not exists sla_clocks_policy_idx on "better_supabase"."sla_clocks" ("policy_id");
alter table "better_supabase"."sla_clocks" enable row level security;
revoke all on "better_supabase"."sla_clocks" from anon, authenticated;
grant select on "better_supabase"."sla_clocks" to authenticated;
grant all on "better_supabase"."sla_clocks" to service_role;
drop policy if exists sla_clocks_read on "better_supabase"."sla_clocks";
create policy sla_clocks_read on "better_supabase"."sla_clocks" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The time minutes of working time after start: business hours on the
-- configured weekdays in the configured time zone, or plain minutes.
create or replace function "better_supabase"."sla_due_at"(start timestamptz, minutes integer, business boolean)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_left integer := sla_due_at.minutes;
  v_local timestamp := sla_due_at.start at time zone 'UTC';
  v_open timestamp;
  v_close timestamp;
  v_take integer;
begin
  if not sla_due_at.business then
    return sla_due_at.start + make_interval(mins => sla_due_at.minutes);
  end if;
  for v_day in 0..400 loop
    v_open := date_trunc('day', v_local) + '09:00'::time;
    v_close := date_trunc('day', v_local) + '17:00'::time;
    if extract(isodow from v_local)::integer = any ('{1,2,3,4,5}'::integer[]) and v_local < v_close then
      v_local := greatest(v_local, v_open);
      v_take := least(v_left, (extract(epoch from v_close - v_local) / 60)::integer);
      v_local := v_local + make_interval(mins => v_take);
      v_left := v_left - v_take;
      if v_left <= 0 then
        return v_local at time zone 'UTC';
      end if;
    end if;
    v_local := date_trunc('day', v_local) + interval '1 day';
  end loop;
  raise exception 'no business hours within 400 days' using errcode = '22023', hint = 'SLA_HOURS_INVALID';
end;
$$;
revoke execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) from public, anon;
grant execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) to authenticated, service_role;

-- Creates or changes a policy: name, subjectType, priority (null for every
-- priority), firstResponseMinutes, nextResponseMinutes, resolutionMinutes,
-- warnAtPercent, businessHours, archived.
create or replace function "better_supabase"."save_sla_policy"(tenant uuid, policy uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_sla_policy.policy;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_sla_policy.tenant, 'sla.manage'), false)) then
    raise exception 'not allowed to manage service levels' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."sla_policies" ("tenant_id", "subject_type", "name", "priority", "first_response_minutes", "next_response_minutes", "resolution_minutes", "warn_at_percent", "business_hours")
      values (save_sla_policy.tenant, save_sla_policy.attrs ->> 'subjectType', save_sla_policy.attrs ->> 'name', save_sla_policy.attrs ->> 'priority',
        (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer, (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer,
        (save_sla_policy.attrs ->> 'resolutionMinutes')::integer, coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, 80),
        coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, false))
      returning "id" into v_id;
    else
      update "better_supabase"."sla_policies" x set
        "name" = coalesce(save_sla_policy.attrs ->> 'name', x."name"),
        "priority" = case when save_sla_policy.attrs ? 'priority' then save_sla_policy.attrs ->> 'priority' else x."priority" end,
        "first_response_minutes" = case when save_sla_policy.attrs ? 'firstResponseMinutes' then (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer else x."first_response_minutes" end,
        "next_response_minutes" = case when save_sla_policy.attrs ? 'nextResponseMinutes' then (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer else x."next_response_minutes" end,
        "resolution_minutes" = case when save_sla_policy.attrs ? 'resolutionMinutes' then (save_sla_policy.attrs ->> 'resolutionMinutes')::integer else x."resolution_minutes" end,
        "warn_at_percent" = coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, x."warn_at_percent"),
        "business_hours" = coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, x."business_hours"),
        "archived_at" = case when coalesce((save_sla_policy.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_sla_policy.tenant;
      if not found then
        raise exception 'policy not found' using errcode = 'P0002', hint = 'SLA_POLICY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another active policy covers this record type and priority' using errcode = '23505', hint = 'SLA_POLICY_TAKEN';
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a policy needs a name, a record type and positive minutes' using errcode = '22023', hint = 'SLA_POLICY_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."sla_policies" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) to authenticated, service_role;

-- Starts a record's clocks from the policy for its type and priority (the
-- exact priority first, then the policy without one). Starting again, as
-- when the priority changes, recomputes the due times of the open clocks
-- from when they started.
create or replace function "better_supabase"."start_sla_clocks"(subject_type text, subject_id text, priority text, trusted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_policy "better_supabase"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "better_supabase"."sla_policies" x
  where x."tenant_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "better_supabase"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "better_supabase"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "better_supabase"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "better_supabase"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$$;
revoke execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) to authenticated, service_role;

-- Moves a record's clocks: responded meets the response clock and starts
-- the next-response clock; resolved meets every open clock; reopened starts
-- a new resolution clock; paused and resumed stop and restart them, moving
-- the due times by the pause.
create or replace function "better_supabase"."record_sla_event"(subject_type text, subject_id text, event text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_clock "better_supabase"."sla_clocks";
  v_policy "better_supabase"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "better_supabase"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "better_supabase"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    null;
  end loop;
  select x.* into v_policy from "better_supabase"."sla_clocks" c join "better_supabase"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$$;
revoke execute on function "better_supabase"."record_sla_event"(text, text, text) from public, anon;
grant execute on function "better_supabase"."record_sla_event"(text, text, text) to authenticated, service_role;

-- A record's clocks the caller can see, newest first, with their state:
-- running, paused, met, breached; and the seconds left.
create or replace function "better_supabase"."sla_clocks_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
    'state', case
      when x."met_at" is not null then 'met'
      when x."paused_at" is not null then 'paused'
      when x."due_at" < now() then 'breached'
      else 'running' end,
    'secondsLeft', case when x."met_at" is null then extract(epoch from x."due_at" - coalesce(x."paused_at", now()))::integer end
  ) order by x."created_at" desc, x."metric"), '[]'::jsonb)
  from "better_supabase"."sla_clocks" x
  where x."subject_type" = sla_clocks_of.subject_type and x."subject_id" = sla_clocks_of.subject_id
$$;
revoke execute on function "better_supabase"."sla_clocks_of"(text, text) from public, anon;
grant execute on function "better_supabase"."sla_clocks_of"(text, text) to authenticated, service_role;

-- Records warnings and breaches of running clocks and notifies the record's
-- watchers. Run it every minute or so from a job. Returns how many changed.
create or replace function "better_supabase"."check_sla_clocks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clock "better_supabase"."sla_clocks";
  v_count integer := 0;
  v_claims text;
begin
  for v_clock in
    update "better_supabase"."sla_clocks" x set "breached_at" = now()
    where x."met_at" is null and x."paused_at" is null and x."breached_at" is null and x."due_at" < now()
    returning *
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "warned_at" = now()
    from "better_supabase"."sla_policies" y
    where y."id" = x."policy_id" and x."met_at" is null and x."paused_at" is null and x."warned_at" is null
      and x."breached_at" is null
      and now() >= x."started_at" + (x."due_at" - x."started_at") * y."warn_at_percent" / 100.0
    returning x.*
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."check_sla_clocks"() from public, anon, authenticated;
grant execute on function "better_supabase"."check_sla_clocks"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
create policy bsb_tenant_scope on "better_supabase"."sla_policies" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
create policy bsb_tenant_scope on "better_supabase"."sla_clocks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:3a470193710382c34f047abbf9d2b499106a119c4e117a44c502d2ac46999a8a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block sla@1 managed
-- @bsb-hash sha256:2bc4b07375f4ad550a79cc130e472a6614848ca24274ee8f963340da9b15835c
-- Service levels on any registered record: first response, next response and resolution clocks from a policy per type and priority, business hours, pauses while the record waits, and warnings and breaches a job records.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Service levels on any record: response and resolution clocks from a
-- policy per record type and priority, in business hours, paused while the
-- record waits, with warnings and breaches recorded by a job.
create table if not exists "better_supabase"."sla_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "priority" text,
  "first_response_minutes" integer check ("first_response_minutes" > 0),
  "next_response_minutes" integer check ("next_response_minutes" > 0),
  "resolution_minutes" integer check ("resolution_minutes" > 0),
  "warn_at_percent" smallint not null default 80 check ("warn_at_percent" between 1 and 99),
  "business_hours" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists sla_policies_match_idx on "better_supabase"."sla_policies" ("tenant_id", "subject_type", coalesce("priority", '')) where "archived_at" is null;
alter table "better_supabase"."sla_policies" enable row level security;
revoke all on "better_supabase"."sla_policies" from anon, authenticated;
grant select on "better_supabase"."sla_policies" to authenticated;
grant all on "better_supabase"."sla_policies" to service_role;
drop policy if exists sla_policies_read on "better_supabase"."sla_policies";
create policy sla_policies_read on "better_supabase"."sla_policies" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')));

create table if not exists "better_supabase"."sla_clocks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "policy_id" uuid references "better_supabase"."sla_policies" ("id") on delete set null,
  "metric" text not null check ("metric" in ('first_response', 'next_response', 'resolution')),
  "started_at" timestamptz not null,
  "due_at" timestamptz not null,
  "paused_at" timestamptz,
  "paused_seconds" integer not null default 0,
  "warned_at" timestamptz,
  "breached_at" timestamptz,
  "met_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists sla_clocks_open_idx on "better_supabase"."sla_clocks" ("subject_type", "subject_id", "metric") where "met_at" is null;
create index if not exists sla_clocks_due_idx on "better_supabase"."sla_clocks" ("due_at") where "met_at" is null and "paused_at" is null;
create index if not exists sla_clocks_policy_idx on "better_supabase"."sla_clocks" ("policy_id");
alter table "better_supabase"."sla_clocks" enable row level security;
revoke all on "better_supabase"."sla_clocks" from anon, authenticated;
grant select on "better_supabase"."sla_clocks" to authenticated;
grant all on "better_supabase"."sla_clocks" to service_role;
drop policy if exists sla_clocks_read on "better_supabase"."sla_clocks";
create policy sla_clocks_read on "better_supabase"."sla_clocks" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The time minutes of working time after start: business hours on the
-- configured weekdays in the configured time zone, or plain minutes.
create or replace function "better_supabase"."sla_due_at"(start timestamptz, minutes integer, business boolean)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_left integer := sla_due_at.minutes;
  v_local timestamp := sla_due_at.start at time zone 'UTC';
  v_open timestamp;
  v_close timestamp;
  v_take integer;
begin
  if not sla_due_at.business then
    return sla_due_at.start + make_interval(mins => sla_due_at.minutes);
  end if;
  for v_day in 0..400 loop
    v_open := date_trunc('day', v_local) + '09:00'::time;
    v_close := date_trunc('day', v_local) + '17:00'::time;
    if extract(isodow from v_local)::integer = any ('{1,2,3,4,5}'::integer[]) and v_local < v_close then
      v_local := greatest(v_local, v_open);
      v_take := least(v_left, (extract(epoch from v_close - v_local) / 60)::integer);
      v_local := v_local + make_interval(mins => v_take);
      v_left := v_left - v_take;
      if v_left <= 0 then
        return v_local at time zone 'UTC';
      end if;
    end if;
    v_local := date_trunc('day', v_local) + interval '1 day';
  end loop;
  raise exception 'no business hours within 400 days' using errcode = '22023', hint = 'SLA_HOURS_INVALID';
end;
$$;
revoke execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) from public, anon;
grant execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) to authenticated, service_role;

-- Creates or changes a policy: name, subjectType, priority (null for every
-- priority), firstResponseMinutes, nextResponseMinutes, resolutionMinutes,
-- warnAtPercent, businessHours, archived.
create or replace function "better_supabase"."save_sla_policy"(tenant uuid, policy uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_sla_policy.policy;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_sla_policy.tenant, 'sla.manage'), false)) then
    raise exception 'not allowed to manage service levels' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."sla_policies" ("tenant_id", "subject_type", "name", "priority", "first_response_minutes", "next_response_minutes", "resolution_minutes", "warn_at_percent", "business_hours")
      values (save_sla_policy.tenant, save_sla_policy.attrs ->> 'subjectType', save_sla_policy.attrs ->> 'name', save_sla_policy.attrs ->> 'priority',
        (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer, (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer,
        (save_sla_policy.attrs ->> 'resolutionMinutes')::integer, coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, 80),
        coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, false))
      returning "id" into v_id;
    else
      update "better_supabase"."sla_policies" x set
        "name" = coalesce(save_sla_policy.attrs ->> 'name', x."name"),
        "priority" = case when save_sla_policy.attrs ? 'priority' then save_sla_policy.attrs ->> 'priority' else x."priority" end,
        "first_response_minutes" = case when save_sla_policy.attrs ? 'firstResponseMinutes' then (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer else x."first_response_minutes" end,
        "next_response_minutes" = case when save_sla_policy.attrs ? 'nextResponseMinutes' then (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer else x."next_response_minutes" end,
        "resolution_minutes" = case when save_sla_policy.attrs ? 'resolutionMinutes' then (save_sla_policy.attrs ->> 'resolutionMinutes')::integer else x."resolution_minutes" end,
        "warn_at_percent" = coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, x."warn_at_percent"),
        "business_hours" = coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, x."business_hours"),
        "archived_at" = case when coalesce((save_sla_policy.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_sla_policy.tenant;
      if not found then
        raise exception 'policy not found' using errcode = 'P0002', hint = 'SLA_POLICY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another active policy covers this record type and priority' using errcode = '23505', hint = 'SLA_POLICY_TAKEN';
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a policy needs a name, a record type and positive minutes' using errcode = '22023', hint = 'SLA_POLICY_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."sla_policies" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) to authenticated, service_role;

-- Starts a record's clocks from the policy for its type and priority (the
-- exact priority first, then the policy without one). Starting again, as
-- when the priority changes, recomputes the due times of the open clocks
-- from when they started.
create or replace function "better_supabase"."start_sla_clocks"(subject_type text, subject_id text, priority text, trusted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_policy "better_supabase"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "better_supabase"."sla_policies" x
  where x."tenant_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "better_supabase"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "better_supabase"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "better_supabase"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "better_supabase"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$$;
revoke execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) to authenticated, service_role;

-- Moves a record's clocks: responded meets the response clock and starts
-- the next-response clock; resolved meets every open clock; reopened starts
-- a new resolution clock; paused and resumed stop and restart them, moving
-- the due times by the pause.
create or replace function "better_supabase"."record_sla_event"(subject_type text, subject_id text, event text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_clock "better_supabase"."sla_clocks";
  v_policy "better_supabase"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "better_supabase"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "better_supabase"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    perform "better_supabase".emit_event('sla.completed', jsonb_build_object('organizationId', v_clock."tenant_id", 'clockId', v_clock."id", 'subjectType', v_clock."subject_type", 'subjectId', v_clock."subject_id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at", 'late', v_clock."met_at" > v_clock."due_at"), 'sla-clocks/' || v_clock."id"::text, (v_clock."tenant_id"::text)::text, null, 'better-supabase/sla');
  end loop;
  select x.* into v_policy from "better_supabase"."sla_clocks" c join "better_supabase"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$$;
revoke execute on function "better_supabase"."record_sla_event"(text, text, text) from public, anon;
grant execute on function "better_supabase"."record_sla_event"(text, text, text) to authenticated, service_role;

-- A record's clocks the caller can see, newest first, with their state:
-- running, paused, met, breached; and the seconds left.
create or replace function "better_supabase"."sla_clocks_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
    'state', case
      when x."met_at" is not null then 'met'
      when x."paused_at" is not null then 'paused'
      when x."due_at" < now() then 'breached'
      else 'running' end,
    'secondsLeft', case when x."met_at" is null then extract(epoch from x."due_at" - coalesce(x."paused_at", now()))::integer end
  ) order by x."created_at" desc, x."metric"), '[]'::jsonb)
  from "better_supabase"."sla_clocks" x
  where x."subject_type" = sla_clocks_of.subject_type and x."subject_id" = sla_clocks_of.subject_id
$$;
revoke execute on function "better_supabase"."sla_clocks_of"(text, text) from public, anon;
grant execute on function "better_supabase"."sla_clocks_of"(text, text) to authenticated, service_role;

-- Records warnings and breaches of running clocks and notifies the record's
-- watchers. Run it every minute or so from a job. Returns how many changed.
create or replace function "better_supabase"."check_sla_clocks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clock "better_supabase"."sla_clocks";
  v_count integer := 0;
  v_claims text;
begin
  for v_clock in
    update "better_supabase"."sla_clocks" x set "breached_at" = now()
    where x."met_at" is null and x."paused_at" is null and x."breached_at" is null and x."due_at" < now()
    returning *
  loop
    perform "better_supabase".emit_event('sla.breached', jsonb_build_object('organizationId', v_clock."tenant_id", 'clockId', v_clock."id", 'subjectType', v_clock."subject_type", 'subjectId', v_clock."subject_id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at"), 'sla-clocks/' || v_clock."id"::text, (v_clock."tenant_id"::text)::text, null, 'better-supabase/sla');
    v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'sla.breached',
      'tenant', v_clock."tenant_id",
      'subject_type', v_clock."subject_type",
      'subject_id', v_clock."subject_id",
      'summary', v_clock."metric" || ' ' || 'breached',
      'priority', 'high',
      'key', 'sla.breached:' || v_clock."id"::text,
      'data', jsonb_build_object('clockId', v_clock."id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    v_count := v_count + 1;
  end loop;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "warned_at" = now()
    from "better_supabase"."sla_policies" y
    where y."id" = x."policy_id" and x."met_at" is null and x."paused_at" is null and x."warned_at" is null
      and x."breached_at" is null
      and now() >= x."started_at" + (x."due_at" - x."started_at") * y."warn_at_percent" / 100.0
    returning x.*
  loop
    perform "better_supabase".emit_event('sla.warned', jsonb_build_object('organizationId', v_clock."tenant_id", 'clockId', v_clock."id", 'subjectType', v_clock."subject_type", 'subjectId', v_clock."subject_id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at"), 'sla-clocks/' || v_clock."id"::text, (v_clock."tenant_id"::text)::text, null, 'better-supabase/sla');
    v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'sla.warned',
      'tenant', v_clock."tenant_id",
      'subject_type', v_clock."subject_type",
      'subject_id', v_clock."subject_id",
      'summary', v_clock."metric" || ' ' || 'warned',
      'priority', 'high',
      'key', 'sla.warned:' || v_clock."id"::text,
      'data', jsonb_build_object('clockId', v_clock."id", 'metric', v_clock."metric", 'dueAt', v_clock."due_at")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."check_sla_clocks"() from public, anon, authenticated;
grant execute on function "better_supabase"."check_sla_clocks"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
create policy bsb_tenant_scope on "better_supabase"."sla_policies" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
create policy bsb_tenant_scope on "better_supabase"."sla_clocks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:3a470193710382c34f047abbf9d2b499106a119c4e117a44c502d2ac46999a8a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block sla@1 managed
-- @bsb-hash sha256:4b8a86156cd4989fc3bc7d911c1d561a4fadf7d5a201cf323df5907234266d5d
-- Service levels on any registered record: first response, next response and resolution clocks from a policy per type and priority, business hours, pauses while the record waits, and warnings and breaches a job records.
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
    drop policy if exists bsb_tenant_scope on "app_private"."sla_policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."sla_clocks";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Service levels on any record: response and resolution clocks from a
-- policy per record type and priority, in business hours, paused while the
-- record waits, with warnings and breaches recorded by a job.
create table if not exists "app_private"."sla_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "priority" text,
  "first_response_minutes" integer check ("first_response_minutes" > 0),
  "next_response_minutes" integer check ("next_response_minutes" > 0),
  "resolution_minutes" integer check ("resolution_minutes" > 0),
  "warn_at_percent" smallint not null default 80 check ("warn_at_percent" between 1 and 99),
  "business_hours" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists sla_policies_match_idx on "app_private"."sla_policies" ("tenant_id", "subject_type", coalesce("priority", '')) where "archived_at" is null;
alter table "app_private"."sla_policies" enable row level security;
revoke all on "app_private"."sla_policies" from anon, authenticated;
grant select on "app_private"."sla_policies" to authenticated;
grant all on "app_private"."sla_policies" to service_role;
drop policy if exists sla_policies_read on "app_private"."sla_policies";
create policy sla_policies_read on "app_private"."sla_policies" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')));

create table if not exists "app_private"."sla_clocks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "policy_id" uuid references "app_private"."sla_policies" ("id") on delete set null,
  "metric" text not null check ("metric" in ('first_response', 'next_response', 'resolution')),
  "started_at" timestamptz not null,
  "due_at" timestamptz not null,
  "paused_at" timestamptz,
  "paused_seconds" integer not null default 0,
  "warned_at" timestamptz,
  "breached_at" timestamptz,
  "met_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists sla_clocks_open_idx on "app_private"."sla_clocks" ("subject_type", "subject_id", "metric") where "met_at" is null;
create index if not exists sla_clocks_due_idx on "app_private"."sla_clocks" ("due_at") where "met_at" is null and "paused_at" is null;
create index if not exists sla_clocks_policy_idx on "app_private"."sla_clocks" ("policy_id");
alter table "app_private"."sla_clocks" enable row level security;
revoke all on "app_private"."sla_clocks" from anon, authenticated;
grant select on "app_private"."sla_clocks" to authenticated;
grant all on "app_private"."sla_clocks" to service_role;
drop policy if exists sla_clocks_read on "app_private"."sla_clocks";
create policy sla_clocks_read on "app_private"."sla_clocks" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The time minutes of working time after start: business hours on the
-- configured weekdays in the configured time zone, or plain minutes.
create or replace function "app_private"."sla_due_at"(start timestamptz, minutes integer, business boolean)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_left integer := sla_due_at.minutes;
  v_local timestamp := sla_due_at.start at time zone 'UTC';
  v_open timestamp;
  v_close timestamp;
  v_take integer;
begin
  if not sla_due_at.business then
    return sla_due_at.start + make_interval(mins => sla_due_at.minutes);
  end if;
  for v_day in 0..400 loop
    v_open := date_trunc('day', v_local) + '09:00'::time;
    v_close := date_trunc('day', v_local) + '17:00'::time;
    if extract(isodow from v_local)::integer = any ('{1,2,3,4,5}'::integer[]) and v_local < v_close then
      v_local := greatest(v_local, v_open);
      v_take := least(v_left, (extract(epoch from v_close - v_local) / 60)::integer);
      v_local := v_local + make_interval(mins => v_take);
      v_left := v_left - v_take;
      if v_left <= 0 then
        return v_local at time zone 'UTC';
      end if;
    end if;
    v_local := date_trunc('day', v_local) + interval '1 day';
  end loop;
  raise exception 'no business hours within 400 days' using errcode = '22023', hint = 'SLA_HOURS_INVALID';
end;
$$;
revoke execute on function "app_private"."sla_due_at"(timestamptz, integer, boolean) from public, anon;
grant execute on function "app_private"."sla_due_at"(timestamptz, integer, boolean) to authenticated, service_role;

-- Creates or changes a policy: name, subjectType, priority (null for every
-- priority), firstResponseMinutes, nextResponseMinutes, resolutionMinutes,
-- warnAtPercent, businessHours, archived.
create or replace function "app_private"."save_sla_policy"(tenant uuid, policy uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_sla_policy.policy;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_sla_policy.tenant, 'sla.manage'), false)) then
    raise exception 'not allowed to manage service levels' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "app_private"."sla_policies" ("tenant_id", "subject_type", "name", "priority", "first_response_minutes", "next_response_minutes", "resolution_minutes", "warn_at_percent", "business_hours")
      values (save_sla_policy.tenant, save_sla_policy.attrs ->> 'subjectType', save_sla_policy.attrs ->> 'name', save_sla_policy.attrs ->> 'priority',
        (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer, (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer,
        (save_sla_policy.attrs ->> 'resolutionMinutes')::integer, coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, 80),
        coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, false))
      returning "id" into v_id;
    else
      update "app_private"."sla_policies" x set
        "name" = coalesce(save_sla_policy.attrs ->> 'name', x."name"),
        "priority" = case when save_sla_policy.attrs ? 'priority' then save_sla_policy.attrs ->> 'priority' else x."priority" end,
        "first_response_minutes" = case when save_sla_policy.attrs ? 'firstResponseMinutes' then (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer else x."first_response_minutes" end,
        "next_response_minutes" = case when save_sla_policy.attrs ? 'nextResponseMinutes' then (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer else x."next_response_minutes" end,
        "resolution_minutes" = case when save_sla_policy.attrs ? 'resolutionMinutes' then (save_sla_policy.attrs ->> 'resolutionMinutes')::integer else x."resolution_minutes" end,
        "warn_at_percent" = coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, x."warn_at_percent"),
        "business_hours" = coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, x."business_hours"),
        "archived_at" = case when coalesce((save_sla_policy.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_sla_policy.tenant;
      if not found then
        raise exception 'policy not found' using errcode = 'P0002', hint = 'SLA_POLICY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another active policy covers this record type and priority' using errcode = '23505', hint = 'SLA_POLICY_TAKEN';
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a policy needs a name, a record type and positive minutes' using errcode = '22023', hint = 'SLA_POLICY_INVALID';
  end;
  return (select to_jsonb(x) from "app_private"."sla_policies" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."save_sla_policy"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_sla_policy"(uuid, uuid, jsonb) to authenticated, service_role;

-- Starts a record's clocks from the policy for its type and priority (the
-- exact priority first, then the policy without one). Starting again, as
-- when the priority changes, recomputes the due times of the open clocks
-- from when they started.
create or replace function "app_private"."start_sla_clocks"(subject_type text, subject_id text, priority text, trusted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_policy "app_private"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "app_private"."sla_policies" x
  where x."tenant_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "app_private"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "app_private"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "app_private"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "app_private"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "app_private"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "app_private"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$$;
revoke execute on function "app_private"."start_sla_clocks"(text, text, text, boolean) from public, anon;
grant execute on function "app_private"."start_sla_clocks"(text, text, text, boolean) to authenticated, service_role;

-- Moves a record's clocks: responded meets the response clock and starts
-- the next-response clock; resolved meets every open clock; reopened starts
-- a new resolution clock; paused and resumed stop and restart them, moving
-- the due times by the pause.
create or replace function "app_private"."record_sla_event"(subject_type text, subject_id text, event text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_clock "app_private"."sla_clocks";
  v_policy "app_private"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "app_private"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "app_private"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "app_private"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "app_private"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "app_private"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    null;
  end loop;
  select x.* into v_policy from "app_private"."sla_clocks" c join "app_private"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "app_private"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "app_private"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "app_private"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "app_private"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "app_private"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "app_private"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$$;
revoke execute on function "app_private"."record_sla_event"(text, text, text) from public, anon;
grant execute on function "app_private"."record_sla_event"(text, text, text) to authenticated, service_role;

-- A record's clocks the caller can see, newest first, with their state:
-- running, paused, met, breached; and the seconds left.
create or replace function "app_private"."sla_clocks_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
    'state', case
      when x."met_at" is not null then 'met'
      when x."paused_at" is not null then 'paused'
      when x."due_at" < now() then 'breached'
      else 'running' end,
    'secondsLeft', case when x."met_at" is null then extract(epoch from x."due_at" - coalesce(x."paused_at", now()))::integer end
  ) order by x."created_at" desc, x."metric"), '[]'::jsonb)
  from "app_private"."sla_clocks" x
  where x."subject_type" = sla_clocks_of.subject_type and x."subject_id" = sla_clocks_of.subject_id
$$;
revoke execute on function "app_private"."sla_clocks_of"(text, text) from public, anon;
grant execute on function "app_private"."sla_clocks_of"(text, text) to authenticated, service_role;

-- Records warnings and breaches of running clocks and notifies the record's
-- watchers. Run it every minute or so from a job. Returns how many changed.
create or replace function "app_private"."check_sla_clocks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clock "app_private"."sla_clocks";
  v_count integer := 0;
  v_claims text;
begin
  for v_clock in
    update "app_private"."sla_clocks" x set "breached_at" = now()
    where x."met_at" is null and x."paused_at" is null and x."breached_at" is null and x."due_at" < now()
    returning *
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  for v_clock in
    update "app_private"."sla_clocks" x set "warned_at" = now()
    from "app_private"."sla_policies" y
    where y."id" = x."policy_id" and x."met_at" is null and x."paused_at" is null and x."warned_at" is null
      and x."breached_at" is null
      and now() >= x."started_at" + (x."due_at" - x."started_at") * y."warn_at_percent" / 100.0
    returning x.*
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."check_sla_clocks"() from public, anon, authenticated;
grant execute on function "app_private"."check_sla_clocks"() to service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."sla_policies";
create policy bsb_tenant_scope on "app_private"."sla_policies" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."sla_clocks";
create policy bsb_tenant_scope on "app_private"."sla_clocks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:3a470193710382c34f047abbf9d2b499106a119c4e117a44c502d2ac46999a8a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block sla@1 managed
-- @bsb-hash sha256:37191e61598cd529b44f854ca3a56ba661a8bc998ddd93d3b2088b8dcf60d816
-- Service levels on any registered record: first response, next response and resolution clocks from a policy per type and priority, business hours, pauses while the record waits, and warnings and breaches a job records.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Service levels on any record: response and resolution clocks from a
-- policy per record type and priority, in business hours, paused while the
-- record waits, with warnings and breaches recorded by a job.
create table if not exists "better_supabase"."sla_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "priority" text,
  "first_response_minutes" integer check ("first_response_minutes" > 0),
  "next_response_minutes" integer check ("next_response_minutes" > 0),
  "resolution_minutes" integer check ("resolution_minutes" > 0),
  "warn_at_percent" smallint not null default 80 check ("warn_at_percent" between 1 and 99),
  "business_hours" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists sla_policies_match_idx on "better_supabase"."sla_policies" ("tenant_id", "subject_type", coalesce("priority", '')) where "archived_at" is null;
alter table "better_supabase"."sla_policies" enable row level security;
revoke all on "better_supabase"."sla_policies" from anon, authenticated;
grant select on "better_supabase"."sla_policies" to authenticated;
grant all on "better_supabase"."sla_policies" to service_role;
drop policy if exists sla_policies_read on "better_supabase"."sla_policies";
create policy sla_policies_read on "better_supabase"."sla_policies" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')));

create table if not exists "better_supabase"."sla_clocks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "policy_id" uuid references "better_supabase"."sla_policies" ("id") on delete set null,
  "metric" text not null check ("metric" in ('first_response', 'next_response', 'resolution')),
  "started_at" timestamptz not null,
  "due_at" timestamptz not null,
  "paused_at" timestamptz,
  "paused_seconds" integer not null default 0,
  "warned_at" timestamptz,
  "breached_at" timestamptz,
  "met_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists sla_clocks_open_idx on "better_supabase"."sla_clocks" ("subject_type", "subject_id", "metric") where "met_at" is null;
create index if not exists sla_clocks_due_idx on "better_supabase"."sla_clocks" ("due_at") where "met_at" is null and "paused_at" is null;
create index if not exists sla_clocks_policy_idx on "better_supabase"."sla_clocks" ("policy_id");
alter table "better_supabase"."sla_clocks" enable row level security;
revoke all on "better_supabase"."sla_clocks" from anon, authenticated;
grant select on "better_supabase"."sla_clocks" to authenticated;
grant all on "better_supabase"."sla_clocks" to service_role;
drop policy if exists sla_clocks_read on "better_supabase"."sla_clocks";
create policy sla_clocks_read on "better_supabase"."sla_clocks" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The time minutes of working time after start: business hours on the
-- configured weekdays in the configured time zone, or plain minutes.
create or replace function "better_supabase"."sla_due_at"(start timestamptz, minutes integer, business boolean)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_left integer := sla_due_at.minutes;
  v_local timestamp := sla_due_at.start at time zone 'UTC';
  v_open timestamp;
  v_close timestamp;
  v_take integer;
begin
  if not sla_due_at.business then
    return sla_due_at.start + make_interval(mins => sla_due_at.minutes);
  end if;
  for v_day in 0..400 loop
    v_open := date_trunc('day', v_local) + '09:00'::time;
    v_close := date_trunc('day', v_local) + '17:00'::time;
    if extract(isodow from v_local)::integer = any ('{1,2,3,4,5}'::integer[]) and v_local < v_close then
      v_local := greatest(v_local, v_open);
      v_take := least(v_left, (extract(epoch from v_close - v_local) / 60)::integer);
      v_local := v_local + make_interval(mins => v_take);
      v_left := v_left - v_take;
      if v_left <= 0 then
        return v_local at time zone 'UTC';
      end if;
    end if;
    v_local := date_trunc('day', v_local) + interval '1 day';
  end loop;
  raise exception 'no business hours within 400 days' using errcode = '22023', hint = 'SLA_HOURS_INVALID';
end;
$$;
revoke execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) from public, anon;
grant execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) to authenticated, service_role;

-- Creates or changes a policy: name, subjectType, priority (null for every
-- priority), firstResponseMinutes, nextResponseMinutes, resolutionMinutes,
-- warnAtPercent, businessHours, archived.
create or replace function "better_supabase"."save_sla_policy"(tenant uuid, policy uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_sla_policy.policy;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_sla_policy.tenant, 'sla.manage'), false)) then
    raise exception 'not allowed to manage service levels' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."sla_policies" ("tenant_id", "subject_type", "name", "priority", "first_response_minutes", "next_response_minutes", "resolution_minutes", "warn_at_percent", "business_hours")
      values (save_sla_policy.tenant, save_sla_policy.attrs ->> 'subjectType', save_sla_policy.attrs ->> 'name', save_sla_policy.attrs ->> 'priority',
        (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer, (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer,
        (save_sla_policy.attrs ->> 'resolutionMinutes')::integer, coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, 80),
        coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, false))
      returning "id" into v_id;
    else
      update "better_supabase"."sla_policies" x set
        "name" = coalesce(save_sla_policy.attrs ->> 'name', x."name"),
        "priority" = case when save_sla_policy.attrs ? 'priority' then save_sla_policy.attrs ->> 'priority' else x."priority" end,
        "first_response_minutes" = case when save_sla_policy.attrs ? 'firstResponseMinutes' then (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer else x."first_response_minutes" end,
        "next_response_minutes" = case when save_sla_policy.attrs ? 'nextResponseMinutes' then (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer else x."next_response_minutes" end,
        "resolution_minutes" = case when save_sla_policy.attrs ? 'resolutionMinutes' then (save_sla_policy.attrs ->> 'resolutionMinutes')::integer else x."resolution_minutes" end,
        "warn_at_percent" = coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, x."warn_at_percent"),
        "business_hours" = coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, x."business_hours"),
        "archived_at" = case when coalesce((save_sla_policy.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_sla_policy.tenant;
      if not found then
        raise exception 'policy not found' using errcode = 'P0002', hint = 'SLA_POLICY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another active policy covers this record type and priority' using errcode = '23505', hint = 'SLA_POLICY_TAKEN';
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a policy needs a name, a record type and positive minutes' using errcode = '22023', hint = 'SLA_POLICY_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."sla_policies" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) to authenticated, service_role;

-- Starts a record's clocks from the policy for its type and priority (the
-- exact priority first, then the policy without one). Starting again, as
-- when the priority changes, recomputes the due times of the open clocks
-- from when they started.
create or replace function "better_supabase"."start_sla_clocks"(subject_type text, subject_id text, priority text, trusted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_policy "better_supabase"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "better_supabase"."sla_policies" x
  where x."tenant_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "better_supabase"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "better_supabase"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "better_supabase"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "better_supabase"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$$;
revoke execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) to authenticated, service_role;

-- Moves a record's clocks: responded meets the response clock and starts
-- the next-response clock; resolved meets every open clock; reopened starts
-- a new resolution clock; paused and resumed stop and restart them, moving
-- the due times by the pause.
create or replace function "better_supabase"."record_sla_event"(subject_type text, subject_id text, event text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_clock "better_supabase"."sla_clocks";
  v_policy "better_supabase"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "better_supabase"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "better_supabase"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    null;
  end loop;
  select x.* into v_policy from "better_supabase"."sla_clocks" c join "better_supabase"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "better_supabase"."sla_clocks" ("tenant_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."tenant_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$$;
revoke execute on function "better_supabase"."record_sla_event"(text, text, text) from public, anon;
grant execute on function "better_supabase"."record_sla_event"(text, text, text) to authenticated, service_role;

-- A record's clocks the caller can see, newest first, with their state:
-- running, paused, met, breached; and the seconds left.
create or replace function "better_supabase"."sla_clocks_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
    'state', case
      when x."met_at" is not null then 'met'
      when x."paused_at" is not null then 'paused'
      when x."due_at" < now() then 'breached'
      else 'running' end,
    'secondsLeft', case when x."met_at" is null then extract(epoch from x."due_at" - coalesce(x."paused_at", now()))::integer end
  ) order by x."created_at" desc, x."metric"), '[]'::jsonb)
  from "better_supabase"."sla_clocks" x
  where x."subject_type" = sla_clocks_of.subject_type and x."subject_id" = sla_clocks_of.subject_id
$$;
revoke execute on function "better_supabase"."sla_clocks_of"(text, text) from public, anon;
grant execute on function "better_supabase"."sla_clocks_of"(text, text) to authenticated, service_role;

-- Records warnings and breaches of running clocks and notifies the record's
-- watchers. Run it every minute or so from a job. Returns how many changed.
create or replace function "better_supabase"."check_sla_clocks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clock "better_supabase"."sla_clocks";
  v_count integer := 0;
  v_claims text;
begin
  for v_clock in
    update "better_supabase"."sla_clocks" x set "breached_at" = now()
    where x."met_at" is null and x."paused_at" is null and x."breached_at" is null and x."due_at" < now()
    returning *
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "warned_at" = now()
    from "better_supabase"."sla_policies" y
    where y."id" = x."policy_id" and x."met_at" is null and x."paused_at" is null and x."warned_at" is null
      and x."breached_at" is null
      and now() >= x."started_at" + (x."due_at" - x."started_at") * y."warn_at_percent" / 100.0
    returning x.*
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."check_sla_clocks"() from public, anon, authenticated;
grant execute on function "better_supabase"."check_sla_clocks"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
create policy bsb_tenant_scope on "better_supabase"."sla_policies" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
create policy bsb_tenant_scope on "better_supabase"."sla_clocks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.sla.api: entry points for the Data API.
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

create or replace function "api"."sla_due_at"(start timestamptz, minutes integer, business boolean)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sla_due_at"($1, $2, $3) $$;
revoke execute on function "api"."sla_due_at"(timestamptz, integer, boolean) from public, anon;
grant execute on function "api"."sla_due_at"(timestamptz, integer, boolean) to authenticated, service_role;

create or replace function "api"."save_sla_policy"(tenant uuid, policy uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_sla_policy"($1, $2, $3) $$;
revoke execute on function "api"."save_sla_policy"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_sla_policy"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."start_sla_clocks"(subject_type text, subject_id text, priority text, trusted boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_sla_clocks"($1, $2, $3, $4) $$;
revoke execute on function "api"."start_sla_clocks"(text, text, text, boolean) from public, anon;
grant execute on function "api"."start_sla_clocks"(text, text, text, boolean) to authenticated, service_role;

create or replace function "api"."record_sla_event"(subject_type text, subject_id text, event text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_sla_event"($1, $2, $3) $$;
revoke execute on function "api"."record_sla_event"(text, text, text) from public, anon;
grant execute on function "api"."record_sla_event"(text, text, text) to authenticated, service_role;

create or replace function "api"."sla_clocks_of"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sla_clocks_of"($1, $2) $$;
revoke execute on function "api"."sla_clocks_of"(text, text) from public, anon;
grant execute on function "api"."sla_clocks_of"(text, text) to authenticated, service_role;

create or replace function "api"."check_sla_clocks"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_sla_clocks"() $$;
revoke execute on function "api"."check_sla_clocks"() from public, anon, authenticated;
grant execute on function "api"."check_sla_clocks"() to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:3a470193710382c34f047abbf9d2b499106a119c4e117a44c502d2ac46999a8a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block sla@1 managed
-- @bsb-hash sha256:4201f4f89ace2363cf974f70d07320a178777442a02a6803bae5f2ce76d3f838
-- Service levels on any registered record: first response, next response and resolution clocks from a policy per type and priority, business hours, pauses while the record waits, and warnings and breaches a job records.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Service levels on any record: response and resolution clocks from a
-- policy per record type and priority, in business hours, paused while the
-- record waits, with warnings and breaches recorded by a job.
create table if not exists "better_supabase"."sla_policies" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "name" text not null check (length("name") between 1 and 200),
  "priority" text,
  "first_response_minutes" integer check ("first_response_minutes" > 0),
  "next_response_minutes" integer check ("next_response_minutes" > 0),
  "resolution_minutes" integer check ("resolution_minutes" > 0),
  "warn_at_percent" smallint not null default 80 check ("warn_at_percent" between 1 and 99),
  "business_hours" boolean not null default false,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists sla_policies_match_idx on "better_supabase"."sla_policies" ("org_id", "subject_type", coalesce("priority", '')) where "archived_at" is null;
alter table "better_supabase"."sla_policies" enable row level security;
revoke all on "better_supabase"."sla_policies" from anon, authenticated;
grant select on "better_supabase"."sla_policies" to authenticated;
grant all on "better_supabase"."sla_policies" to service_role;
drop policy if exists sla_policies_read on "better_supabase"."sla_policies";
create policy sla_policies_read on "better_supabase"."sla_policies" for select to authenticated
using ("org_id" in (select better_supabase.tenant_ids_with('sla.read')));

create table if not exists "better_supabase"."sla_clocks" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "policy_id" uuid references "better_supabase"."sla_policies" ("id") on delete set null,
  "metric" text not null check ("metric" in ('first_response', 'next_response', 'resolution')),
  "started_at" timestamptz not null,
  "due_at" timestamptz not null,
  "paused_at" timestamptz,
  "paused_seconds" integer not null default 0,
  "warned_at" timestamptz,
  "breached_at" timestamptz,
  "met_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create unique index if not exists sla_clocks_open_idx on "better_supabase"."sla_clocks" ("subject_type", "subject_id", "metric") where "met_at" is null;
create index if not exists sla_clocks_due_idx on "better_supabase"."sla_clocks" ("due_at") where "met_at" is null and "paused_at" is null;
create index if not exists sla_clocks_policy_idx on "better_supabase"."sla_clocks" ("policy_id");
alter table "better_supabase"."sla_clocks" enable row level security;
revoke all on "better_supabase"."sla_clocks" from anon, authenticated;
grant select on "better_supabase"."sla_clocks" to authenticated;
grant all on "better_supabase"."sla_clocks" to service_role;
drop policy if exists sla_clocks_read on "better_supabase"."sla_clocks";
create policy sla_clocks_read on "better_supabase"."sla_clocks" for select to authenticated
using ("org_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));

-- The time minutes of working time after start: business hours on the
-- configured weekdays in the configured time zone, or plain minutes.
create or replace function "better_supabase"."sla_due_at"(start timestamptz, minutes integer, business boolean)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_left integer := sla_due_at.minutes;
  v_local timestamp := sla_due_at.start at time zone 'UTC';
  v_open timestamp;
  v_close timestamp;
  v_take integer;
begin
  if not sla_due_at.business then
    return sla_due_at.start + make_interval(mins => sla_due_at.minutes);
  end if;
  for v_day in 0..400 loop
    v_open := date_trunc('day', v_local) + '09:00'::time;
    v_close := date_trunc('day', v_local) + '17:00'::time;
    if extract(isodow from v_local)::integer = any ('{1,2,3,4,5}'::integer[]) and v_local < v_close then
      v_local := greatest(v_local, v_open);
      v_take := least(v_left, (extract(epoch from v_close - v_local) / 60)::integer);
      v_local := v_local + make_interval(mins => v_take);
      v_left := v_left - v_take;
      if v_left <= 0 then
        return v_local at time zone 'UTC';
      end if;
    end if;
    v_local := date_trunc('day', v_local) + interval '1 day';
  end loop;
  raise exception 'no business hours within 400 days' using errcode = '22023', hint = 'SLA_HOURS_INVALID';
end;
$$;
revoke execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) from public, anon;
grant execute on function "better_supabase"."sla_due_at"(timestamptz, integer, boolean) to authenticated, service_role;

-- Creates or changes a policy: name, subjectType, priority (null for every
-- priority), firstResponseMinutes, nextResponseMinutes, resolutionMinutes,
-- warnAtPercent, businessHours, archived.
create or replace function "better_supabase"."save_sla_policy"(tenant uuid, policy uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_sla_policy.policy;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_sla_policy.tenant, 'sla.manage'), false)) then
    raise exception 'not allowed to manage service levels' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."sla_policies" ("org_id", "subject_type", "name", "priority", "first_response_minutes", "next_response_minutes", "resolution_minutes", "warn_at_percent", "business_hours")
      values (save_sla_policy.tenant, save_sla_policy.attrs ->> 'subjectType', save_sla_policy.attrs ->> 'name', save_sla_policy.attrs ->> 'priority',
        (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer, (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer,
        (save_sla_policy.attrs ->> 'resolutionMinutes')::integer, coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, 80),
        coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, false))
      returning "id" into v_id;
    else
      update "better_supabase"."sla_policies" x set
        "name" = coalesce(save_sla_policy.attrs ->> 'name', x."name"),
        "priority" = case when save_sla_policy.attrs ? 'priority' then save_sla_policy.attrs ->> 'priority' else x."priority" end,
        "first_response_minutes" = case when save_sla_policy.attrs ? 'firstResponseMinutes' then (save_sla_policy.attrs ->> 'firstResponseMinutes')::integer else x."first_response_minutes" end,
        "next_response_minutes" = case when save_sla_policy.attrs ? 'nextResponseMinutes' then (save_sla_policy.attrs ->> 'nextResponseMinutes')::integer else x."next_response_minutes" end,
        "resolution_minutes" = case when save_sla_policy.attrs ? 'resolutionMinutes' then (save_sla_policy.attrs ->> 'resolutionMinutes')::integer else x."resolution_minutes" end,
        "warn_at_percent" = coalesce((save_sla_policy.attrs ->> 'warnAtPercent')::smallint, x."warn_at_percent"),
        "business_hours" = coalesce((save_sla_policy.attrs ->> 'businessHours')::boolean, x."business_hours"),
        "archived_at" = case when coalesce((save_sla_policy.attrs ->> 'archived')::boolean, false) then coalesce(x."archived_at", now()) else x."archived_at" end,
        "updated_at" = now()
      where x."id" = v_id and x."org_id" = save_sla_policy.tenant;
      if not found then
        raise exception 'policy not found' using errcode = 'P0002', hint = 'SLA_POLICY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another active policy covers this record type and priority' using errcode = '23505', hint = 'SLA_POLICY_TAKEN';
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a policy needs a name, a record type and positive minutes' using errcode = '22023', hint = 'SLA_POLICY_INVALID';
  end;
  return (select to_jsonb(x) from "better_supabase"."sla_policies" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_sla_policy"(uuid, uuid, jsonb) to authenticated, service_role;

-- Starts a record's clocks from the policy for its type and priority (the
-- exact priority first, then the policy without one). Starting again, as
-- when the priority changes, recomputes the due times of the open clocks
-- from when they started.
create or replace function "better_supabase"."start_sla_clocks"(subject_type text, subject_id text, priority text, trusted boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_policy "better_supabase"."sla_policies";
  v_metric text;
  v_minutes integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if not (start_sla_clocks.trusted and pg_trigger_depth() > 0) and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to start clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  select * into v_policy from "better_supabase"."sla_policies" x
  where x."org_id"::text = v_tenant and x."subject_type" = start_sla_clocks.subject_type and x."archived_at" is null
    and (x."priority" = start_sla_clocks.priority or x."priority" is null)
  order by x."priority" nulls last
  limit 1;
  if v_policy."id" is null then
    return '[]'::jsonb;
  end if;
  foreach v_metric in array array['first_response', 'resolution'] loop
    v_minutes := case v_metric when 'first_response' then v_policy."first_response_minutes" else v_policy."resolution_minutes" end;
    if v_minutes is null then
      continue;
    end if;
    update "better_supabase"."sla_clocks" x set "policy_id" = v_policy."id",
      "due_at" = "better_supabase"."sla_due_at"(x."started_at", v_minutes, v_policy."business_hours") + make_interval(secs => x."paused_seconds")
    where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id
      and x."metric" = v_metric and x."met_at" is null;
    if not found and not exists (
      select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = start_sla_clocks.subject_type and x."subject_id" = start_sla_clocks.subject_id and x."metric" = v_metric
    ) then
      insert into "better_supabase"."sla_clocks" ("org_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."org_id", start_sla_clocks.subject_type, start_sla_clocks.subject_id, v_policy."id", v_metric, now(),
        "better_supabase"."sla_due_at"(now(), v_minutes, v_policy."business_hours"));
    end if;
  end loop;
  return "better_supabase"."sla_clocks_of"(start_sla_clocks.subject_type, start_sla_clocks.subject_id);
end;
$$;
revoke execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."start_sla_clocks"(text, text, text, boolean) to authenticated, service_role;

-- Moves a record's clocks: responded meets the response clock and starts
-- the next-response clock; resolved meets every open clock; reopened starts
-- a new resolution clock; paused and resumed stop and restart them, moving
-- the due times by the pause.
create or replace function "better_supabase"."record_sla_event"(subject_type text, subject_id text, event text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text := null::text;
  v_clock "better_supabase"."sla_clocks";
  v_policy "better_supabase"."sla_policies";
  v_meet text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_tenant is null then
    raise exception 'unknown record' using errcode = 'P0002', hint = 'SLA_SUBJECT_INVALID';
  end if;
  if pg_trigger_depth() = 0 and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to move clocks on this record' using errcode = '42501', hint = 'SLA_FORBIDDEN';
  end if;
  case record_sla_event.event
    when 'responded' then v_meet := array['first_response', 'next_response'];
    when 'resolved' then v_meet := array['first_response', 'next_response', 'resolution'];
    when 'paused' then
      update "better_supabase"."sla_clocks" x set "paused_at" = now()
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'resumed' then
      update "better_supabase"."sla_clocks" x set
        "due_at" = x."due_at" + (now() - x."paused_at"),
        "paused_seconds" = x."paused_seconds" + extract(epoch from now() - x."paused_at")::integer,
        "paused_at" = null
      where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
        and x."met_at" is null and x."paused_at" is not null;
      return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
    when 'reopened' then v_meet := array[]::text[];
    else
      raise exception 'event is responded, resolved, reopened, paused or resumed' using errcode = '22023', hint = 'SLA_EVENT_INVALID';
  end case;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "met_at" = now(), "paused_at" = null
    where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id
      and x."met_at" is null and x."metric" = any (v_meet)
    returning *
  loop
    null;
  end loop;
  select x.* into v_policy from "better_supabase"."sla_clocks" c join "better_supabase"."sla_policies" x on x."id" = c."policy_id"
  where c."subject_type" = record_sla_event.subject_type and c."subject_id" = record_sla_event.subject_id
  order by c."created_at" desc limit 1;
  if v_policy."id" is not null then
    if record_sla_event.event = 'responded' and v_policy."next_response_minutes" is not null
      and exists (select 1 from "better_supabase"."sla_clocks" x where x."subject_type" = record_sla_event.subject_type and x."subject_id" = record_sla_event.subject_id and x."metric" = 'resolution' and x."met_at" is null) then
      insert into "better_supabase"."sla_clocks" ("org_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."org_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'next_response', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."next_response_minutes", v_policy."business_hours"))
      on conflict do nothing;
    elsif record_sla_event.event = 'reopened' and v_policy."resolution_minutes" is not null then
      insert into "better_supabase"."sla_clocks" ("org_id", "subject_type", "subject_id", "policy_id", "metric", "started_at", "due_at")
      values (v_policy."org_id", record_sla_event.subject_type, record_sla_event.subject_id, v_policy."id", 'resolution', now(),
        "better_supabase"."sla_due_at"(now(), v_policy."resolution_minutes", v_policy."business_hours"))
      on conflict do nothing;
    end if;
  end if;
  return "better_supabase"."sla_clocks_of"(record_sla_event.subject_type, record_sla_event.subject_id);
end;
$$;
revoke execute on function "better_supabase"."record_sla_event"(text, text, text) from public, anon;
grant execute on function "better_supabase"."record_sla_event"(text, text, text) to authenticated, service_role;

-- A record's clocks the caller can see, newest first, with their state:
-- running, paused, met, breached; and the seconds left.
create or replace function "better_supabase"."sla_clocks_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) || jsonb_build_object(
    'state', case
      when x."met_at" is not null then 'met'
      when x."paused_at" is not null then 'paused'
      when x."due_at" < now() then 'breached'
      else 'running' end,
    'secondsLeft', case when x."met_at" is null then extract(epoch from x."due_at" - coalesce(x."paused_at", now()))::integer end
  ) order by x."created_at" desc, x."metric"), '[]'::jsonb)
  from "better_supabase"."sla_clocks" x
  where x."subject_type" = sla_clocks_of.subject_type and x."subject_id" = sla_clocks_of.subject_id
$$;
revoke execute on function "better_supabase"."sla_clocks_of"(text, text) from public, anon;
grant execute on function "better_supabase"."sla_clocks_of"(text, text) to authenticated, service_role;

-- Records warnings and breaches of running clocks and notifies the record's
-- watchers. Run it every minute or so from a job. Returns how many changed.
create or replace function "better_supabase"."check_sla_clocks"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_clock "better_supabase"."sla_clocks";
  v_count integer := 0;
  v_claims text;
begin
  for v_clock in
    update "better_supabase"."sla_clocks" x set "breached_at" = now()
    where x."met_at" is null and x."paused_at" is null and x."breached_at" is null and x."due_at" < now()
    returning *
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  for v_clock in
    update "better_supabase"."sla_clocks" x set "warned_at" = now()
    from "better_supabase"."sla_policies" y
    where y."id" = x."policy_id" and x."met_at" is null and x."paused_at" is null and x."warned_at" is null
      and x."breached_at" is null
      and now() >= x."started_at" + (x."due_at" - x."started_at") * y."warn_at_percent" / 100.0
    returning x.*
  loop
    null;
    
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."check_sla_clocks"() from public, anon, authenticated;
grant execute on function "better_supabase"."check_sla_clocks"() to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_policies";
create policy bsb_tenant_scope on "better_supabase"."sla_policies" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('sla.read')))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."sla_clocks";
create policy bsb_tenant_scope on "better_supabase"."sla_clocks" as restrictive
  for all to authenticated
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('sla.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'))
  )
  with check ("org_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_099_sla.sql
-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:3a470193710382c34f047abbf9d2b499106a119c4e117a44c502d2ac46999a8a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
