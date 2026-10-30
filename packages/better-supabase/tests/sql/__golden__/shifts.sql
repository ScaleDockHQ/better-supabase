-- ==== alone: schema supabase/schemas/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block shifts@1 managed
-- @bsb-hash sha256:2c5d00f46527a56ac165ba712eed49edf8483f6212ceccb8d56a72d977757374
-- Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Shifts: templates that generate shifts, shifts planned in draft and
-- published, assignments checked for overlap, leave, qualifications and rest,
-- open shift requests, swaps between members, and availability.

create extension if not exists btree_gist with schema extensions;

create table if not exists "better_supabase"."shift_templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  -- An end at or before the start runs into the next day.
  "starts_time" time not null,
  "ends_time" time not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  -- Qualification type keys (qualifications block) everyone on the shift holds.
  "required_qualifications" text[] not null default '{}',
  -- ISO weekdays, 1 (Monday) to 7 (Sunday), generate_shifts creates shifts on.
  "weekdays" integer[] not null default '{1,2,3,4,5}' check ("weekdays" <@ array[1, 2, 3, 4, 5, 6, 7]),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "shift_templates_tenant_idx" on "better_supabase"."shift_templates" ("tenant_id", "name");
create index if not exists "shift_templates_team_idx" on "better_supabase"."shift_templates" ("team_id") where "team_id" is not null;
create index if not exists "shift_templates_location_idx" on "better_supabase"."shift_templates" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shift_templates" enable row level security;
revoke all on "better_supabase"."shift_templates" from public, anon, authenticated;
grant select on "better_supabase"."shift_templates" to authenticated;
grant all on "better_supabase"."shift_templates" to service_role;
drop policy if exists shift_templates_read on "better_supabase"."shift_templates";
create policy shift_templates_read on "better_supabase"."shift_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shifts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "template_id" uuid,
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  "required_qualifications" text[] not null default '{}',
  -- draft: planners see it; published: everyone with shifts.read does.
  "status" text not null default 'draft' check ("status" in ('draft', 'published', 'canceled')),
  "note" text check ("note" is null or length("note") <= 2000),
  "published_at" timestamptz,
  "canceled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" > "starts_at"),
  check ("ends_at" - "starts_at" <= interval '24 hours'),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "template_id") references "better_supabase"."shift_templates" ("tenant_id", "id") on delete set null ("template_id")
);
create index if not exists "shifts_tenant_idx" on "better_supabase"."shifts" ("tenant_id", "starts_at");
create index if not exists "shifts_template_idx" on "better_supabase"."shifts" ("tenant_id", "template_id") where "template_id" is not null;
create index if not exists "shifts_team_idx" on "better_supabase"."shifts" ("team_id") where "team_id" is not null;
create index if not exists "shifts_location_idx" on "better_supabase"."shifts" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shifts" enable row level security;
revoke all on "better_supabase"."shifts" from public, anon, authenticated;
grant select on "better_supabase"."shifts" to authenticated;
grant all on "better_supabase"."shifts" to service_role;
drop policy if exists shifts_read on "better_supabase"."shifts";
create policy shifts_read on "better_supabase"."shifts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))));

create table if not exists "better_supabase"."shift_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shift_id" uuid not null,
  "user_id" uuid not null,
  -- requested: the member asked for an open shift; released: no longer on it.
  "status" text not null default 'assigned' check ("status" in ('assigned', 'requested', 'released')),
  -- The shift's times, copied so the exclusion constraint can read them.
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "assigned_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("shift_id", "user_id"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "shift_id") references "better_supabase"."shifts" ("tenant_id", "id") on delete cascade,
  constraint "shift_assignments_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("starts_at", "ends_at") with &&
  ) where ("status" = 'assigned')
);
create index if not exists "shift_assignments_tenant_idx" on "better_supabase"."shift_assignments" ("tenant_id", "shift_id");
create index if not exists "shift_assignments_user_idx" on "better_supabase"."shift_assignments" ("user_id", "starts_at");
alter table "better_supabase"."shift_assignments" enable row level security;
revoke all on "better_supabase"."shift_assignments" from public, anon, authenticated;
grant select on "better_supabase"."shift_assignments" to authenticated;
grant all on "better_supabase"."shift_assignments" to service_role;
drop policy if exists shift_assignments_read on "better_supabase"."shift_assignments";
create policy shift_assignments_read on "better_supabase"."shift_assignments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shift_swaps" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "assignment_id" uuid not null,
  "from_user_id" uuid not null,
  "to_user_id" uuid not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'canceled')),
  "approval_id" uuid,
  "note" text check ("note" is null or length("note") <= 2000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check ("to_user_id" <> "from_user_id"),
  foreign key ("tenant_id", "assignment_id") references "better_supabase"."shift_assignments" ("tenant_id", "id") on delete cascade
);
create index if not exists "shift_swaps_tenant_idx" on "better_supabase"."shift_swaps" ("tenant_id", "assignment_id");
create unique index if not exists "shift_swaps_pending_idx" on "better_supabase"."shift_swaps" ("assignment_id") where "status" = 'pending';
create index if not exists "shift_swaps_to_user_idx" on "better_supabase"."shift_swaps" ("to_user_id");
alter table "better_supabase"."shift_swaps" enable row level security;
revoke all on "better_supabase"."shift_swaps" from public, anon, authenticated;
grant select on "better_supabase"."shift_swaps" to authenticated;
grant all on "better_supabase"."shift_swaps" to service_role;
drop policy if exists shift_swaps_read on "better_supabase"."shift_swaps";
create policy shift_swaps_read on "better_supabase"."shift_swaps"
  for select to authenticated
  using ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')));

create table if not exists "better_supabase"."shift_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "on_date" date not null,
  -- Both null: the whole day.
  "from_time" time,
  "until_time" time,
  "kind" text not null check ("kind" in ('available', 'unavailable', 'preferred')),
  "note" text check ("note" is null or length("note") <= 500),
  "created_at" timestamptz not null default now(),
  check (("from_time" is null) = ("until_time" is null)),
  check ("until_time" is null or "until_time" > "from_time"),
  unique ("tenant_id", "user_id", "on_date")
);
create index if not exists "shift_availability_day_idx" on "better_supabase"."shift_availability" ("tenant_id", "on_date");
alter table "better_supabase"."shift_availability" enable row level security;
revoke all on "better_supabase"."shift_availability" from public, anon, authenticated;
grant select on "better_supabase"."shift_availability" to authenticated;
grant all on "better_supabase"."shift_availability" to service_role;
drop policy if exists shift_availability_read on "better_supabase"."shift_availability";
create policy shift_availability_read on "better_supabase"."shift_availability"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')));

-- Creates a shift template, or changes one (template_id). An end at or before
-- the start runs into the next day. weekdays are ISO weekdays (1 is Monday)
-- generate_shifts creates shifts on.
create or replace function "better_supabase"."save_shift_template"(tenant uuid, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift_template.required_qualifications, '{}')) k where k is not null order by k);
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift_template.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a shift template needs a name of at most 200 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    raise exception 'a shift template needs a start and an end time' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    raise exception 'weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift_template.team_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.template_id is null then
    insert into "better_supabase"."shift_templates" ("tenant_id", "name", "team_id", "location_id", "starts_time", "ends_time", "break_minutes", "headcount", "required_qualifications", "weekdays")
    values (save_shift_template.tenant, v_name, save_shift_template.team_id, save_shift_template.location_id, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update "better_supabase"."shift_templates" x set
      "name" = v_name,
      "team_id" = save_shift_template.team_id,
      "location_id" = save_shift_template.location_id,
      "starts_time" = save_shift_template.starts_time,
      "ends_time" = save_shift_template.ends_time,
      "break_minutes" = coalesce(save_shift_template.break_minutes, 0),
      "headcount" = coalesce(save_shift_template.headcount, 1),
      "required_qualifications" = v_required,
      "weekdays" = v_weekdays,
      "updated_at" = now(),
      "archived_at" = null
    where x."id" = save_shift_template.template_id and x."tenant_id" = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) from public, anon;
grant execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) to authenticated, service_role;

-- Archives a template: generate_shifts no longer takes it; its shifts stay.
create or replace function "better_supabase"."archive_shift_template"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_templates" x where x."id" = archive_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "better_supabase"."shift_templates" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_shift_template"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_shift_template"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_shift_templates"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'teamId', x."team_id", 'locationId', x."location_id", 'startsTime', to_char(x."starts_time", 'HH24:MI'), 'endsTime', to_char(x."ends_time", 'HH24:MI'), 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'weekdays', to_jsonb(x."weekdays"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."shift_templates" x
  where x."tenant_id" = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_shift_templates"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_shift_templates"(uuid, boolean) to authenticated, service_role;

-- Creates draft shifts from a template on each of its weekdays from from_date
-- until_date (at most 92 days), in the block's time zone. A day that
-- already has the template's shift at the same start is skipped. Returns the
-- shifts it created.
create or replace function "better_supabase"."generate_shifts"(tenant uuid, template_id uuid, from_date date, until_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_template "better_supabase"."shift_templates"%rowtype;
  v_row "better_supabase"."shifts"%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', generate_shifts.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_template from "better_supabase"."shift_templates" x
  where x."id" = generate_shifts.template_id and x."tenant_id" = generate_shifts.tenant and x."archived_at" is null;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= 92 then
    raise exception 'generate_shifts covers at most 92 days' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template."weekdays"));
    v_starts := (v_day + v_template."starts_time") at time zone 'UTC';
    v_ends := (v_day + v_template."ends_time" + case when v_template."ends_time" <= v_template."starts_time" then interval '1 day' else interval '0' end) at time zone 'UTC';
    continue when exists (
      select 1 from "better_supabase"."shifts" x
      where x."tenant_id" = v_template."tenant_id" and x."template_id" = v_template."id" and x."starts_at" = v_starts
    );
    insert into "better_supabase"."shifts" ("tenant_id", "template_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "created_by")
    values (v_template."tenant_id", v_template."id", v_template."team_id", v_template."location_id", v_starts, v_ends, v_template."break_minutes", v_template."headcount", v_template."required_qualifications", (select auth.uid()))
    returning * into v_row;
    null;
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return v_created;
end;
$$;
revoke execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) from public, anon;
grant execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) to authenticated, service_role;

-- Creates a draft shift, or changes one (shift_id). Changing the times moves
-- its assignments with it; a move that overlaps another shift of an assigned
-- member is refused.
drop function if exists "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid, jsonb);
create or replace function "better_supabase"."save_shift"(tenant uuid, starts_at timestamptz, ends_at timestamptz, team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift.required_qualifications, '{}')) k where k is not null order by k);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    raise exception 'a shift ends after it starts' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    raise exception 'a shift lasts at most 24 hours' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift.team_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_save"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using save_shift.tenant, save_shift.shift_id;
    end if;
  end;
  if save_shift.shift_id is null then
    insert into "better_supabase"."shifts" ("tenant_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "note", "created_by")
    values (save_shift.tenant, save_shift.team_id, save_shift.location_id, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required, nullif(trim(save_shift.note), ''), (select auth.uid()))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."shifts" x
    where x."id" = save_shift.shift_id and x."tenant_id" = save_shift.tenant
    for update;
    if not found then
      raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
    end if;
    if v_row."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    update "better_supabase"."shifts" x set
      "starts_at" = save_shift.starts_at,
      "ends_at" = save_shift.ends_at,
      "team_id" = save_shift.team_id,
      "location_id" = save_shift.location_id,
      "break_minutes" = coalesce(save_shift.break_minutes, 0),
      "headcount" = coalesce(save_shift.headcount, 1),
      "required_qualifications" = v_required,
      "note" = nullif(trim(save_shift.note), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    begin
      update "better_supabase"."shift_assignments" x set "starts_at" = v_row."starts_at", "ends_at" = v_row."ends_at", "updated_at" = now()
      where x."shift_id" = v_row."id" and (x."starts_at" <> v_row."starts_at" or x."ends_at" <> v_row."ends_at");
    exception when exclusion_violation then
      raise exception 'an assigned member has another shift at the new time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) from public, anon;
grant execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) to authenticated, service_role;

-- Cancels a shift and releases its assignments. Assigned members are
-- notified. Canceling one already canceled changes nothing.
create or replace function "better_supabase"."cancel_shift"(shift_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_assignment "better_supabase"."shift_assignments"%rowtype;
  v_users jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shifts" x where x."id" = cancel_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to cancel shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'canceled' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    v_users := coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb);
    update "better_supabase"."shifts" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    for v_assignment in
      update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
      where x."shift_id" = v_row."id" and x."status" <> 'released'
      returning x.*
    loop
      null;
    end loop;
    null;
    if jsonb_array_length(v_users) > 0 then
      
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_shift"(uuid, text) to authenticated, service_role;

-- Publishes the draft shifts that start from from_date to until_date (days in the
-- block's time zone), for one team or all. Members then see them, and the
-- assigned members are notified. Returns how many it published.
create or replace function "better_supabase"."publish_shifts"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', publish_shifts.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to publish shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_row in
    update "better_supabase"."shifts" x set "status" = 'published', "published_at" = now(), "updated_at" = now()
    where x."tenant_id" = publish_shifts.tenant
      and x."status" = 'draft'
      and x."starts_at" >= publish_shifts.from_date::timestamp at time zone 'UTC'
      and x."starts_at" < (publish_shifts.until_date + 1)::timestamp at time zone 'UTC'
      and (publish_shifts.team_id is null or x."team_id" = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    null;
    if jsonb_array_length(coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb)) > 0 then
      
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) to authenticated, service_role;

-- Checks that a member may work a shift: no other assigned shift overlaps,
-- no approved leave falls on its day, they hold its required qualifications
-- and they keep the minimum rest between shifts. Returns warnings (with
-- qualificationCheck "warn") and raises otherwise.
create or replace function "better_supabase"."shift_assignment_check"(shift_id uuid, user_id uuid, assignment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from "better_supabase"."shifts" x where x."id" = shift_assignment_check.shift_id;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if shift_assignment_check.user_id is null or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_shift."tenant_id" and mm."user_id" = shift_assignment_check.user_id and mm."disabled_at" is null) then
    raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at", v_shift."ends_at")
  ) then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at" - interval '11 hours', v_shift."ends_at" + interval '11 hours')
  ) then
    raise exception 'the member would have less than 11 hours between shifts' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_REST_TOO_SHORT';
  end if;
  return v_warnings;
end;
$$;
revoke execute on function "better_supabase"."shift_assignment_check"(uuid, uuid, uuid) from public, anon, authenticated;

-- Assigns a member to a shift. Returns the assignment with its warnings.
-- Assigning someone already on the shift changes nothing.
create or replace function "better_supabase"."assign_shift"(shift_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = assign_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = assign_shift.user_id;
  if found and v_row."status" = 'assigned' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", assign_shift.user_id, v_row."id");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", assign_shift.user_id;
    end if;
  end;
  begin
    insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", assign_shift.user_id, 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  exception when exclusion_violation then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end;
  null;
  if v_shift."status" = 'published' then
    
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."assign_shift"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."assign_shift"(uuid, uuid) to authenticated, service_role;

-- Takes a member off a shift, or turns down their request for it.
create or replace function "better_supabase"."unassign_shift"(assignment_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = unassign_shift.assignment_id for update;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  v_was := v_row."status";
  if v_was <> 'released' then
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    if v_was = 'assigned' and v_shift."status" = 'published' then
      
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."unassign_shift"(uuid, text) to authenticated, service_role;

-- Asks for a place on a published open shift that hasn't started. A planner
-- decides with decide_shift_request.
create or replace function "better_supabase"."request_open_shift"(shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_user uuid := (select auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = request_open_shift.shift_id;
  if not found or v_shift."status" = 'draft' then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if v_user is null or not coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.request'), false) then
    raise exception 'not allowed to request shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  if v_shift."starts_at" <= now() then
    raise exception 'the shift has started' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = v_user;
  if found and v_row."status" <> 'released' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  perform "better_supabase"."shift_assignment_check"(v_shift."id", v_user, v_row."id");
  insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_user, 'requested', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'requested', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_open_shift"(uuid) from public, anon;
grant execute on function "better_supabase"."request_open_shift"(uuid) to authenticated, service_role;

-- Approves a request for an open shift (the member is assigned after the
-- same checks as assign_shift) or turns it down.
create or replace function "better_supabase"."decide_shift_request"(assignment_id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = decide_shift_request.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to decide shift requests' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'requested' then
    raise exception 'the assignment isn''t a pending request' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
    v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", v_row."user_id", v_row."id");
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", v_row."user_id";
    end if;
  end;
    begin
      update "better_supabase"."shift_assignments" x set "status" = 'assigned', "starts_at" = v_shift."starts_at", "ends_at" = v_shift."ends_at", "assigned_by" = (select auth.uid()), "updated_at" = now()
      where x."id" = v_row."id"
      returning x.* into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
    
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."decide_shift_request"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."decide_shift_request"(uuid, boolean) to authenticated, service_role;

-- Offers an assigned shift that hasn't started to another member. A manager
-- decides with decide_shift_swap; the member who asked may withdraw it there.
create or replace function "better_supabase"."request_shift_swap"(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row."user_id" or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = request_shift_swap.to_user_id and mm."disabled_at" is null) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "better_supabase"."shift_swaps" ("tenant_id", "assignment_id", "from_user_id", "to_user_id", "note")
  values (v_row."tenant_id", v_row."id", v_row."user_id", request_shift_swap.to_user_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  null;
  
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) to authenticated, service_role;

-- Approves a pending swap (the other member takes the shift after the same
-- checks as assign_shift) or rejects it. The member who asked may withdraw it
-- (approve false). approval_id links an approvals request.
create or replace function "better_supabase"."decide_shift_swap"(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "better_supabase"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."tenant_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_user_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null then
    raise exception 'approval_id needs the approvals block' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "better_supabase"."shift_assignment_check"(v_shift."id", v_swap."to_user_id", null);
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    begin
      insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_swap."to_user_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
  end if;
  update "better_supabase"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid())
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  null;
  if v_status <> 'canceled' then
    
  end if;
  if v_status = 'approved' then
    
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) to authenticated, service_role;

-- Sets a member's availability on a day: available, unavailable or
-- preferred, for the whole day or from_time to until_time. kind null clears
-- the day. Planners (shifts.write) set it for others with user_id.
create or replace function "better_supabase"."set_shift_availability"(tenant uuid, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_availability"%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_user = (select auth.uid()) then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.request'), false)) then
      raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to set another member''s availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if set_shift_availability.on_date is null then
    raise exception 'on_date is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.kind is null then
    delete from "better_supabase"."shift_availability" x
    where x."tenant_id" = set_shift_availability.tenant and x."user_id" = v_user and x."on_date" = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ('available', 'unavailable', 'preferred') then
    raise exception 'kind is one of available, unavailable, preferred' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    raise exception 'from_time and until_time are both set, with until_time after from_time, or both null' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    raise exception 'a note is at most 500 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  insert into "better_supabase"."shift_availability" ("tenant_id", "user_id", "on_date", "from_time", "until_time", "kind", "note")
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind, nullif(trim(set_shift_availability.note), ''))
  on conflict ("tenant_id", "user_id", "on_date") do update set
    "from_time" = excluded."from_time",
    "until_time" = excluded."until_time",
    "kind" = excluded."kind",
    "note" = excluded."note"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'onDate', v_row."on_date", 'fromTime', to_char(v_row."from_time", 'HH24:MI'), 'untilTime', to_char(v_row."until_time", 'HH24:MI'), 'kind', v_row."kind", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) to authenticated, service_role;

-- The availability the caller may read from from_date to until_date: their own,
-- or everyone's (or one member's) with shifts.write.
create or replace function "better_supabase"."list_shift_availability"(tenant uuid, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'onDate', x."on_date", 'fromTime', to_char(x."from_time", 'HH24:MI'), 'untilTime', to_char(x."until_time", 'HH24:MI'), 'kind', x."kind", 'note', x."note", 'createdAt', x."created_at") order by x."on_date", x."user_id"), '[]'::jsonb)
  from "better_supabase"."shift_availability" x
  where x."tenant_id" = list_shift_availability.tenant
    and x."on_date" between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x."user_id" = list_shift_availability.user_id)
$$;
revoke execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) to authenticated, service_role;

-- The shifts the caller may read that start from from_date to until_date (days in
-- the block's time zone), for one team or all, each with its assigned and
-- requested members. Members see published shifts; planners also drafts.
create or replace function "better_supabase"."roster"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."status", y."user_id")
    from "better_supabase"."shift_assignments" y
    where y."shift_id" = x."id" and y."status" <> 'released'
  ), '[]'::jsonb)) order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."shifts" x
  where x."tenant_id" = roster.tenant
    and x."starts_at" >= (roster.from_date)::timestamp at time zone 'UTC'
    and x."starts_at" < (roster.until_date + 1)::timestamp at time zone 'UTC'
    and (roster.team_id is null or x."team_id" = roster.team_id)
$$;
revoke execute on function "better_supabase"."roster"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."roster"(uuid, date, date, uuid) to authenticated, service_role;

-- The caller's shifts (assigned or requested) that start from since to until,
-- in every organization, each with its assignment.
create or replace function "better_supabase"."my_shifts"(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignment', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_at"), '[]'::jsonb)
  from "better_supabase"."shift_assignments" y
  join "better_supabase"."shifts" x on x."id" = y."shift_id"
  where y."user_id" = (select auth.uid())
    and y."status" in ('assigned', 'requested')
    and x."status" <> 'draft'
    and x."starts_at" >= coalesce(my_shifts.since, now())
    and x."starts_at" < coalesce(my_shifts.until, now() + interval '30 days')
$$;
revoke execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) to authenticated, service_role;

-- The hours each member is planned for in the week from week_start (shifts
-- not canceled, breaks taken off), next to their contract hours when the
-- employees block keeps contracts.
create or replace function "better_supabase"."shift_hours"(tenant uuid, week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', shift_hours.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to read planned hours' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if shift_hours.week_start is null then
    raise exception 'week_start is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.shifts,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.shifts, p.planned, null::numeric as contract
      from (
        select y."user_id" as user_id, count(*)::integer as shifts, round((extract(epoch from sum(x."ends_at" - make_interval(mins => x."break_minutes") - x."starts_at")) / 3600)::numeric, 2) as planned
        from "better_supabase"."shift_assignments" y
        join "better_supabase"."shifts" x on x."id" = y."shift_id"
        where y."tenant_id" = shift_hours.tenant
          and y."status" = 'assigned'
          and x."status" <> 'canceled'
          and x."starts_at" >= (shift_hours.week_start)::timestamp at time zone 'UTC'
          and x."starts_at" < (shift_hours.week_start + 7)::timestamp at time zone 'UTC'
        group by y."user_id"
      ) p
    ) u
  );
end;
$$;
revoke execute on function "better_supabase"."shift_hours"(uuid, date) from public, anon;
grant execute on function "better_supabase"."shift_hours"(uuid, date) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_select on "better_supabase"."shift_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_update on "better_supabase"."shift_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
create policy bsb_tenant_scope_select on "better_supabase"."shifts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
create policy bsb_tenant_scope_insert on "better_supabase"."shifts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
create policy bsb_tenant_scope_update on "better_supabase"."shifts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
create policy bsb_tenant_scope_delete on "better_supabase"."shifts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."shift_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."shift_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_select on "better_supabase"."shift_swaps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_swaps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_update on "better_supabase"."shift_swaps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_swaps" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_select on "better_supabase"."shift_availability" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_availability" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_update on "better_supabase"."shift_availability" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_availability" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:1885529dd31ecefd0b84d5f3f56b949fcd6011a51a38cbeec6dd8c7bf0fc1545
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block shifts@1 managed
-- @bsb-hash sha256:9351789c8817b8a7c32e59d1f37dfe047033558a77b19d5f2889f7bfd327394b
-- Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Shifts: templates that generate shifts, shifts planned in draft and
-- published, assignments checked for overlap, leave, qualifications and rest,
-- open shift requests, swaps between members, and availability.

create extension if not exists btree_gist with schema extensions;

create table if not exists "better_supabase"."shift_templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid references "better_supabase"."assets" ("id") on delete set null,
  -- An end at or before the start runs into the next day.
  "starts_time" time not null,
  "ends_time" time not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  -- Qualification type keys (qualifications block) everyone on the shift holds.
  "required_qualifications" text[] not null default '{}',
  -- ISO weekdays, 1 (Monday) to 7 (Sunday), generate_shifts creates shifts on.
  "weekdays" integer[] not null default '{1,2,3,4,5}' check ("weekdays" <@ array[1, 2, 3, 4, 5, 6, 7]),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "shift_templates_tenant_idx" on "better_supabase"."shift_templates" ("tenant_id", "name");
create index if not exists "shift_templates_team_idx" on "better_supabase"."shift_templates" ("team_id") where "team_id" is not null;
create index if not exists "shift_templates_location_idx" on "better_supabase"."shift_templates" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shift_templates" enable row level security;
revoke all on "better_supabase"."shift_templates" from public, anon, authenticated;
grant select on "better_supabase"."shift_templates" to authenticated;
grant all on "better_supabase"."shift_templates" to service_role;
drop policy if exists shift_templates_read on "better_supabase"."shift_templates";
create policy shift_templates_read on "better_supabase"."shift_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shifts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "template_id" uuid,
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid references "better_supabase"."assets" ("id") on delete set null,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  "required_qualifications" text[] not null default '{}',
  -- draft: planners see it; published: everyone with shifts.read does.
  "status" text not null default 'draft' check ("status" in ('draft', 'published', 'canceled')),
  "note" text check ("note" is null or length("note") <= 2000),
  "published_at" timestamptz,
  "canceled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" > "starts_at"),
  check ("ends_at" - "starts_at" <= interval '24 hours'),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "template_id") references "better_supabase"."shift_templates" ("tenant_id", "id") on delete set null ("template_id")
);
create index if not exists "shifts_tenant_idx" on "better_supabase"."shifts" ("tenant_id", "starts_at");
create index if not exists "shifts_template_idx" on "better_supabase"."shifts" ("tenant_id", "template_id") where "template_id" is not null;
create index if not exists "shifts_team_idx" on "better_supabase"."shifts" ("team_id") where "team_id" is not null;
create index if not exists "shifts_location_idx" on "better_supabase"."shifts" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shifts" enable row level security;
revoke all on "better_supabase"."shifts" from public, anon, authenticated;
grant select on "better_supabase"."shifts" to authenticated;
grant all on "better_supabase"."shifts" to service_role;
drop policy if exists shifts_read on "better_supabase"."shifts";
create policy shifts_read on "better_supabase"."shifts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))));

create table if not exists "better_supabase"."shift_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shift_id" uuid not null,
  "user_id" uuid not null,
  -- requested: the member asked for an open shift; released: no longer on it.
  "status" text not null default 'assigned' check ("status" in ('assigned', 'requested', 'released')),
  -- The shift's times, copied so the exclusion constraint can read them.
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "assigned_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("shift_id", "user_id"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "shift_id") references "better_supabase"."shifts" ("tenant_id", "id") on delete cascade,
  constraint "shift_assignments_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("starts_at", "ends_at") with &&
  ) where ("status" = 'assigned')
);
create index if not exists "shift_assignments_tenant_idx" on "better_supabase"."shift_assignments" ("tenant_id", "shift_id");
create index if not exists "shift_assignments_user_idx" on "better_supabase"."shift_assignments" ("user_id", "starts_at");
alter table "better_supabase"."shift_assignments" enable row level security;
revoke all on "better_supabase"."shift_assignments" from public, anon, authenticated;
grant select on "better_supabase"."shift_assignments" to authenticated;
grant all on "better_supabase"."shift_assignments" to service_role;
drop policy if exists shift_assignments_read on "better_supabase"."shift_assignments";
create policy shift_assignments_read on "better_supabase"."shift_assignments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shift_swaps" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "assignment_id" uuid not null,
  "from_user_id" uuid not null,
  "to_user_id" uuid not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'canceled')),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check ("to_user_id" <> "from_user_id"),
  foreign key ("tenant_id", "assignment_id") references "better_supabase"."shift_assignments" ("tenant_id", "id") on delete cascade
);
create index if not exists "shift_swaps_tenant_idx" on "better_supabase"."shift_swaps" ("tenant_id", "assignment_id");
create unique index if not exists "shift_swaps_pending_idx" on "better_supabase"."shift_swaps" ("assignment_id") where "status" = 'pending';
create index if not exists "shift_swaps_to_user_idx" on "better_supabase"."shift_swaps" ("to_user_id");
create index if not exists "shift_swaps_approval_idx" on "better_supabase"."shift_swaps" ("approval_id") where "approval_id" is not null;
alter table "better_supabase"."shift_swaps" enable row level security;
revoke all on "better_supabase"."shift_swaps" from public, anon, authenticated;
grant select on "better_supabase"."shift_swaps" to authenticated;
grant all on "better_supabase"."shift_swaps" to service_role;
drop policy if exists shift_swaps_read on "better_supabase"."shift_swaps";
create policy shift_swaps_read on "better_supabase"."shift_swaps"
  for select to authenticated
  using ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')));

create table if not exists "better_supabase"."shift_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "on_date" date not null,
  -- Both null: the whole day.
  "from_time" time,
  "until_time" time,
  "kind" text not null check ("kind" in ('available', 'unavailable', 'preferred')),
  "note" text check ("note" is null or length("note") <= 500),
  "created_at" timestamptz not null default now(),
  check (("from_time" is null) = ("until_time" is null)),
  check ("until_time" is null or "until_time" > "from_time"),
  unique ("tenant_id", "user_id", "on_date")
);
create index if not exists "shift_availability_day_idx" on "better_supabase"."shift_availability" ("tenant_id", "on_date");
alter table "better_supabase"."shift_availability" enable row level security;
revoke all on "better_supabase"."shift_availability" from public, anon, authenticated;
grant select on "better_supabase"."shift_availability" to authenticated;
grant all on "better_supabase"."shift_availability" to service_role;
drop policy if exists shift_availability_read on "better_supabase"."shift_availability";
create policy shift_availability_read on "better_supabase"."shift_availability"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')));

-- Creates a shift template, or changes one (template_id). An end at or before
-- the start runs into the next day. weekdays are ISO weekdays (1 is Monday)
-- generate_shifts creates shifts on.
create or replace function "better_supabase"."save_shift_template"(tenant uuid, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift_template.required_qualifications, '{}')) k where k is not null order by k);
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift_template.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a shift template needs a name of at most 200 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    raise exception 'a shift template needs a start and an end time' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    raise exception 'weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift_template.team_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.location_id is not null and not exists (
    select 1 from "better_supabase"."assets" o where o."id" = save_shift_template.location_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the location isn''t an asset in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if exists (
    select 1 from unnest(coalesce(v_required, '{}')) k
    where not exists (
      select 1 from "better_supabase"."qualification_types" o
      where o."tenant_id" = save_shift_template.tenant and o."key" = k and o."archived_at" is null
    )
  ) then
    raise exception 'every required qualification is a qualification type key of this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.template_id is null then
    insert into "better_supabase"."shift_templates" ("tenant_id", "name", "team_id", "location_id", "starts_time", "ends_time", "break_minutes", "headcount", "required_qualifications", "weekdays")
    values (save_shift_template.tenant, v_name, save_shift_template.team_id, save_shift_template.location_id, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update "better_supabase"."shift_templates" x set
      "name" = v_name,
      "team_id" = save_shift_template.team_id,
      "location_id" = save_shift_template.location_id,
      "starts_time" = save_shift_template.starts_time,
      "ends_time" = save_shift_template.ends_time,
      "break_minutes" = coalesce(save_shift_template.break_minutes, 0),
      "headcount" = coalesce(save_shift_template.headcount, 1),
      "required_qualifications" = v_required,
      "weekdays" = v_weekdays,
      "updated_at" = now(),
      "archived_at" = null
    where x."id" = save_shift_template.template_id and x."tenant_id" = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) from public, anon;
grant execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) to authenticated, service_role;

-- Archives a template: generate_shifts no longer takes it; its shifts stay.
create or replace function "better_supabase"."archive_shift_template"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_templates" x where x."id" = archive_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "better_supabase"."shift_templates" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_shift_template"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_shift_template"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_shift_templates"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'teamId', x."team_id", 'locationId', x."location_id", 'startsTime', to_char(x."starts_time", 'HH24:MI'), 'endsTime', to_char(x."ends_time", 'HH24:MI'), 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'weekdays', to_jsonb(x."weekdays"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."shift_templates" x
  where x."tenant_id" = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_shift_templates"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_shift_templates"(uuid, boolean) to authenticated, service_role;

-- Creates draft shifts from a template on each of its weekdays from from_date
-- until_date (at most 92 days), in the block's time zone. A day that
-- already has the template's shift at the same start is skipped. Returns the
-- shifts it created.
create or replace function "better_supabase"."generate_shifts"(tenant uuid, template_id uuid, from_date date, until_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_template "better_supabase"."shift_templates"%rowtype;
  v_row "better_supabase"."shifts"%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', generate_shifts.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_template from "better_supabase"."shift_templates" x
  where x."id" = generate_shifts.template_id and x."tenant_id" = generate_shifts.tenant and x."archived_at" is null;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= 92 then
    raise exception 'generate_shifts covers at most 92 days' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template."weekdays"));
    v_starts := (v_day + v_template."starts_time") at time zone 'UTC';
    v_ends := (v_day + v_template."ends_time" + case when v_template."ends_time" <= v_template."starts_time" then interval '1 day' else interval '0' end) at time zone 'UTC';
    continue when exists (
      select 1 from "better_supabase"."shifts" x
      where x."tenant_id" = v_template."tenant_id" and x."template_id" = v_template."id" and x."starts_at" = v_starts
    );
    insert into "better_supabase"."shifts" ("tenant_id", "template_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "created_by")
    values (v_template."tenant_id", v_template."id", v_template."team_id", v_template."location_id", v_starts, v_ends, v_template."break_minutes", v_template."headcount", v_template."required_qualifications", (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('shift.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status"), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.created',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status")
  );
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return v_created;
end;
$$;
revoke execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) from public, anon;
grant execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) to authenticated, service_role;

-- Creates a draft shift, or changes one (shift_id). Changing the times moves
-- its assignments with it; a move that overlaps another shift of an assigned
-- member is refused.
drop function if exists "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid, jsonb);
create or replace function "better_supabase"."save_shift"(tenant uuid, starts_at timestamptz, ends_at timestamptz, team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift.required_qualifications, '{}')) k where k is not null order by k);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    raise exception 'a shift ends after it starts' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    raise exception 'a shift lasts at most 24 hours' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift.team_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.location_id is not null and not exists (
    select 1 from "better_supabase"."assets" o where o."id" = save_shift.location_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the location isn''t an asset in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if exists (
    select 1 from unnest(coalesce(v_required, '{}')) k
    where not exists (
      select 1 from "better_supabase"."qualification_types" o
      where o."tenant_id" = save_shift.tenant and o."key" = k and o."archived_at" is null
    )
  ) then
    raise exception 'every required qualification is a qualification type key of this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_save"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using save_shift.tenant, save_shift.shift_id;
    end if;
  end;
  if save_shift.shift_id is null then
    insert into "better_supabase"."shifts" ("tenant_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "note", "created_by")
    values (save_shift.tenant, save_shift.team_id, save_shift.location_id, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required, nullif(trim(save_shift.note), ''), (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('shift.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status"), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.created',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status")
  );
  else
    select * into v_row from "better_supabase"."shifts" x
    where x."id" = save_shift.shift_id and x."tenant_id" = save_shift.tenant
    for update;
    if not found then
      raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
    end if;
    if v_row."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    update "better_supabase"."shifts" x set
      "starts_at" = save_shift.starts_at,
      "ends_at" = save_shift.ends_at,
      "team_id" = save_shift.team_id,
      "location_id" = save_shift.location_id,
      "break_minutes" = coalesce(save_shift.break_minutes, 0),
      "headcount" = coalesce(save_shift.headcount, 1),
      "required_qualifications" = v_required,
      "note" = nullif(trim(save_shift.note), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    begin
      update "better_supabase"."shift_assignments" x set "starts_at" = v_row."starts_at", "ends_at" = v_row."ends_at", "updated_at" = now()
      where x."shift_id" = v_row."id" and (x."starts_at" <> v_row."starts_at" or x."ends_at" <> v_row."ends_at");
    exception when exclusion_violation then
      raise exception 'an assigned member has another shift at the new time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) from public, anon;
grant execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) to authenticated, service_role;

-- Cancels a shift and releases its assignments. Assigned members are
-- notified. Canceling one already canceled changes nothing.
create or replace function "better_supabase"."cancel_shift"(shift_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_assignment "better_supabase"."shift_assignments"%rowtype;
  v_users jsonb := '[]'::jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shifts" x where x."id" = cancel_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to cancel shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'canceled' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    v_users := coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb);
    update "better_supabase"."shifts" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    for v_assignment in
      update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
      where x."shift_id" = v_row."id" and x."status" <> 'released'
      returning x.*
    loop
      perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_assignment."tenant_id", 'shiftId', v_assignment."shift_id", 'assignmentId', v_assignment."id", 'userId', v_assignment."user_id", 'startsAt', v_assignment."starts_at", 'endsAt', v_assignment."ends_at", 'reason', 'shift_canceled'), 'shifts/' || v_assignment."shift_id"::text, (v_assignment."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_assignment."id"::text,
    summary => 'Shift assignment released',
    tenant => (v_assignment."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_assignment."tenant_id", 'shiftId', v_assignment."shift_id", 'assignmentId', v_assignment."id", 'userId', v_assignment."user_id", 'startsAt', v_assignment."starts_at", 'endsAt', v_assignment."ends_at", 'reason', 'shift_canceled')
  );
    end loop;
    perform "better_supabase".emit_event('shift.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(cancel_shift.reason), '')), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.cancelled',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift canceled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(cancel_shift.reason), ''))
  );
    if jsonb_array_length(v_users) > 0 then
      v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift.cancelled',
      'tenant', v_row."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_row."id"::text,
      'summary', 'Your shift is canceled',
      'recipients', v_users,
      'key', 'shift.cancelled:' || v_row."id"::text,
      'data', jsonb_build_object('startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_shift"(uuid, text) to authenticated, service_role;

-- Publishes the draft shifts that start from from_date to until_date (days in the
-- block's time zone), for one team or all. Members then see them, and the
-- assigned members are notified. Returns how many it published.
create or replace function "better_supabase"."publish_shifts"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', publish_shifts.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to publish shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_row in
    update "better_supabase"."shifts" x set "status" = 'published', "published_at" = now(), "updated_at" = now()
    where x."tenant_id" = publish_shifts.tenant
      and x."status" = 'draft'
      and x."starts_at" >= publish_shifts.from_date::timestamp at time zone 'UTC'
      and x."starts_at" < (publish_shifts.until_date + 1)::timestamp at time zone 'UTC'
      and (publish_shifts.team_id is null or x."team_id" = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    perform "better_supabase".emit_event('shift.published', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift.published',
    category => 'data',
    target_type => 'shift',
    record_id => v_row."id"::text,
    summary => 'Shift published',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."id", 'teamId', v_row."team_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
    if jsonb_array_length(coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb)) > 0 then
      v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift.published',
      'tenant', v_row."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_row."id"::text,
      'summary', 'Your shift is published',
      'recipients', coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb),
      'key', 'shift.published:' || v_row."id"::text,
      'data', jsonb_build_object('startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) to authenticated, service_role;

-- Checks that a member may work a shift: no other assigned shift overlaps,
-- no approved leave falls on its day, they hold its required qualifications
-- and they keep the minimum rest between shifts. Returns warnings (with
-- qualificationCheck "warn") and raises otherwise.
create or replace function "better_supabase"."shift_assignment_check"(shift_id uuid, user_id uuid, assignment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from "better_supabase"."shifts" x where x."id" = shift_assignment_check.shift_id;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if shift_assignment_check.user_id is null or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_shift."tenant_id" and mm."user_id" = shift_assignment_check.user_id and mm."disabled_at" is null) then
    raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at", v_shift."ends_at")
  ) then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end if;
  if exists (
    select 1 from "better_supabase"."leave_requests" r
    where r."tenant_id" = v_shift."tenant_id"
      and (r."user_id" = shift_assignment_check.user_id or exists (select 1 from "better_supabase"."employees" e where e."id" = r."employee_id" and e."user_id" = shift_assignment_check.user_id))
      and r."approved_at" is not null and r."cancelled_at" is null
      and r."starts_on" <= ((v_shift."ends_at" - interval '1 microsecond') at time zone 'UTC')::date
      and r."ends_on" >= (v_shift."starts_at" at time zone 'UTC')::date
  ) then
    raise exception 'the member has approved leave on the shift''s day' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_ON_LEAVE';
  end if;
  foreach v_key in array v_shift."required_qualifications" loop
    if not coalesce("better_supabase"."qualified_holders"(v_shift."tenant_id", v_key, 'member', (v_shift."starts_at" at time zone 'UTC')::date) ? shift_assignment_check.user_id::text, false) then
      raise exception 'the member doesn''t hold a qualification the shift requires' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_UNQUALIFIED';
    end if;
  end loop;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at" - interval '11 hours', v_shift."ends_at" + interval '11 hours')
  ) then
    raise exception 'the member would have less than 11 hours between shifts' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_REST_TOO_SHORT';
  end if;
  return v_warnings;
end;
$$;
revoke execute on function "better_supabase"."shift_assignment_check"(uuid, uuid, uuid) from public, anon, authenticated;

-- Assigns a member to a shift. Returns the assignment with its warnings.
-- Assigning someone already on the shift changes nothing.
create or replace function "better_supabase"."assign_shift"(shift_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = assign_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = assign_shift.user_id;
  if found and v_row."status" = 'assigned' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", assign_shift.user_id, v_row."id");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", assign_shift.user_id;
    end if;
  end;
  begin
    insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", assign_shift.user_id, 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  exception when exclusion_violation then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end;
  perform "better_supabase".emit_event('shift_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.created',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  if v_shift."status" = 'published' then
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.created',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'You are on a shift',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.created:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."assign_shift"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."assign_shift"(uuid, uuid) to authenticated, service_role;

-- Takes a member off a shift, or turns down their request for it.
create or replace function "better_supabase"."unassign_shift"(assignment_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_was text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = unassign_shift.assignment_id for update;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  v_was := v_row."status";
  if v_was <> 'released' then
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(unassign_shift.reason), '')), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment released',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', nullif(trim(unassign_shift.reason), ''))
  );
    if v_was = 'assigned' and v_shift."status" = 'published' then
      v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.released',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'You are off a shift',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.released:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."unassign_shift"(uuid, text) to authenticated, service_role;

-- Asks for a place on a published open shift that hasn't started. A planner
-- decides with decide_shift_request.
create or replace function "better_supabase"."request_open_shift"(shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_user uuid := (select auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = request_open_shift.shift_id;
  if not found or v_shift."status" = 'draft' then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if v_user is null or not coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.request'), false) then
    raise exception 'not allowed to request shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  if v_shift."starts_at" <= now() then
    raise exception 'the shift has started' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = v_user;
  if found and v_row."status" <> 'released' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  perform "better_supabase"."shift_assignment_check"(v_shift."id", v_user, v_row."id");
  insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_user, 'requested', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'requested', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_open_shift"(uuid) from public, anon;
grant execute on function "better_supabase"."request_open_shift"(uuid) to authenticated, service_role;

-- Approves a request for an open shift (the member is assigned after the
-- same checks as assign_shift) or turns it down.
create or replace function "better_supabase"."decide_shift_request"(assignment_id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = decide_shift_request.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to decide shift requests' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'requested' then
    raise exception 'the assignment isn''t a pending request' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
    v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", v_row."user_id", v_row."id");
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", v_row."user_id";
    end if;
  end;
    begin
      update "better_supabase"."shift_assignments" x set "status" = 'assigned', "starts_at" = v_shift."starts_at", "ends_at" = v_shift."ends_at", "assigned_by" = (select auth.uid()), "updated_at" = now()
      where x."id" = v_row."id"
      returning x.* into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    perform "better_supabase".emit_event('shift_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.created',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.created',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'Your shift request is approved',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.created:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'request_rejected'), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift request rejected',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'request_rejected')
  );
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.released',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'Your shift request is turned down',
      'recipients', jsonb_build_array(v_row."user_id"),
      'key', 'shift_assignment.released:' || v_shift."id"::text || ':' || v_row."user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."decide_shift_request"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."decide_shift_request"(uuid, boolean) to authenticated, service_role;

-- Offers an assigned shift that hasn't started to another member. A manager
-- decides with decide_shift_swap; the member who asked may withdraw it there.
create or replace function "better_supabase"."request_shift_swap"(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row."user_id" or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = request_shift_swap.to_user_id and mm."disabled_at" is null) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "better_supabase"."shift_swaps" ("tenant_id", "assignment_id", "from_user_id", "to_user_id", "note")
  values (v_row."tenant_id", v_row."id", v_row."user_id", request_shift_swap.to_user_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  perform "better_supabase".emit_event('shift_swap.requested', jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id"), 'shifts/' || v_shift."id"::text, (v_swap."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_swap.requested',
    category => 'data',
    target_type => 'shift_swap',
    record_id => v_swap."id"::text,
    summary => 'Shift swap requested',
    tenant => (v_swap."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id")
  );
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_swap.requested',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'A shift swap is offered to you',
      'recipients', jsonb_build_array(v_swap."to_user_id"),
      'key', 'shift_swap.requested:' || v_shift."id"::text || ':' || v_swap."to_user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) to authenticated, service_role;

-- Approves a pending swap (the other member takes the shift after the same
-- checks as assign_shift) or rejects it. The member who asked may withdraw it
-- (approve false). approval_id links an approvals request.
create or replace function "better_supabase"."decide_shift_swap"(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_status text;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "better_supabase"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."tenant_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_user_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" o where o."id" = decide_shift_swap.approval_id and o."tenant_id" = v_swap."tenant_id"
  ) then
    raise exception 'the approval isn''t in this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "better_supabase"."shift_assignment_check"(v_shift."id", v_swap."to_user_id", null);
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('shift_assignment.released', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'swapped'), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.released',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment released',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'reason', 'swapped')
  );
    begin
      insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_swap."to_user_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    perform "better_supabase".emit_event('shift_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'shifts/' || v_row."shift_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_assignment.created',
    category => 'data',
    target_type => 'shift_assignment',
    record_id => v_row."id"::text,
    summary => 'Shift assignment created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'assignmentId', v_row."id", 'userId', v_row."user_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  end if;
  update "better_supabase"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid()), "approval_id" = coalesce(decide_shift_swap.approval_id, x."approval_id")
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  perform "better_supabase".emit_event('shift_swap.decided', jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status"), 'shifts/' || v_shift."id"::text, (v_swap."tenant_id")::text, null, 'better-supabase/shifts');
  perform better_supabase.audit_event(
    event_type => 'shift_swap.decided',
    category => 'data',
    target_type => 'shift_swap',
    record_id => v_swap."id"::text,
    summary => 'Shift swap decided',
    tenant => (v_swap."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_swap."tenant_id", 'swapId', v_swap."id", 'assignmentId', v_swap."assignment_id", 'shiftId', v_shift."id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status")
  );
  if v_status <> 'canceled' then
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_swap.decided',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'Your shift swap is decided',
      'recipients', jsonb_build_array(v_swap."from_user_id"),
      'key', 'shift_swap.decided:' || v_shift."id"::text || ':' || v_swap."from_user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if v_status = 'approved' then
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'shift_assignment.created',
      'tenant', v_shift."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', 'shift',
      'subject_id', v_shift."id"::text,
      'summary', 'You took over a shift',
      'recipients', jsonb_build_array(v_swap."to_user_id"),
      'key', 'shift_assignment.created:' || v_shift."id"::text || ':' || v_swap."to_user_id"::text,
      'data', jsonb_build_object('startsAt', v_shift."starts_at", 'endsAt', v_shift."ends_at")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) to authenticated, service_role;

-- Sets a member's availability on a day: available, unavailable or
-- preferred, for the whole day or from_time to until_time. kind null clears
-- the day. Planners (shifts.write) set it for others with user_id.
create or replace function "better_supabase"."set_shift_availability"(tenant uuid, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_availability"%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_user = (select auth.uid()) then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.request'), false)) then
      raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to set another member''s availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if set_shift_availability.on_date is null then
    raise exception 'on_date is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.kind is null then
    delete from "better_supabase"."shift_availability" x
    where x."tenant_id" = set_shift_availability.tenant and x."user_id" = v_user and x."on_date" = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ('available', 'unavailable', 'preferred') then
    raise exception 'kind is one of available, unavailable, preferred' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    raise exception 'from_time and until_time are both set, with until_time after from_time, or both null' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    raise exception 'a note is at most 500 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  insert into "better_supabase"."shift_availability" ("tenant_id", "user_id", "on_date", "from_time", "until_time", "kind", "note")
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind, nullif(trim(set_shift_availability.note), ''))
  on conflict ("tenant_id", "user_id", "on_date") do update set
    "from_time" = excluded."from_time",
    "until_time" = excluded."until_time",
    "kind" = excluded."kind",
    "note" = excluded."note"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'onDate', v_row."on_date", 'fromTime', to_char(v_row."from_time", 'HH24:MI'), 'untilTime', to_char(v_row."until_time", 'HH24:MI'), 'kind', v_row."kind", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) to authenticated, service_role;

-- The availability the caller may read from from_date to until_date: their own,
-- or everyone's (or one member's) with shifts.write.
create or replace function "better_supabase"."list_shift_availability"(tenant uuid, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'onDate', x."on_date", 'fromTime', to_char(x."from_time", 'HH24:MI'), 'untilTime', to_char(x."until_time", 'HH24:MI'), 'kind', x."kind", 'note', x."note", 'createdAt', x."created_at") order by x."on_date", x."user_id"), '[]'::jsonb)
  from "better_supabase"."shift_availability" x
  where x."tenant_id" = list_shift_availability.tenant
    and x."on_date" between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x."user_id" = list_shift_availability.user_id)
$$;
revoke execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) to authenticated, service_role;

-- The shifts the caller may read that start from from_date to until_date (days in
-- the block's time zone), for one team or all, each with its assigned and
-- requested members. Members see published shifts; planners also drafts.
create or replace function "better_supabase"."roster"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."status", y."user_id")
    from "better_supabase"."shift_assignments" y
    where y."shift_id" = x."id" and y."status" <> 'released'
  ), '[]'::jsonb)) order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."shifts" x
  where x."tenant_id" = roster.tenant
    and x."starts_at" >= (roster.from_date)::timestamp at time zone 'UTC'
    and x."starts_at" < (roster.until_date + 1)::timestamp at time zone 'UTC'
    and (roster.team_id is null or x."team_id" = roster.team_id)
$$;
revoke execute on function "better_supabase"."roster"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."roster"(uuid, date, date, uuid) to authenticated, service_role;

-- The caller's shifts (assigned or requested) that start from since to until,
-- in every organization, each with its assignment.
create or replace function "better_supabase"."my_shifts"(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignment', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_at"), '[]'::jsonb)
  from "better_supabase"."shift_assignments" y
  join "better_supabase"."shifts" x on x."id" = y."shift_id"
  where y."user_id" = (select auth.uid())
    and y."status" in ('assigned', 'requested')
    and x."status" <> 'draft'
    and x."starts_at" >= coalesce(my_shifts.since, now())
    and x."starts_at" < coalesce(my_shifts.until, now() + interval '30 days')
$$;
revoke execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) to authenticated, service_role;

-- The hours each member is planned for in the week from week_start (shifts
-- not canceled, breaks taken off), next to their contract hours when the
-- employees block keeps contracts.
create or replace function "better_supabase"."shift_hours"(tenant uuid, week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', shift_hours.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to read planned hours' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if shift_hours.week_start is null then
    raise exception 'week_start is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.shifts,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.shifts, p.planned, (select k."hours_per_week" from "better_supabase"."employee_contracts" k
        join "better_supabase"."employees" e on e."id" = k."employee_id"
        where e."user_id" = p.user_id and k."tenant_id" = shift_hours.tenant
          and k."starts_on" <= shift_hours.week_start and (k."ends_on" is null or k."ends_on" >= shift_hours.week_start)
        order by k."starts_on" desc
        limit 1)::numeric as contract
      from (
        select y."user_id" as user_id, count(*)::integer as shifts, round((extract(epoch from sum(x."ends_at" - make_interval(mins => x."break_minutes") - x."starts_at")) / 3600)::numeric, 2) as planned
        from "better_supabase"."shift_assignments" y
        join "better_supabase"."shifts" x on x."id" = y."shift_id"
        where y."tenant_id" = shift_hours.tenant
          and y."status" = 'assigned'
          and x."status" <> 'canceled'
          and x."starts_at" >= (shift_hours.week_start)::timestamp at time zone 'UTC'
          and x."starts_at" < (shift_hours.week_start + 7)::timestamp at time zone 'UTC'
        group by y."user_id"
      ) p
    ) u
  );
end;
$$;
revoke execute on function "better_supabase"."shift_hours"(uuid, date) from public, anon;
grant execute on function "better_supabase"."shift_hours"(uuid, date) to authenticated, service_role;

-- Writes a time entry for every assigned shift of the tenant that ended
-- before until and has none yet: its start to its end less the break, with
-- subject shift_assignment. Weeks whose timesheet is submitted and entries
-- that overlap one already there are skipped. Returns how many it wrote.
create or replace function "better_supabase"."shifts_to_time_entries"(tenant uuid, until timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item record;
  v_count integer := 0;
begin
  for v_item in
    select y."id" as id, y."tenant_id" as tenant, y."user_id" as user_id, x."starts_at" as starts_at,
      greatest(x."ends_at" - make_interval(mins => x."break_minutes"), x."starts_at" + interval '1 minute') as ends_at,
      (select o."id" from "better_supabase"."employees" o where o."tenant_id" = y."tenant_id" and o."user_id" = y."user_id" limit 1) as employee_id
    from "better_supabase"."shift_assignments" y
    join "better_supabase"."shifts" x on x."id" = y."shift_id"
    where y."tenant_id" = shifts_to_time_entries.tenant
      and y."status" = 'assigned'
      and x."status" <> 'canceled'
      and x."ends_at" <= least(coalesce(shifts_to_time_entries.until, now()), now())
      and not exists (
        select 1 from "better_supabase"."time_entries" t
        where t."tenant_id" = y."tenant_id" and t."subject_type" = 'shift_assignment' and t."subject_id" = y."id"::text
      )
    order by x."starts_at"
  loop
    begin
      insert into "better_supabase"."time_entries" ("tenant_id", "user_id", "employee_id", "subject_type", "subject_id", "started_at", "ended_at")
      values (v_item.tenant, v_item.user_id, v_item.employee_id, 'shift_assignment', v_item.id::text, v_item.starts_at, v_item.ends_at);
      v_count := v_count + 1;
    exception when exclusion_violation or not_null_violation or sqlstate '55000' then
      null;
    end;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."shifts_to_time_entries"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."shifts_to_time_entries"(uuid, timestamptz) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_select on "better_supabase"."shift_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_update on "better_supabase"."shift_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
create policy bsb_tenant_scope_select on "better_supabase"."shifts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
create policy bsb_tenant_scope_insert on "better_supabase"."shifts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
create policy bsb_tenant_scope_update on "better_supabase"."shifts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
create policy bsb_tenant_scope_delete on "better_supabase"."shifts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."shift_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."shift_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_select on "better_supabase"."shift_swaps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_swaps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_update on "better_supabase"."shift_swaps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_swaps" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_select on "better_supabase"."shift_availability" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_availability" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_update on "better_supabase"."shift_availability" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_availability" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:1885529dd31ecefd0b84d5f3f56b949fcd6011a51a38cbeec6dd8c7bf0fc1545
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block shifts@1 managed
-- @bsb-hash sha256:317bec2c9e2a47c12416bfaeb8f8dcd0569c6fcfc8ecfb340eddd418569dd3c8
-- Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.
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
    drop policy if exists bsb_tenant_scope on "app_private"."shift_templates";
    drop policy if exists bsb_tenant_scope_select on "app_private"."shift_templates";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_templates";
    drop policy if exists bsb_tenant_scope_update on "app_private"."shift_templates";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."shifts";
    drop policy if exists bsb_tenant_scope_select on "app_private"."shifts";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."shifts";
    drop policy if exists bsb_tenant_scope_update on "app_private"."shifts";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."shifts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."shift_assignments";
    drop policy if exists bsb_tenant_scope_select on "app_private"."shift_assignments";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_assignments";
    drop policy if exists bsb_tenant_scope_update on "app_private"."shift_assignments";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."shift_swaps";
    drop policy if exists bsb_tenant_scope_select on "app_private"."shift_swaps";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_swaps";
    drop policy if exists bsb_tenant_scope_update on "app_private"."shift_swaps";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_swaps";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."shift_availability";
    drop policy if exists bsb_tenant_scope_select on "app_private"."shift_availability";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_availability";
    drop policy if exists bsb_tenant_scope_update on "app_private"."shift_availability";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_availability";
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
-- Shifts: templates that generate shifts, shifts planned in draft and
-- published, assignments checked for overlap, leave, qualifications and rest,
-- open shift requests, swaps between members, and availability.

create extension if not exists btree_gist with schema extensions;

create table if not exists "app_private"."shift_templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  -- An end at or before the start runs into the next day.
  "starts_time" time not null,
  "ends_time" time not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  -- Qualification type keys (qualifications block) everyone on the shift holds.
  "required_qualifications" text[] not null default '{}',
  -- ISO weekdays, 1 (Monday) to 7 (Sunday), generate_shifts creates shifts on.
  "weekdays" integer[] not null default '{1,2,3,4,5}' check ("weekdays" <@ array[1, 2, 3, 4, 5, 6, 7]),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "shift_templates_tenant_idx" on "app_private"."shift_templates" ("tenant_id", "name");
create index if not exists "shift_templates_team_idx" on "app_private"."shift_templates" ("team_id") where "team_id" is not null;
create index if not exists "shift_templates_location_idx" on "app_private"."shift_templates" ("location_id") where "location_id" is not null;
alter table "app_private"."shift_templates" enable row level security;
revoke all on "app_private"."shift_templates" from public, anon, authenticated;
grant select on "app_private"."shift_templates" to authenticated;
grant all on "app_private"."shift_templates" to service_role;
drop policy if exists shift_templates_read on "app_private"."shift_templates";
create policy shift_templates_read on "app_private"."shift_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "app_private"."shifts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "template_id" uuid,
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  "required_qualifications" text[] not null default '{}',
  -- draft: planners see it; published: everyone with shifts.read does.
  "status" text not null default 'draft' check ("status" in ('draft', 'published', 'canceled')),
  "note" text check ("note" is null or length("note") <= 2000),
  "published_at" timestamptz,
  "canceled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" > "starts_at"),
  check ("ends_at" - "starts_at" <= interval '24 hours'),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "template_id") references "app_private"."shift_templates" ("tenant_id", "id") on delete set null ("template_id")
);
create index if not exists "shifts_tenant_idx" on "app_private"."shifts" ("tenant_id", "starts_at");
create index if not exists "shifts_template_idx" on "app_private"."shifts" ("tenant_id", "template_id") where "template_id" is not null;
create index if not exists "shifts_team_idx" on "app_private"."shifts" ("team_id") where "team_id" is not null;
create index if not exists "shifts_location_idx" on "app_private"."shifts" ("location_id") where "location_id" is not null;
alter table "app_private"."shifts" enable row level security;
revoke all on "app_private"."shifts" from public, anon, authenticated;
grant select on "app_private"."shifts" to authenticated;
grant all on "app_private"."shifts" to service_role;
drop policy if exists shifts_read on "app_private"."shifts";
create policy shifts_read on "app_private"."shifts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))));

create table if not exists "app_private"."shift_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shift_id" uuid not null,
  "user_id" uuid not null,
  -- requested: the member asked for an open shift; released: no longer on it.
  "status" text not null default 'assigned' check ("status" in ('assigned', 'requested', 'released')),
  -- The shift's times, copied so the exclusion constraint can read them.
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "assigned_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("shift_id", "user_id"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "shift_id") references "app_private"."shifts" ("tenant_id", "id") on delete cascade,
  constraint "shift_assignments_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("starts_at", "ends_at") with &&
  ) where ("status" = 'assigned')
);
create index if not exists "shift_assignments_tenant_idx" on "app_private"."shift_assignments" ("tenant_id", "shift_id");
create index if not exists "shift_assignments_user_idx" on "app_private"."shift_assignments" ("user_id", "starts_at");
alter table "app_private"."shift_assignments" enable row level security;
revoke all on "app_private"."shift_assignments" from public, anon, authenticated;
grant select on "app_private"."shift_assignments" to authenticated;
grant all on "app_private"."shift_assignments" to service_role;
drop policy if exists shift_assignments_read on "app_private"."shift_assignments";
create policy shift_assignments_read on "app_private"."shift_assignments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "app_private"."shift_swaps" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "assignment_id" uuid not null,
  "from_user_id" uuid not null,
  "to_user_id" uuid not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'canceled')),
  "approval_id" uuid,
  "note" text check ("note" is null or length("note") <= 2000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check ("to_user_id" <> "from_user_id"),
  foreign key ("tenant_id", "assignment_id") references "app_private"."shift_assignments" ("tenant_id", "id") on delete cascade
);
create index if not exists "shift_swaps_tenant_idx" on "app_private"."shift_swaps" ("tenant_id", "assignment_id");
create unique index if not exists "shift_swaps_pending_idx" on "app_private"."shift_swaps" ("assignment_id") where "status" = 'pending';
create index if not exists "shift_swaps_to_user_idx" on "app_private"."shift_swaps" ("to_user_id");
alter table "app_private"."shift_swaps" enable row level security;
revoke all on "app_private"."shift_swaps" from public, anon, authenticated;
grant select on "app_private"."shift_swaps" to authenticated;
grant all on "app_private"."shift_swaps" to service_role;
drop policy if exists shift_swaps_read on "app_private"."shift_swaps";
create policy shift_swaps_read on "app_private"."shift_swaps"
  for select to authenticated
  using ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')));

create table if not exists "app_private"."shift_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "on_date" date not null,
  -- Both null: the whole day.
  "from_time" time,
  "until_time" time,
  "kind" text not null check ("kind" in ('available', 'unavailable', 'preferred')),
  "note" text check ("note" is null or length("note") <= 500),
  "created_at" timestamptz not null default now(),
  check (("from_time" is null) = ("until_time" is null)),
  check ("until_time" is null or "until_time" > "from_time"),
  unique ("tenant_id", "user_id", "on_date")
);
create index if not exists "shift_availability_day_idx" on "app_private"."shift_availability" ("tenant_id", "on_date");
alter table "app_private"."shift_availability" enable row level security;
revoke all on "app_private"."shift_availability" from public, anon, authenticated;
grant select on "app_private"."shift_availability" to authenticated;
grant all on "app_private"."shift_availability" to service_role;
drop policy if exists shift_availability_read on "app_private"."shift_availability";
create policy shift_availability_read on "app_private"."shift_availability"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')));

-- Creates a shift template, or changes one (template_id). An end at or before
-- the start runs into the next day. weekdays are ISO weekdays (1 is Monday)
-- generate_shifts creates shifts on.
create or replace function "app_private"."save_shift_template"(tenant uuid, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."shift_templates"%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift_template.required_qualifications, '{}')) k where k is not null order by k);
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift_template.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a shift template needs a name of at most 200 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    raise exception 'a shift template needs a start and an end time' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    raise exception 'weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift_template.team_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.template_id is null then
    insert into "app_private"."shift_templates" ("tenant_id", "name", "team_id", "location_id", "starts_time", "ends_time", "break_minutes", "headcount", "required_qualifications", "weekdays")
    values (save_shift_template.tenant, v_name, save_shift_template.team_id, save_shift_template.location_id, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update "app_private"."shift_templates" x set
      "name" = v_name,
      "team_id" = save_shift_template.team_id,
      "location_id" = save_shift_template.location_id,
      "starts_time" = save_shift_template.starts_time,
      "ends_time" = save_shift_template.ends_time,
      "break_minutes" = coalesce(save_shift_template.break_minutes, 0),
      "headcount" = coalesce(save_shift_template.headcount, 1),
      "required_qualifications" = v_required,
      "weekdays" = v_weekdays,
      "updated_at" = now(),
      "archived_at" = null
    where x."id" = save_shift_template.template_id and x."tenant_id" = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) from public, anon;
grant execute on function "app_private"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) to authenticated, service_role;

-- Archives a template: generate_shifts no longer takes it; its shifts stay.
create or replace function "app_private"."archive_shift_template"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."shift_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."shift_templates" x where x."id" = archive_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "app_private"."shift_templates" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."archive_shift_template"(uuid) from public, anon;
grant execute on function "app_private"."archive_shift_template"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_shift_templates"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'teamId', x."team_id", 'locationId', x."location_id", 'startsTime', to_char(x."starts_time", 'HH24:MI'), 'endsTime', to_char(x."ends_time", 'HH24:MI'), 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'weekdays', to_jsonb(x."weekdays"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "app_private"."shift_templates" x
  where x."tenant_id" = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "app_private"."list_shift_templates"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_shift_templates"(uuid, boolean) to authenticated, service_role;

-- Creates draft shifts from a template on each of its weekdays from from_date
-- until_date (at most 92 days), in the block's time zone. A day that
-- already has the template's shift at the same start is skipped. Returns the
-- shifts it created.
create or replace function "app_private"."generate_shifts"(tenant uuid, template_id uuid, from_date date, until_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_template "app_private"."shift_templates"%rowtype;
  v_row "app_private"."shifts"%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', generate_shifts.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_template from "app_private"."shift_templates" x
  where x."id" = generate_shifts.template_id and x."tenant_id" = generate_shifts.tenant and x."archived_at" is null;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= 92 then
    raise exception 'generate_shifts covers at most 92 days' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template."weekdays"));
    v_starts := (v_day + v_template."starts_time") at time zone 'UTC';
    v_ends := (v_day + v_template."ends_time" + case when v_template."ends_time" <= v_template."starts_time" then interval '1 day' else interval '0' end) at time zone 'UTC';
    continue when exists (
      select 1 from "app_private"."shifts" x
      where x."tenant_id" = v_template."tenant_id" and x."template_id" = v_template."id" and x."starts_at" = v_starts
    );
    insert into "app_private"."shifts" ("tenant_id", "template_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "created_by")
    values (v_template."tenant_id", v_template."id", v_template."team_id", v_template."location_id", v_starts, v_ends, v_template."break_minutes", v_template."headcount", v_template."required_qualifications", (select auth.uid()))
    returning * into v_row;
    null;
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return v_created;
end;
$$;
revoke execute on function "app_private"."generate_shifts"(uuid, uuid, date, date) from public, anon;
grant execute on function "app_private"."generate_shifts"(uuid, uuid, date, date) to authenticated, service_role;

-- Creates a draft shift, or changes one (shift_id). Changing the times moves
-- its assignments with it; a move that overlaps another shift of an assigned
-- member is refused.
drop function if exists "app_private"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid, jsonb);
create or replace function "app_private"."save_shift"(tenant uuid, starts_at timestamptz, ends_at timestamptz, team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."shifts"%rowtype;
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift.required_qualifications, '{}')) k where k is not null order by k);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    raise exception 'a shift ends after it starts' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    raise exception 'a shift lasts at most 24 hours' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift.team_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_save"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using save_shift.tenant, save_shift.shift_id;
    end if;
  end;
  if save_shift.shift_id is null then
    insert into "app_private"."shifts" ("tenant_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "note", "created_by")
    values (save_shift.tenant, save_shift.team_id, save_shift.location_id, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required, nullif(trim(save_shift.note), ''), (select auth.uid()))
    returning * into v_row;
    null;
  else
    select * into v_row from "app_private"."shifts" x
    where x."id" = save_shift.shift_id and x."tenant_id" = save_shift.tenant
    for update;
    if not found then
      raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
    end if;
    if v_row."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    update "app_private"."shifts" x set
      "starts_at" = save_shift.starts_at,
      "ends_at" = save_shift.ends_at,
      "team_id" = save_shift.team_id,
      "location_id" = save_shift.location_id,
      "break_minutes" = coalesce(save_shift.break_minutes, 0),
      "headcount" = coalesce(save_shift.headcount, 1),
      "required_qualifications" = v_required,
      "note" = nullif(trim(save_shift.note), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    begin
      update "app_private"."shift_assignments" x set "starts_at" = v_row."starts_at", "ends_at" = v_row."ends_at", "updated_at" = now()
      where x."shift_id" = v_row."id" and (x."starts_at" <> v_row."starts_at" or x."ends_at" <> v_row."ends_at");
    exception when exclusion_violation then
      raise exception 'an assigned member has another shift at the new time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) from public, anon;
grant execute on function "app_private"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) to authenticated, service_role;

-- Cancels a shift and releases its assignments. Assigned members are
-- notified. Canceling one already canceled changes nothing.
create or replace function "app_private"."cancel_shift"(shift_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."shifts"%rowtype;
  v_assignment "app_private"."shift_assignments"%rowtype;
  v_users jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."shifts" x where x."id" = cancel_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to cancel shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'canceled' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    v_users := coalesce((select jsonb_agg(x."user_id") from "app_private"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb);
    update "app_private"."shifts" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    for v_assignment in
      update "app_private"."shift_assignments" x set "status" = 'released', "updated_at" = now()
      where x."shift_id" = v_row."id" and x."status" <> 'released'
      returning x.*
    loop
      null;
    end loop;
    null;
    if jsonb_array_length(v_users) > 0 then
      
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."cancel_shift"(uuid, text) from public, anon;
grant execute on function "app_private"."cancel_shift"(uuid, text) to authenticated, service_role;

-- Publishes the draft shifts that start from from_date to until_date (days in the
-- block's time zone), for one team or all. Members then see them, and the
-- assigned members are notified. Returns how many it published.
create or replace function "app_private"."publish_shifts"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."shifts"%rowtype;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', publish_shifts.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to publish shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_row in
    update "app_private"."shifts" x set "status" = 'published', "published_at" = now(), "updated_at" = now()
    where x."tenant_id" = publish_shifts.tenant
      and x."status" = 'draft'
      and x."starts_at" >= publish_shifts.from_date::timestamp at time zone 'UTC'
      and x."starts_at" < (publish_shifts.until_date + 1)::timestamp at time zone 'UTC'
      and (publish_shifts.team_id is null or x."team_id" = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    null;
    if jsonb_array_length(coalesce((select jsonb_agg(x."user_id") from "app_private"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb)) > 0 then
      
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."publish_shifts"(uuid, date, date, uuid) from public, anon;
grant execute on function "app_private"."publish_shifts"(uuid, date, date, uuid) to authenticated, service_role;

-- Checks that a member may work a shift: no other assigned shift overlaps,
-- no approved leave falls on its day, they hold its required qualifications
-- and they keep the minimum rest between shifts. Returns warnings (with
-- qualificationCheck "warn") and raises otherwise.
create or replace function "app_private"."shift_assignment_check"(shift_id uuid, user_id uuid, assignment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "app_private"."shifts"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from "app_private"."shifts" x where x."id" = shift_assignment_check.shift_id;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if shift_assignment_check.user_id is null or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_shift."tenant_id" and mm."user_id" = shift_assignment_check.user_id and mm."disabled_at" is null) then
    raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  if exists (
    select 1 from "app_private"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at", v_shift."ends_at")
  ) then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end if;
  if exists (
    select 1 from "app_private"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at" - interval '11 hours', v_shift."ends_at" + interval '11 hours')
  ) then
    raise exception 'the member would have less than 11 hours between shifts' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_REST_TOO_SHORT';
  end if;
  return v_warnings;
end;
$$;
revoke execute on function "app_private"."shift_assignment_check"(uuid, uuid, uuid) from public, anon, authenticated;

-- Assigns a member to a shift. Returns the assignment with its warnings.
-- Assigning someone already on the shift changes nothing.
create or replace function "app_private"."assign_shift"(shift_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "app_private"."shifts"%rowtype;
  v_row "app_private"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "app_private"."shifts" x where x."id" = assign_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  select * into v_row from "app_private"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = assign_shift.user_id;
  if found and v_row."status" = 'assigned' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
  end if;
  if (select count(*) from "app_private"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  v_warnings := "app_private"."shift_assignment_check"(v_shift."id", assign_shift.user_id, v_row."id");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", assign_shift.user_id;
    end if;
  end;
  begin
    insert into "app_private"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", assign_shift.user_id, 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  exception when exclusion_violation then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end;
  null;
  if v_shift."status" = 'published' then
    
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "app_private"."assign_shift"(uuid, uuid) from public, anon;
grant execute on function "app_private"."assign_shift"(uuid, uuid) to authenticated, service_role;

-- Takes a member off a shift, or turns down their request for it.
create or replace function "app_private"."unassign_shift"(assignment_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "app_private"."shifts"%rowtype;
  v_row "app_private"."shift_assignments"%rowtype;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."shift_assignments" x where x."id" = unassign_shift.assignment_id for update;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "app_private"."shifts" x where x."id" = v_row."shift_id";
  v_was := v_row."status";
  if v_was <> 'released' then
    update "app_private"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    if v_was = 'assigned' and v_shift."status" = 'published' then
      
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."unassign_shift"(uuid, text) from public, anon;
grant execute on function "app_private"."unassign_shift"(uuid, text) to authenticated, service_role;

-- Asks for a place on a published open shift that hasn't started. A planner
-- decides with decide_shift_request.
create or replace function "app_private"."request_open_shift"(shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "app_private"."shifts"%rowtype;
  v_row "app_private"."shift_assignments"%rowtype;
  v_user uuid := (select auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "app_private"."shifts" x where x."id" = request_open_shift.shift_id;
  if not found or v_shift."status" = 'draft' then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if v_user is null or not coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.request'), false) then
    raise exception 'not allowed to request shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  if v_shift."starts_at" <= now() then
    raise exception 'the shift has started' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_row from "app_private"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = v_user;
  if found and v_row."status" <> 'released' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if (select count(*) from "app_private"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  perform "app_private"."shift_assignment_check"(v_shift."id", v_user, v_row."id");
  insert into "app_private"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_user, 'requested', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'requested', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."request_open_shift"(uuid) from public, anon;
grant execute on function "app_private"."request_open_shift"(uuid) to authenticated, service_role;

-- Approves a request for an open shift (the member is assigned after the
-- same checks as assign_shift) or turns it down.
create or replace function "app_private"."decide_shift_request"(assignment_id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "app_private"."shifts"%rowtype;
  v_row "app_private"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."shift_assignments" x where x."id" = decide_shift_request.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to decide shift requests' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'requested' then
    raise exception 'the assignment isn''t a pending request' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_shift from "app_private"."shifts" x where x."id" = v_row."shift_id" for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    if (select count(*) from "app_private"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
    v_warnings := "app_private"."shift_assignment_check"(v_shift."id", v_row."user_id", v_row."id");
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", v_row."user_id";
    end if;
  end;
    begin
      update "app_private"."shift_assignments" x set "status" = 'assigned', "starts_at" = v_shift."starts_at", "ends_at" = v_shift."ends_at", "assigned_by" = (select auth.uid()), "updated_at" = now()
      where x."id" = v_row."id"
      returning x.* into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
    
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    update "app_private"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "app_private"."decide_shift_request"(uuid, boolean) from public, anon;
grant execute on function "app_private"."decide_shift_request"(uuid, boolean) to authenticated, service_role;

-- Offers an assigned shift that hasn't started to another member. A manager
-- decides with decide_shift_swap; the member who asked may withdraw it there.
create or replace function "app_private"."request_shift_swap"(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "app_private"."shifts"%rowtype;
  v_row "app_private"."shift_assignments"%rowtype;
  v_swap "app_private"."shift_swaps"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "app_private"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row."user_id" or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = request_shift_swap.to_user_id and mm."disabled_at" is null) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "app_private"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "app_private"."shift_swaps" ("tenant_id", "assignment_id", "from_user_id", "to_user_id", "note")
  values (v_row."tenant_id", v_row."id", v_row."user_id", request_shift_swap.to_user_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  null;
  
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "app_private"."request_shift_swap"(uuid, uuid, text) from public, anon;
grant execute on function "app_private"."request_shift_swap"(uuid, uuid, text) to authenticated, service_role;

-- Approves a pending swap (the other member takes the shift after the same
-- checks as assign_shift) or rejects it. The member who asked may withdraw it
-- (approve false). approval_id links an approvals request.
create or replace function "app_private"."decide_shift_swap"(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "app_private"."shifts"%rowtype;
  v_row "app_private"."shift_assignments"%rowtype;
  v_swap "app_private"."shift_swaps"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "app_private"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."tenant_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_user_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null then
    raise exception 'approval_id needs the approvals block' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "app_private"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "app_private"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "app_private"."shift_assignment_check"(v_shift."id", v_swap."to_user_id", null);
    update "app_private"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    begin
      insert into "app_private"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_swap."to_user_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
  end if;
  update "app_private"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid())
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  null;
  if v_status <> 'canceled' then
    
  end if;
  if v_status = 'approved' then
    
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "app_private"."decide_shift_swap"(uuid, boolean, uuid) from public, anon;
grant execute on function "app_private"."decide_shift_swap"(uuid, boolean, uuid) to authenticated, service_role;

-- Sets a member's availability on a day: available, unavailable or
-- preferred, for the whole day or from_time to until_time. kind null clears
-- the day. Planners (shifts.write) set it for others with user_id.
create or replace function "app_private"."set_shift_availability"(tenant uuid, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."shift_availability"%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_user = (select auth.uid()) then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.request'), false)) then
      raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to set another member''s availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if set_shift_availability.on_date is null then
    raise exception 'on_date is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.kind is null then
    delete from "app_private"."shift_availability" x
    where x."tenant_id" = set_shift_availability.tenant and x."user_id" = v_user and x."on_date" = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ('available', 'unavailable', 'preferred') then
    raise exception 'kind is one of available, unavailable, preferred' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    raise exception 'from_time and until_time are both set, with until_time after from_time, or both null' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    raise exception 'a note is at most 500 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  insert into "app_private"."shift_availability" ("tenant_id", "user_id", "on_date", "from_time", "until_time", "kind", "note")
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind, nullif(trim(set_shift_availability.note), ''))
  on conflict ("tenant_id", "user_id", "on_date") do update set
    "from_time" = excluded."from_time",
    "until_time" = excluded."until_time",
    "kind" = excluded."kind",
    "note" = excluded."note"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'onDate', v_row."on_date", 'fromTime', to_char(v_row."from_time", 'HH24:MI'), 'untilTime', to_char(v_row."until_time", 'HH24:MI'), 'kind', v_row."kind", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."set_shift_availability"(uuid, date, text, time, time, text, uuid) from public, anon;
grant execute on function "app_private"."set_shift_availability"(uuid, date, text, time, time, text, uuid) to authenticated, service_role;

-- The availability the caller may read from from_date to until_date: their own,
-- or everyone's (or one member's) with shifts.write.
create or replace function "app_private"."list_shift_availability"(tenant uuid, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'onDate', x."on_date", 'fromTime', to_char(x."from_time", 'HH24:MI'), 'untilTime', to_char(x."until_time", 'HH24:MI'), 'kind', x."kind", 'note', x."note", 'createdAt', x."created_at") order by x."on_date", x."user_id"), '[]'::jsonb)
  from "app_private"."shift_availability" x
  where x."tenant_id" = list_shift_availability.tenant
    and x."on_date" between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x."user_id" = list_shift_availability.user_id)
$$;
revoke execute on function "app_private"."list_shift_availability"(uuid, date, date, uuid) from public, anon;
grant execute on function "app_private"."list_shift_availability"(uuid, date, date, uuid) to authenticated, service_role;

-- The shifts the caller may read that start from from_date to until_date (days in
-- the block's time zone), for one team or all, each with its assigned and
-- requested members. Members see published shifts; planners also drafts.
create or replace function "app_private"."roster"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."status", y."user_id")
    from "app_private"."shift_assignments" y
    where y."shift_id" = x."id" and y."status" <> 'released'
  ), '[]'::jsonb)) order by x."starts_at", x."id"), '[]'::jsonb)
  from "app_private"."shifts" x
  where x."tenant_id" = roster.tenant
    and x."starts_at" >= (roster.from_date)::timestamp at time zone 'UTC'
    and x."starts_at" < (roster.until_date + 1)::timestamp at time zone 'UTC'
    and (roster.team_id is null or x."team_id" = roster.team_id)
$$;
revoke execute on function "app_private"."roster"(uuid, date, date, uuid) from public, anon;
grant execute on function "app_private"."roster"(uuid, date, date, uuid) to authenticated, service_role;

-- The caller's shifts (assigned or requested) that start from since to until,
-- in every organization, each with its assignment.
create or replace function "app_private"."my_shifts"(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignment', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_at"), '[]'::jsonb)
  from "app_private"."shift_assignments" y
  join "app_private"."shifts" x on x."id" = y."shift_id"
  where y."user_id" = (select auth.uid())
    and y."status" in ('assigned', 'requested')
    and x."status" <> 'draft'
    and x."starts_at" >= coalesce(my_shifts.since, now())
    and x."starts_at" < coalesce(my_shifts.until, now() + interval '30 days')
$$;
revoke execute on function "app_private"."my_shifts"(timestamptz, timestamptz) from public, anon;
grant execute on function "app_private"."my_shifts"(timestamptz, timestamptz) to authenticated, service_role;

-- The hours each member is planned for in the week from week_start (shifts
-- not canceled, breaks taken off), next to their contract hours when the
-- employees block keeps contracts.
create or replace function "app_private"."shift_hours"(tenant uuid, week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', shift_hours.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to read planned hours' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if shift_hours.week_start is null then
    raise exception 'week_start is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.shifts,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.shifts, p.planned, null::numeric as contract
      from (
        select y."user_id" as user_id, count(*)::integer as shifts, round((extract(epoch from sum(x."ends_at" - make_interval(mins => x."break_minutes") - x."starts_at")) / 3600)::numeric, 2) as planned
        from "app_private"."shift_assignments" y
        join "app_private"."shifts" x on x."id" = y."shift_id"
        where y."tenant_id" = shift_hours.tenant
          and y."status" = 'assigned'
          and x."status" <> 'canceled'
          and x."starts_at" >= (shift_hours.week_start)::timestamp at time zone 'UTC'
          and x."starts_at" < (shift_hours.week_start + 7)::timestamp at time zone 'UTC'
        group by y."user_id"
      ) p
    ) u
  );
end;
$$;
revoke execute on function "app_private"."shift_hours"(uuid, date) from public, anon;
grant execute on function "app_private"."shift_hours"(uuid, date) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."shift_templates";
drop policy if exists bsb_tenant_scope_select on "app_private"."shift_templates";
create policy bsb_tenant_scope_select on "app_private"."shift_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_templates";
create policy bsb_tenant_scope_insert on "app_private"."shift_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."shift_templates";
create policy bsb_tenant_scope_update on "app_private"."shift_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_templates";
create policy bsb_tenant_scope_delete on "app_private"."shift_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."shifts";
drop policy if exists bsb_tenant_scope_select on "app_private"."shifts";
create policy bsb_tenant_scope_select on "app_private"."shifts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."shifts";
create policy bsb_tenant_scope_insert on "app_private"."shifts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."shifts";
create policy bsb_tenant_scope_update on "app_private"."shifts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."shifts";
create policy bsb_tenant_scope_delete on "app_private"."shifts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."shift_assignments";
drop policy if exists bsb_tenant_scope_select on "app_private"."shift_assignments";
create policy bsb_tenant_scope_select on "app_private"."shift_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_assignments";
create policy bsb_tenant_scope_insert on "app_private"."shift_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."shift_assignments";
create policy bsb_tenant_scope_update on "app_private"."shift_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_assignments";
create policy bsb_tenant_scope_delete on "app_private"."shift_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."shift_swaps";
drop policy if exists bsb_tenant_scope_select on "app_private"."shift_swaps";
create policy bsb_tenant_scope_select on "app_private"."shift_swaps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_swaps";
create policy bsb_tenant_scope_insert on "app_private"."shift_swaps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."shift_swaps";
create policy bsb_tenant_scope_update on "app_private"."shift_swaps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_swaps";
create policy bsb_tenant_scope_delete on "app_private"."shift_swaps" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."shift_availability";
drop policy if exists bsb_tenant_scope_select on "app_private"."shift_availability";
create policy bsb_tenant_scope_select on "app_private"."shift_availability" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."shift_availability";
create policy bsb_tenant_scope_insert on "app_private"."shift_availability" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."shift_availability";
create policy bsb_tenant_scope_update on "app_private"."shift_availability" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."shift_availability";
create policy bsb_tenant_scope_delete on "app_private"."shift_availability" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:1885529dd31ecefd0b84d5f3f56b949fcd6011a51a38cbeec6dd8c7bf0fc1545
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block shifts@1 managed
-- @bsb-hash sha256:15983c199389dab353f8d5e66e75f93b5d9d71904eacfcda341d1810b45d9a29
-- Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Shifts: templates that generate shifts, shifts planned in draft and
-- published, assignments checked for overlap, leave, qualifications and rest,
-- open shift requests, swaps between members, and availability.

create extension if not exists btree_gist with schema extensions;

create table if not exists "better_supabase"."shift_templates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  -- An end at or before the start runs into the next day.
  "starts_time" time not null,
  "ends_time" time not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  -- Qualification type keys (qualifications block) everyone on the shift holds.
  "required_qualifications" text[] not null default '{}',
  -- ISO weekdays, 1 (Monday) to 7 (Sunday), generate_shifts creates shifts on.
  "weekdays" integer[] not null default '{1,2,3,4,5}' check ("weekdays" <@ array[1, 2, 3, 4, 5, 6, 7]),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id")
);
create index if not exists "shift_templates_tenant_idx" on "better_supabase"."shift_templates" ("tenant_id", "name");
create index if not exists "shift_templates_team_idx" on "better_supabase"."shift_templates" ("team_id") where "team_id" is not null;
create index if not exists "shift_templates_location_idx" on "better_supabase"."shift_templates" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shift_templates" enable row level security;
revoke all on "better_supabase"."shift_templates" from public, anon, authenticated;
grant select on "better_supabase"."shift_templates" to authenticated;
grant all on "better_supabase"."shift_templates" to service_role;
drop policy if exists shift_templates_read on "better_supabase"."shift_templates";
create policy shift_templates_read on "better_supabase"."shift_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shifts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "template_id" uuid,
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  "required_qualifications" text[] not null default '{}',
  -- draft: planners see it; published: everyone with shifts.read does.
  "status" text not null default 'draft' check ("status" in ('draft', 'published', 'canceled')),
  "note" text check ("note" is null or length("note") <= 2000),
  "published_at" timestamptz,
  "canceled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" > "starts_at"),
  check ("ends_at" - "starts_at" <= interval '24 hours'),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "template_id") references "better_supabase"."shift_templates" ("tenant_id", "id") on delete set null ("template_id")
);
create index if not exists "shifts_tenant_idx" on "better_supabase"."shifts" ("tenant_id", "starts_at");
create index if not exists "shifts_template_idx" on "better_supabase"."shifts" ("tenant_id", "template_id") where "template_id" is not null;
create index if not exists "shifts_team_idx" on "better_supabase"."shifts" ("team_id") where "team_id" is not null;
create index if not exists "shifts_location_idx" on "better_supabase"."shifts" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shifts" enable row level security;
revoke all on "better_supabase"."shifts" from public, anon, authenticated;
grant select on "better_supabase"."shifts" to authenticated;
grant all on "better_supabase"."shifts" to service_role;
drop policy if exists shifts_read on "better_supabase"."shifts";
create policy shifts_read on "better_supabase"."shifts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))));

create table if not exists "better_supabase"."shift_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "shift_id" uuid not null,
  "user_id" uuid not null,
  -- requested: the member asked for an open shift; released: no longer on it.
  "status" text not null default 'assigned' check ("status" in ('assigned', 'requested', 'released')),
  -- The shift's times, copied so the exclusion constraint can read them.
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "assigned_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("shift_id", "user_id"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "shift_id") references "better_supabase"."shifts" ("tenant_id", "id") on delete cascade,
  constraint "shift_assignments_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("starts_at", "ends_at") with &&
  ) where ("status" = 'assigned')
);
create index if not exists "shift_assignments_tenant_idx" on "better_supabase"."shift_assignments" ("tenant_id", "shift_id");
create index if not exists "shift_assignments_user_idx" on "better_supabase"."shift_assignments" ("user_id", "starts_at");
alter table "better_supabase"."shift_assignments" enable row level security;
revoke all on "better_supabase"."shift_assignments" from public, anon, authenticated;
grant select on "better_supabase"."shift_assignments" to authenticated;
grant all on "better_supabase"."shift_assignments" to service_role;
drop policy if exists shift_assignments_read on "better_supabase"."shift_assignments";
create policy shift_assignments_read on "better_supabase"."shift_assignments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shift_swaps" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "assignment_id" uuid not null,
  "from_user_id" uuid not null,
  "to_user_id" uuid not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'canceled')),
  "approval_id" uuid,
  "note" text check ("note" is null or length("note") <= 2000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check ("to_user_id" <> "from_user_id"),
  foreign key ("tenant_id", "assignment_id") references "better_supabase"."shift_assignments" ("tenant_id", "id") on delete cascade
);
create index if not exists "shift_swaps_tenant_idx" on "better_supabase"."shift_swaps" ("tenant_id", "assignment_id");
create unique index if not exists "shift_swaps_pending_idx" on "better_supabase"."shift_swaps" ("assignment_id") where "status" = 'pending';
create index if not exists "shift_swaps_to_user_idx" on "better_supabase"."shift_swaps" ("to_user_id");
alter table "better_supabase"."shift_swaps" enable row level security;
revoke all on "better_supabase"."shift_swaps" from public, anon, authenticated;
grant select on "better_supabase"."shift_swaps" to authenticated;
grant all on "better_supabase"."shift_swaps" to service_role;
drop policy if exists shift_swaps_read on "better_supabase"."shift_swaps";
create policy shift_swaps_read on "better_supabase"."shift_swaps"
  for select to authenticated
  using ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')));

create table if not exists "better_supabase"."shift_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "on_date" date not null,
  -- Both null: the whole day.
  "from_time" time,
  "until_time" time,
  "kind" text not null check ("kind" in ('available', 'unavailable', 'preferred')),
  "note" text check ("note" is null or length("note") <= 500),
  "created_at" timestamptz not null default now(),
  check (("from_time" is null) = ("until_time" is null)),
  check ("until_time" is null or "until_time" > "from_time"),
  unique ("tenant_id", "user_id", "on_date")
);
create index if not exists "shift_availability_day_idx" on "better_supabase"."shift_availability" ("tenant_id", "on_date");
alter table "better_supabase"."shift_availability" enable row level security;
revoke all on "better_supabase"."shift_availability" from public, anon, authenticated;
grant select on "better_supabase"."shift_availability" to authenticated;
grant all on "better_supabase"."shift_availability" to service_role;
drop policy if exists shift_availability_read on "better_supabase"."shift_availability";
create policy shift_availability_read on "better_supabase"."shift_availability"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')));

-- Creates a shift template, or changes one (template_id). An end at or before
-- the start runs into the next day. weekdays are ISO weekdays (1 is Monday)
-- generate_shifts creates shifts on.
create or replace function "better_supabase"."save_shift_template"(tenant uuid, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift_template.required_qualifications, '{}')) k where k is not null order by k);
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift_template.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a shift template needs a name of at most 200 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    raise exception 'a shift template needs a start and an end time' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    raise exception 'weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift_template.team_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.template_id is null then
    insert into "better_supabase"."shift_templates" ("tenant_id", "name", "team_id", "location_id", "starts_time", "ends_time", "break_minutes", "headcount", "required_qualifications", "weekdays")
    values (save_shift_template.tenant, v_name, save_shift_template.team_id, save_shift_template.location_id, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update "better_supabase"."shift_templates" x set
      "name" = v_name,
      "team_id" = save_shift_template.team_id,
      "location_id" = save_shift_template.location_id,
      "starts_time" = save_shift_template.starts_time,
      "ends_time" = save_shift_template.ends_time,
      "break_minutes" = coalesce(save_shift_template.break_minutes, 0),
      "headcount" = coalesce(save_shift_template.headcount, 1),
      "required_qualifications" = v_required,
      "weekdays" = v_weekdays,
      "updated_at" = now(),
      "archived_at" = null
    where x."id" = save_shift_template.template_id and x."tenant_id" = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) from public, anon;
grant execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) to authenticated, service_role;

-- Archives a template: generate_shifts no longer takes it; its shifts stay.
create or replace function "better_supabase"."archive_shift_template"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_templates" x where x."id" = archive_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "better_supabase"."shift_templates" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_shift_template"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_shift_template"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_shift_templates"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'teamId', x."team_id", 'locationId', x."location_id", 'startsTime', to_char(x."starts_time", 'HH24:MI'), 'endsTime', to_char(x."ends_time", 'HH24:MI'), 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'weekdays', to_jsonb(x."weekdays"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."shift_templates" x
  where x."tenant_id" = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_shift_templates"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_shift_templates"(uuid, boolean) to authenticated, service_role;

-- Creates draft shifts from a template on each of its weekdays from from_date
-- until_date (at most 92 days), in the block's time zone. A day that
-- already has the template's shift at the same start is skipped. Returns the
-- shifts it created.
create or replace function "better_supabase"."generate_shifts"(tenant uuid, template_id uuid, from_date date, until_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_template "better_supabase"."shift_templates"%rowtype;
  v_row "better_supabase"."shifts"%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', generate_shifts.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_template from "better_supabase"."shift_templates" x
  where x."id" = generate_shifts.template_id and x."tenant_id" = generate_shifts.tenant and x."archived_at" is null;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= 92 then
    raise exception 'generate_shifts covers at most 92 days' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template."weekdays"));
    v_starts := (v_day + v_template."starts_time") at time zone 'UTC';
    v_ends := (v_day + v_template."ends_time" + case when v_template."ends_time" <= v_template."starts_time" then interval '1 day' else interval '0' end) at time zone 'UTC';
    continue when exists (
      select 1 from "better_supabase"."shifts" x
      where x."tenant_id" = v_template."tenant_id" and x."template_id" = v_template."id" and x."starts_at" = v_starts
    );
    insert into "better_supabase"."shifts" ("tenant_id", "template_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "created_by")
    values (v_template."tenant_id", v_template."id", v_template."team_id", v_template."location_id", v_starts, v_ends, v_template."break_minutes", v_template."headcount", v_template."required_qualifications", (select auth.uid()))
    returning * into v_row;
    null;
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return v_created;
end;
$$;
revoke execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) from public, anon;
grant execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) to authenticated, service_role;

-- Creates a draft shift, or changes one (shift_id). Changing the times moves
-- its assignments with it; a move that overlaps another shift of an assigned
-- member is refused.
drop function if exists "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid, jsonb);
create or replace function "better_supabase"."save_shift"(tenant uuid, starts_at timestamptz, ends_at timestamptz, team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift.required_qualifications, '{}')) k where k is not null order by k);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    raise exception 'a shift ends after it starts' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    raise exception 'a shift lasts at most 24 hours' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift.team_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_save"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using save_shift.tenant, save_shift.shift_id;
    end if;
  end;
  if save_shift.shift_id is null then
    insert into "better_supabase"."shifts" ("tenant_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "note", "created_by")
    values (save_shift.tenant, save_shift.team_id, save_shift.location_id, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required, nullif(trim(save_shift.note), ''), (select auth.uid()))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."shifts" x
    where x."id" = save_shift.shift_id and x."tenant_id" = save_shift.tenant
    for update;
    if not found then
      raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
    end if;
    if v_row."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    update "better_supabase"."shifts" x set
      "starts_at" = save_shift.starts_at,
      "ends_at" = save_shift.ends_at,
      "team_id" = save_shift.team_id,
      "location_id" = save_shift.location_id,
      "break_minutes" = coalesce(save_shift.break_minutes, 0),
      "headcount" = coalesce(save_shift.headcount, 1),
      "required_qualifications" = v_required,
      "note" = nullif(trim(save_shift.note), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    begin
      update "better_supabase"."shift_assignments" x set "starts_at" = v_row."starts_at", "ends_at" = v_row."ends_at", "updated_at" = now()
      where x."shift_id" = v_row."id" and (x."starts_at" <> v_row."starts_at" or x."ends_at" <> v_row."ends_at");
    exception when exclusion_violation then
      raise exception 'an assigned member has another shift at the new time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) from public, anon;
grant execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) to authenticated, service_role;

-- Cancels a shift and releases its assignments. Assigned members are
-- notified. Canceling one already canceled changes nothing.
create or replace function "better_supabase"."cancel_shift"(shift_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_assignment "better_supabase"."shift_assignments"%rowtype;
  v_users jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shifts" x where x."id" = cancel_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to cancel shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'canceled' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    v_users := coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb);
    update "better_supabase"."shifts" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    for v_assignment in
      update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
      where x."shift_id" = v_row."id" and x."status" <> 'released'
      returning x.*
    loop
      null;
    end loop;
    null;
    if jsonb_array_length(v_users) > 0 then
      
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_shift"(uuid, text) to authenticated, service_role;

-- Publishes the draft shifts that start from from_date to until_date (days in the
-- block's time zone), for one team or all. Members then see them, and the
-- assigned members are notified. Returns how many it published.
create or replace function "better_supabase"."publish_shifts"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', publish_shifts.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to publish shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_row in
    update "better_supabase"."shifts" x set "status" = 'published', "published_at" = now(), "updated_at" = now()
    where x."tenant_id" = publish_shifts.tenant
      and x."status" = 'draft'
      and x."starts_at" >= publish_shifts.from_date::timestamp at time zone 'UTC'
      and x."starts_at" < (publish_shifts.until_date + 1)::timestamp at time zone 'UTC'
      and (publish_shifts.team_id is null or x."team_id" = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    null;
    if jsonb_array_length(coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb)) > 0 then
      
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) to authenticated, service_role;

-- Checks that a member may work a shift: no other assigned shift overlaps,
-- no approved leave falls on its day, they hold its required qualifications
-- and they keep the minimum rest between shifts. Returns warnings (with
-- qualificationCheck "warn") and raises otherwise.
create or replace function "better_supabase"."shift_assignment_check"(shift_id uuid, user_id uuid, assignment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from "better_supabase"."shifts" x where x."id" = shift_assignment_check.shift_id;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if shift_assignment_check.user_id is null or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_shift."tenant_id" and mm."user_id" = shift_assignment_check.user_id and mm."disabled_at" is null) then
    raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at", v_shift."ends_at")
  ) then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at" - interval '11 hours', v_shift."ends_at" + interval '11 hours')
  ) then
    raise exception 'the member would have less than 11 hours between shifts' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_REST_TOO_SHORT';
  end if;
  return v_warnings;
end;
$$;
revoke execute on function "better_supabase"."shift_assignment_check"(uuid, uuid, uuid) from public, anon, authenticated;

-- Assigns a member to a shift. Returns the assignment with its warnings.
-- Assigning someone already on the shift changes nothing.
create or replace function "better_supabase"."assign_shift"(shift_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = assign_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = assign_shift.user_id;
  if found and v_row."status" = 'assigned' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", assign_shift.user_id, v_row."id");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", assign_shift.user_id;
    end if;
  end;
  begin
    insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", assign_shift.user_id, 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  exception when exclusion_violation then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end;
  null;
  if v_shift."status" = 'published' then
    
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."assign_shift"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."assign_shift"(uuid, uuid) to authenticated, service_role;

-- Takes a member off a shift, or turns down their request for it.
create or replace function "better_supabase"."unassign_shift"(assignment_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = unassign_shift.assignment_id for update;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  v_was := v_row."status";
  if v_was <> 'released' then
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    if v_was = 'assigned' and v_shift."status" = 'published' then
      
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."unassign_shift"(uuid, text) to authenticated, service_role;

-- Asks for a place on a published open shift that hasn't started. A planner
-- decides with decide_shift_request.
create or replace function "better_supabase"."request_open_shift"(shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_user uuid := (select auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = request_open_shift.shift_id;
  if not found or v_shift."status" = 'draft' then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if v_user is null or not coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.request'), false) then
    raise exception 'not allowed to request shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  if v_shift."starts_at" <= now() then
    raise exception 'the shift has started' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = v_user;
  if found and v_row."status" <> 'released' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  perform "better_supabase"."shift_assignment_check"(v_shift."id", v_user, v_row."id");
  insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_user, 'requested', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'requested', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_open_shift"(uuid) from public, anon;
grant execute on function "better_supabase"."request_open_shift"(uuid) to authenticated, service_role;

-- Approves a request for an open shift (the member is assigned after the
-- same checks as assign_shift) or turns it down.
create or replace function "better_supabase"."decide_shift_request"(assignment_id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = decide_shift_request.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to decide shift requests' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'requested' then
    raise exception 'the assignment isn''t a pending request' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
    v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", v_row."user_id", v_row."id");
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", v_row."user_id";
    end if;
  end;
    begin
      update "better_supabase"."shift_assignments" x set "status" = 'assigned', "starts_at" = v_shift."starts_at", "ends_at" = v_shift."ends_at", "assigned_by" = (select auth.uid()), "updated_at" = now()
      where x."id" = v_row."id"
      returning x.* into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
    
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."decide_shift_request"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."decide_shift_request"(uuid, boolean) to authenticated, service_role;

-- Offers an assigned shift that hasn't started to another member. A manager
-- decides with decide_shift_swap; the member who asked may withdraw it there.
create or replace function "better_supabase"."request_shift_swap"(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row."user_id" or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = request_shift_swap.to_user_id and mm."disabled_at" is null) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "better_supabase"."shift_swaps" ("tenant_id", "assignment_id", "from_user_id", "to_user_id", "note")
  values (v_row."tenant_id", v_row."id", v_row."user_id", request_shift_swap.to_user_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  null;
  
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) to authenticated, service_role;

-- Approves a pending swap (the other member takes the shift after the same
-- checks as assign_shift) or rejects it. The member who asked may withdraw it
-- (approve false). approval_id links an approvals request.
create or replace function "better_supabase"."decide_shift_swap"(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "better_supabase"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."tenant_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_user_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null then
    raise exception 'approval_id needs the approvals block' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "better_supabase"."shift_assignment_check"(v_shift."id", v_swap."to_user_id", null);
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    begin
      insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_swap."to_user_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
  end if;
  update "better_supabase"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid())
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  null;
  if v_status <> 'canceled' then
    
  end if;
  if v_status = 'approved' then
    
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) to authenticated, service_role;

-- Sets a member's availability on a day: available, unavailable or
-- preferred, for the whole day or from_time to until_time. kind null clears
-- the day. Planners (shifts.write) set it for others with user_id.
create or replace function "better_supabase"."set_shift_availability"(tenant uuid, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_availability"%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_user = (select auth.uid()) then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.request'), false)) then
      raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to set another member''s availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if set_shift_availability.on_date is null then
    raise exception 'on_date is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.kind is null then
    delete from "better_supabase"."shift_availability" x
    where x."tenant_id" = set_shift_availability.tenant and x."user_id" = v_user and x."on_date" = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ('available', 'unavailable', 'preferred') then
    raise exception 'kind is one of available, unavailable, preferred' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    raise exception 'from_time and until_time are both set, with until_time after from_time, or both null' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    raise exception 'a note is at most 500 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  insert into "better_supabase"."shift_availability" ("tenant_id", "user_id", "on_date", "from_time", "until_time", "kind", "note")
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind, nullif(trim(set_shift_availability.note), ''))
  on conflict ("tenant_id", "user_id", "on_date") do update set
    "from_time" = excluded."from_time",
    "until_time" = excluded."until_time",
    "kind" = excluded."kind",
    "note" = excluded."note"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'onDate', v_row."on_date", 'fromTime', to_char(v_row."from_time", 'HH24:MI'), 'untilTime', to_char(v_row."until_time", 'HH24:MI'), 'kind', v_row."kind", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) to authenticated, service_role;

-- The availability the caller may read from from_date to until_date: their own,
-- or everyone's (or one member's) with shifts.write.
create or replace function "better_supabase"."list_shift_availability"(tenant uuid, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'onDate', x."on_date", 'fromTime', to_char(x."from_time", 'HH24:MI'), 'untilTime', to_char(x."until_time", 'HH24:MI'), 'kind', x."kind", 'note', x."note", 'createdAt', x."created_at") order by x."on_date", x."user_id"), '[]'::jsonb)
  from "better_supabase"."shift_availability" x
  where x."tenant_id" = list_shift_availability.tenant
    and x."on_date" between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x."user_id" = list_shift_availability.user_id)
$$;
revoke execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) to authenticated, service_role;

-- The shifts the caller may read that start from from_date to until_date (days in
-- the block's time zone), for one team or all, each with its assigned and
-- requested members. Members see published shifts; planners also drafts.
create or replace function "better_supabase"."roster"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."status", y."user_id")
    from "better_supabase"."shift_assignments" y
    where y."shift_id" = x."id" and y."status" <> 'released'
  ), '[]'::jsonb)) order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."shifts" x
  where x."tenant_id" = roster.tenant
    and x."starts_at" >= (roster.from_date)::timestamp at time zone 'UTC'
    and x."starts_at" < (roster.until_date + 1)::timestamp at time zone 'UTC'
    and (roster.team_id is null or x."team_id" = roster.team_id)
$$;
revoke execute on function "better_supabase"."roster"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."roster"(uuid, date, date, uuid) to authenticated, service_role;

-- The caller's shifts (assigned or requested) that start from since to until,
-- in every organization, each with its assignment.
create or replace function "better_supabase"."my_shifts"(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignment', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_at"), '[]'::jsonb)
  from "better_supabase"."shift_assignments" y
  join "better_supabase"."shifts" x on x."id" = y."shift_id"
  where y."user_id" = (select auth.uid())
    and y."status" in ('assigned', 'requested')
    and x."status" <> 'draft'
    and x."starts_at" >= coalesce(my_shifts.since, now())
    and x."starts_at" < coalesce(my_shifts.until, now() + interval '30 days')
$$;
revoke execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) to authenticated, service_role;

-- The hours each member is planned for in the week from week_start (shifts
-- not canceled, breaks taken off), next to their contract hours when the
-- employees block keeps contracts.
create or replace function "better_supabase"."shift_hours"(tenant uuid, week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', shift_hours.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to read planned hours' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if shift_hours.week_start is null then
    raise exception 'week_start is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.shifts,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.shifts, p.planned, null::numeric as contract
      from (
        select y."user_id" as user_id, count(*)::integer as shifts, round((extract(epoch from sum(x."ends_at" - make_interval(mins => x."break_minutes") - x."starts_at")) / 3600)::numeric, 2) as planned
        from "better_supabase"."shift_assignments" y
        join "better_supabase"."shifts" x on x."id" = y."shift_id"
        where y."tenant_id" = shift_hours.tenant
          and y."status" = 'assigned'
          and x."status" <> 'canceled'
          and x."starts_at" >= (shift_hours.week_start)::timestamp at time zone 'UTC'
          and x."starts_at" < (shift_hours.week_start + 7)::timestamp at time zone 'UTC'
        group by y."user_id"
      ) p
    ) u
  );
end;
$$;
revoke execute on function "better_supabase"."shift_hours"(uuid, date) from public, anon;
grant execute on function "better_supabase"."shift_hours"(uuid, date) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_select on "better_supabase"."shift_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_update on "better_supabase"."shift_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
create policy bsb_tenant_scope_select on "better_supabase"."shifts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
create policy bsb_tenant_scope_insert on "better_supabase"."shifts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
create policy bsb_tenant_scope_update on "better_supabase"."shifts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
create policy bsb_tenant_scope_delete on "better_supabase"."shifts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."shift_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."shift_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_select on "better_supabase"."shift_swaps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_swaps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_update on "better_supabase"."shift_swaps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_swaps" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_select on "better_supabase"."shift_availability" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_availability" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_update on "better_supabase"."shift_availability" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_availability" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.shifts.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid, jsonb);

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

create or replace function "api"."save_shift_template"(tenant uuid, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_shift_template"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) $$;
revoke execute on function "api"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) from public, anon;
grant execute on function "api"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) to authenticated, service_role;

create or replace function "api"."archive_shift_template"(template_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_shift_template"($1) $$;
revoke execute on function "api"."archive_shift_template"(uuid) from public, anon;
grant execute on function "api"."archive_shift_template"(uuid) to authenticated, service_role;

create or replace function "api"."list_shift_templates"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_shift_templates"($1, $2) $$;
revoke execute on function "api"."list_shift_templates"(uuid, boolean) from public, anon;
grant execute on function "api"."list_shift_templates"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."generate_shifts"(tenant uuid, template_id uuid, from_date date, until_date date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."generate_shifts"($1, $2, $3, $4) $$;
revoke execute on function "api"."generate_shifts"(uuid, uuid, date, date) from public, anon;
grant execute on function "api"."generate_shifts"(uuid, uuid, date, date) to authenticated, service_role;

create or replace function "api"."save_shift"(tenant uuid, starts_at timestamptz, ends_at timestamptz, team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_shift"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) from public, anon;
grant execute on function "api"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) to authenticated, service_role;

create or replace function "api"."cancel_shift"(shift_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_shift"($1, $2) $$;
revoke execute on function "api"."cancel_shift"(uuid, text) from public, anon;
grant execute on function "api"."cancel_shift"(uuid, text) to authenticated, service_role;

create or replace function "api"."publish_shifts"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."publish_shifts"($1, $2, $3, $4) $$;
revoke execute on function "api"."publish_shifts"(uuid, date, date, uuid) from public, anon;
grant execute on function "api"."publish_shifts"(uuid, date, date, uuid) to authenticated, service_role;

create or replace function "api"."assign_shift"(shift_id uuid, user_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assign_shift"($1, $2) $$;
revoke execute on function "api"."assign_shift"(uuid, uuid) from public, anon;
grant execute on function "api"."assign_shift"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."unassign_shift"(assignment_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unassign_shift"($1, $2) $$;
revoke execute on function "api"."unassign_shift"(uuid, text) from public, anon;
grant execute on function "api"."unassign_shift"(uuid, text) to authenticated, service_role;

create or replace function "api"."request_open_shift"(shift_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_open_shift"($1) $$;
revoke execute on function "api"."request_open_shift"(uuid) from public, anon;
grant execute on function "api"."request_open_shift"(uuid) to authenticated, service_role;

create or replace function "api"."decide_shift_request"(assignment_id uuid, approve boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_shift_request"($1, $2) $$;
revoke execute on function "api"."decide_shift_request"(uuid, boolean) from public, anon;
grant execute on function "api"."decide_shift_request"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."request_shift_swap"(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_shift_swap"($1, $2, $3) $$;
revoke execute on function "api"."request_shift_swap"(uuid, uuid, text) from public, anon;
grant execute on function "api"."request_shift_swap"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."decide_shift_swap"(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_shift_swap"($1, $2, $3) $$;
revoke execute on function "api"."decide_shift_swap"(uuid, boolean, uuid) from public, anon;
grant execute on function "api"."decide_shift_swap"(uuid, boolean, uuid) to authenticated, service_role;

create or replace function "api"."set_shift_availability"(tenant uuid, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_shift_availability"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."set_shift_availability"(uuid, date, text, time, time, text, uuid) from public, anon;
grant execute on function "api"."set_shift_availability"(uuid, date, text, time, time, text, uuid) to authenticated, service_role;

create or replace function "api"."list_shift_availability"(tenant uuid, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_shift_availability"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_shift_availability"(uuid, date, date, uuid) from public, anon;
grant execute on function "api"."list_shift_availability"(uuid, date, date, uuid) to authenticated, service_role;

create or replace function "api"."roster"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."roster"($1, $2, $3, $4) $$;
revoke execute on function "api"."roster"(uuid, date, date, uuid) from public, anon;
grant execute on function "api"."roster"(uuid, date, date, uuid) to authenticated, service_role;

create or replace function "api"."my_shifts"(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_shifts"($1, $2) $$;
revoke execute on function "api"."my_shifts"(timestamptz, timestamptz) from public, anon;
grant execute on function "api"."my_shifts"(timestamptz, timestamptz) to authenticated, service_role;

create or replace function "api"."shift_hours"(tenant uuid, week_start date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."shift_hours"($1, $2) $$;
revoke execute on function "api"."shift_hours"(uuid, date) from public, anon;
grant execute on function "api"."shift_hours"(uuid, date) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:1885529dd31ecefd0b84d5f3f56b949fcd6011a51a38cbeec6dd8c7bf0fc1545
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block shifts@1 managed
-- @bsb-hash sha256:c4bf849c177b55504690672ae102114cbaf31c00baadcb4fa9d9951f2df0ff70
-- Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Shifts: templates that generate shifts, shifts planned in draft and
-- published, assignments checked for overlap, leave, qualifications and rest,
-- open shift requests, swaps between members, and availability.

create extension if not exists btree_gist with schema extensions;

-- better_supabase.shift_templates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shift_templates" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shift_templates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shift_templates" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."shift_templates" add column if not exists "team_id" uuid references "better_supabase"."teams" ("id") on delete set null;
alter table "better_supabase"."shift_templates" add column if not exists "location_id" uuid;
alter table "better_supabase"."shift_templates" add column if not exists "starts_time" time;
alter table "better_supabase"."shift_templates" add column if not exists "ends_time" time;
alter table "better_supabase"."shift_templates" add column if not exists "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720);
alter table "better_supabase"."shift_templates" add column if not exists "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500);
alter table "better_supabase"."shift_templates" add column if not exists "required_qualifications" text[] not null default '{}';
alter table "better_supabase"."shift_templates" add column if not exists "weekdays" integer[] not null default '{1,2,3,4,5}' check ("weekdays" <@ array[1, 2, 3, 4, 5, 6, 7]);
alter table "better_supabase"."shift_templates" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."shift_templates" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."shift_templates" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_shift_templates_tenant_id_key" on "better_supabase"."shift_templates" ("tenant_id", "id");
create index if not exists "shift_templates_tenant_idx" on "better_supabase"."shift_templates" ("tenant_id", "name");
create index if not exists "shift_templates_team_idx" on "better_supabase"."shift_templates" ("team_id") where "team_id" is not null;
create index if not exists "shift_templates_location_idx" on "better_supabase"."shift_templates" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shift_templates" enable row level security;
grant select on "better_supabase"."shift_templates" to authenticated;
grant all on "better_supabase"."shift_templates" to service_role;
drop policy if exists bsb_shift_templates_read on "better_supabase"."shift_templates";
create policy bsb_shift_templates_read on "better_supabase"."shift_templates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

-- better_supabase.shifts is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shifts" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shifts" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shifts" add column if not exists "template_id" uuid;
alter table "better_supabase"."shifts" add column if not exists "team_id" uuid references "better_supabase"."teams" ("id") on delete set null;
alter table "better_supabase"."shifts" add column if not exists "location_id" uuid;
alter table "better_supabase"."shifts" add column if not exists "starts_at" timestamptz;
alter table "better_supabase"."shifts" add column if not exists "ends_at" timestamptz;
alter table "better_supabase"."shifts" add column if not exists "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720);
alter table "better_supabase"."shifts" add column if not exists "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500);
alter table "better_supabase"."shifts" add column if not exists "required_qualifications" text[] not null default '{}';
alter table "better_supabase"."shifts" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'published', 'canceled'));
alter table "better_supabase"."shifts" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."shifts" add column if not exists "published_at" timestamptz;
alter table "better_supabase"."shifts" add column if not exists "canceled_at" timestamptz;
alter table "better_supabase"."shifts" add column if not exists "created_by" uuid;
alter table "better_supabase"."shifts" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."shifts" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_shifts_tenant_id_key" on "better_supabase"."shifts" ("tenant_id", "id");
create index if not exists "shifts_tenant_idx" on "better_supabase"."shifts" ("tenant_id", "starts_at");
create index if not exists "shifts_template_idx" on "better_supabase"."shifts" ("tenant_id", "template_id") where "template_id" is not null;
create index if not exists "shifts_team_idx" on "better_supabase"."shifts" ("team_id") where "team_id" is not null;
create index if not exists "shifts_location_idx" on "better_supabase"."shifts" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shifts" enable row level security;
grant select on "better_supabase"."shifts" to authenticated;
grant all on "better_supabase"."shifts" to service_role;
drop policy if exists bsb_shifts_read on "better_supabase"."shifts";
create policy bsb_shifts_read on "better_supabase"."shifts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))));

-- better_supabase.shift_assignments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shift_assignments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shift_assignments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shift_assignments" add column if not exists "shift_id" uuid;
alter table "better_supabase"."shift_assignments" add column if not exists "user_id" uuid;
alter table "better_supabase"."shift_assignments" add column if not exists "status" text not null default 'assigned' check ("status" in ('assigned', 'requested', 'released'));
alter table "better_supabase"."shift_assignments" add column if not exists "starts_at" timestamptz;
alter table "better_supabase"."shift_assignments" add column if not exists "ends_at" timestamptz;
alter table "better_supabase"."shift_assignments" add column if not exists "assigned_by" uuid;
alter table "better_supabase"."shift_assignments" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."shift_assignments" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_shift_assignments_shift_user_key_key" on "better_supabase"."shift_assignments" ("shift_id", "user_id");
create unique index if not exists "bsb_shift_assignments_tenant_id_key" on "better_supabase"."shift_assignments" ("tenant_id", "id");
create index if not exists "shift_assignments_tenant_idx" on "better_supabase"."shift_assignments" ("tenant_id", "shift_id");
create index if not exists "shift_assignments_user_idx" on "better_supabase"."shift_assignments" ("user_id", "starts_at");
alter table "better_supabase"."shift_assignments" enable row level security;
grant select on "better_supabase"."shift_assignments" to authenticated;
grant all on "better_supabase"."shift_assignments" to service_role;
drop policy if exists bsb_shift_assignments_read on "better_supabase"."shift_assignments";
create policy bsb_shift_assignments_read on "better_supabase"."shift_assignments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')));

-- better_supabase.shift_swaps is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shift_swaps" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shift_swaps" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shift_swaps" add column if not exists "assignment_id" uuid;
alter table "better_supabase"."shift_swaps" add column if not exists "from_user_id" uuid;
alter table "better_supabase"."shift_swaps" add column if not exists "to_user_id" uuid;
alter table "better_supabase"."shift_swaps" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'canceled'));
alter table "better_supabase"."shift_swaps" add column if not exists "approval_id" uuid;
alter table "better_supabase"."shift_swaps" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."shift_swaps" add column if not exists "decided_by" uuid;
alter table "better_supabase"."shift_swaps" add column if not exists "decided_at" timestamptz;
alter table "better_supabase"."shift_swaps" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "shift_swaps_tenant_idx" on "better_supabase"."shift_swaps" ("tenant_id", "assignment_id");
create unique index if not exists "shift_swaps_pending_idx" on "better_supabase"."shift_swaps" ("assignment_id") where "status" = 'pending';
create index if not exists "shift_swaps_to_user_idx" on "better_supabase"."shift_swaps" ("to_user_id");
alter table "better_supabase"."shift_swaps" enable row level security;
grant select on "better_supabase"."shift_swaps" to authenticated;
grant all on "better_supabase"."shift_swaps" to service_role;
drop policy if exists bsb_shift_swaps_read on "better_supabase"."shift_swaps";
create policy bsb_shift_swaps_read on "better_supabase"."shift_swaps"
  for select to authenticated
  using ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')));

-- better_supabase.shift_availability is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."shift_availability" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."shift_availability" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."shift_availability" add column if not exists "user_id" uuid;
alter table "better_supabase"."shift_availability" add column if not exists "on_date" date;
alter table "better_supabase"."shift_availability" add column if not exists "from_time" time;
alter table "better_supabase"."shift_availability" add column if not exists "until_time" time;
alter table "better_supabase"."shift_availability" add column if not exists "kind" text check ("kind" in ('available', 'unavailable', 'preferred'));
alter table "better_supabase"."shift_availability" add column if not exists "note" text check ("note" is null or length("note") <= 500);
alter table "better_supabase"."shift_availability" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_shift_availability_user_day_key_key" on "better_supabase"."shift_availability" ("tenant_id", "user_id", "on_date");
create index if not exists "shift_availability_day_idx" on "better_supabase"."shift_availability" ("tenant_id", "on_date");
alter table "better_supabase"."shift_availability" enable row level security;
grant select on "better_supabase"."shift_availability" to authenticated;
grant all on "better_supabase"."shift_availability" to service_role;
drop policy if exists bsb_shift_availability_read on "better_supabase"."shift_availability";
create policy bsb_shift_availability_read on "better_supabase"."shift_availability"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')));

-- Creates a shift template, or changes one (template_id). An end at or before
-- the start runs into the next day. weekdays are ISO weekdays (1 is Monday)
-- generate_shifts creates shifts on.
create or replace function "better_supabase"."save_shift_template"(tenant uuid, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift_template.required_qualifications, '{}')) k where k is not null order by k);
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift_template.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a shift template needs a name of at most 200 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    raise exception 'a shift template needs a start and an end time' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    raise exception 'weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift_template.team_id and o."tenant_id" = save_shift_template.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.template_id is null then
    insert into "better_supabase"."shift_templates" ("tenant_id", "name", "team_id", "location_id", "starts_time", "ends_time", "break_minutes", "headcount", "required_qualifications", "weekdays")
    values (save_shift_template.tenant, v_name, save_shift_template.team_id, save_shift_template.location_id, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update "better_supabase"."shift_templates" x set
      "name" = v_name,
      "team_id" = save_shift_template.team_id,
      "location_id" = save_shift_template.location_id,
      "starts_time" = save_shift_template.starts_time,
      "ends_time" = save_shift_template.ends_time,
      "break_minutes" = coalesce(save_shift_template.break_minutes, 0),
      "headcount" = coalesce(save_shift_template.headcount, 1),
      "required_qualifications" = v_required,
      "weekdays" = v_weekdays,
      "updated_at" = now(),
      "archived_at" = null
    where x."id" = save_shift_template.template_id and x."tenant_id" = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) from public, anon;
grant execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) to authenticated, service_role;

-- Archives a template: generate_shifts no longer takes it; its shifts stay.
create or replace function "better_supabase"."archive_shift_template"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_templates" x where x."id" = archive_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "better_supabase"."shift_templates" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_shift_template"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_shift_template"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_shift_templates"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'teamId', x."team_id", 'locationId', x."location_id", 'startsTime', to_char(x."starts_time", 'HH24:MI'), 'endsTime', to_char(x."ends_time", 'HH24:MI'), 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'weekdays', to_jsonb(x."weekdays"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."shift_templates" x
  where x."tenant_id" = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_shift_templates"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_shift_templates"(uuid, boolean) to authenticated, service_role;

-- Creates draft shifts from a template on each of its weekdays from from_date
-- until_date (at most 92 days), in the block's time zone. A day that
-- already has the template's shift at the same start is skipped. Returns the
-- shifts it created.
create or replace function "better_supabase"."generate_shifts"(tenant uuid, template_id uuid, from_date date, until_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_template "better_supabase"."shift_templates"%rowtype;
  v_row "better_supabase"."shifts"%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', generate_shifts.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_template from "better_supabase"."shift_templates" x
  where x."id" = generate_shifts.template_id and x."tenant_id" = generate_shifts.tenant and x."archived_at" is null;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= 92 then
    raise exception 'generate_shifts covers at most 92 days' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template."weekdays"));
    v_starts := (v_day + v_template."starts_time") at time zone 'UTC';
    v_ends := (v_day + v_template."ends_time" + case when v_template."ends_time" <= v_template."starts_time" then interval '1 day' else interval '0' end) at time zone 'UTC';
    continue when exists (
      select 1 from "better_supabase"."shifts" x
      where x."tenant_id" = v_template."tenant_id" and x."template_id" = v_template."id" and x."starts_at" = v_starts
    );
    insert into "better_supabase"."shifts" ("tenant_id", "template_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "created_by")
    values (v_template."tenant_id", v_template."id", v_template."team_id", v_template."location_id", v_starts, v_ends, v_template."break_minutes", v_template."headcount", v_template."required_qualifications", (select auth.uid()))
    returning * into v_row;
    null;
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return v_created;
end;
$$;
revoke execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) from public, anon;
grant execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) to authenticated, service_role;

-- Creates a draft shift, or changes one (shift_id). Changing the times moves
-- its assignments with it; a move that overlaps another shift of an assigned
-- member is refused.
drop function if exists "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid, jsonb);
create or replace function "better_supabase"."save_shift"(tenant uuid, starts_at timestamptz, ends_at timestamptz, team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift.required_qualifications, '{}')) k where k is not null order by k);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    raise exception 'a shift ends after it starts' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    raise exception 'a shift lasts at most 24 hours' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift.team_id and o."tenant_id" = save_shift.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_save"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using save_shift.tenant, save_shift.shift_id;
    end if;
  end;
  if save_shift.shift_id is null then
    insert into "better_supabase"."shifts" ("tenant_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "note", "created_by")
    values (save_shift.tenant, save_shift.team_id, save_shift.location_id, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required, nullif(trim(save_shift.note), ''), (select auth.uid()))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."shifts" x
    where x."id" = save_shift.shift_id and x."tenant_id" = save_shift.tenant
    for update;
    if not found then
      raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
    end if;
    if v_row."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    update "better_supabase"."shifts" x set
      "starts_at" = save_shift.starts_at,
      "ends_at" = save_shift.ends_at,
      "team_id" = save_shift.team_id,
      "location_id" = save_shift.location_id,
      "break_minutes" = coalesce(save_shift.break_minutes, 0),
      "headcount" = coalesce(save_shift.headcount, 1),
      "required_qualifications" = v_required,
      "note" = nullif(trim(save_shift.note), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    begin
      update "better_supabase"."shift_assignments" x set "starts_at" = v_row."starts_at", "ends_at" = v_row."ends_at", "updated_at" = now()
      where x."shift_id" = v_row."id" and (x."starts_at" <> v_row."starts_at" or x."ends_at" <> v_row."ends_at");
    exception when exclusion_violation then
      raise exception 'an assigned member has another shift at the new time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) from public, anon;
grant execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) to authenticated, service_role;

-- Cancels a shift and releases its assignments. Assigned members are
-- notified. Canceling one already canceled changes nothing.
create or replace function "better_supabase"."cancel_shift"(shift_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_assignment "better_supabase"."shift_assignments"%rowtype;
  v_users jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shifts" x where x."id" = cancel_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to cancel shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'canceled' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    v_users := coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb);
    update "better_supabase"."shifts" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    for v_assignment in
      update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
      where x."shift_id" = v_row."id" and x."status" <> 'released'
      returning x.*
    loop
      null;
    end loop;
    null;
    if jsonb_array_length(v_users) > 0 then
      
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_shift"(uuid, text) to authenticated, service_role;

-- Publishes the draft shifts that start from from_date to until_date (days in the
-- block's time zone), for one team or all. Members then see them, and the
-- assigned members are notified. Returns how many it published.
create or replace function "better_supabase"."publish_shifts"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', publish_shifts.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to publish shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_row in
    update "better_supabase"."shifts" x set "status" = 'published', "published_at" = now(), "updated_at" = now()
    where x."tenant_id" = publish_shifts.tenant
      and x."status" = 'draft'
      and x."starts_at" >= publish_shifts.from_date::timestamp at time zone 'UTC'
      and x."starts_at" < (publish_shifts.until_date + 1)::timestamp at time zone 'UTC'
      and (publish_shifts.team_id is null or x."team_id" = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    null;
    if jsonb_array_length(coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb)) > 0 then
      
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) to authenticated, service_role;

-- Checks that a member may work a shift: no other assigned shift overlaps,
-- no approved leave falls on its day, they hold its required qualifications
-- and they keep the minimum rest between shifts. Returns warnings (with
-- qualificationCheck "warn") and raises otherwise.
create or replace function "better_supabase"."shift_assignment_check"(shift_id uuid, user_id uuid, assignment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from "better_supabase"."shifts" x where x."id" = shift_assignment_check.shift_id;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if shift_assignment_check.user_id is null or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_shift."tenant_id" and mm."user_id" = shift_assignment_check.user_id and mm."disabled_at" is null) then
    raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at", v_shift."ends_at")
  ) then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."tenant_id" = v_shift."tenant_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at" - interval '11 hours', v_shift."ends_at" + interval '11 hours')
  ) then
    raise exception 'the member would have less than 11 hours between shifts' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_REST_TOO_SHORT';
  end if;
  return v_warnings;
end;
$$;
revoke execute on function "better_supabase"."shift_assignment_check"(uuid, uuid, uuid) from public, anon, authenticated;

-- Assigns a member to a shift. Returns the assignment with its warnings.
-- Assigning someone already on the shift changes nothing.
create or replace function "better_supabase"."assign_shift"(shift_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = assign_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = assign_shift.user_id;
  if found and v_row."status" = 'assigned' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", assign_shift.user_id, v_row."id");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", assign_shift.user_id;
    end if;
  end;
  begin
    insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", assign_shift.user_id, 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  exception when exclusion_violation then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end;
  null;
  if v_shift."status" = 'published' then
    
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."assign_shift"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."assign_shift"(uuid, uuid) to authenticated, service_role;

-- Takes a member off a shift, or turns down their request for it.
create or replace function "better_supabase"."unassign_shift"(assignment_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = unassign_shift.assignment_id for update;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  v_was := v_row."status";
  if v_was <> 'released' then
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    if v_was = 'assigned' and v_shift."status" = 'published' then
      
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."unassign_shift"(uuid, text) to authenticated, service_role;

-- Asks for a place on a published open shift that hasn't started. A planner
-- decides with decide_shift_request.
create or replace function "better_supabase"."request_open_shift"(shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_user uuid := (select auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = request_open_shift.shift_id;
  if not found or v_shift."status" = 'draft' then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if v_user is null or not coalesce(better_supabase.can('tenant', v_shift."tenant_id", 'shifts.request'), false) then
    raise exception 'not allowed to request shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  if v_shift."starts_at" <= now() then
    raise exception 'the shift has started' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = v_user;
  if found and v_row."status" <> 'released' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  perform "better_supabase"."shift_assignment_check"(v_shift."id", v_user, v_row."id");
  insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_user, 'requested', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'requested', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_open_shift"(uuid) from public, anon;
grant execute on function "better_supabase"."request_open_shift"(uuid) to authenticated, service_role;

-- Approves a request for an open shift (the member is assigned after the
-- same checks as assign_shift) or turns it down.
create or replace function "better_supabase"."decide_shift_request"(assignment_id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = decide_shift_request.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to decide shift requests' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'requested' then
    raise exception 'the assignment isn''t a pending request' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
    v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", v_row."user_id", v_row."id");
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", v_row."user_id";
    end if;
  end;
    begin
      update "better_supabase"."shift_assignments" x set "status" = 'assigned', "starts_at" = v_shift."starts_at", "ends_at" = v_shift."ends_at", "assigned_by" = (select auth.uid()), "updated_at" = now()
      where x."id" = v_row."id"
      returning x.* into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
    
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."decide_shift_request"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."decide_shift_request"(uuid, boolean) to authenticated, service_role;

-- Offers an assigned shift that hasn't started to another member. A manager
-- decides with decide_shift_swap; the member who asked may withdraw it there.
create or replace function "better_supabase"."request_shift_swap"(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row."user_id" or not exists (select 1 from "better_supabase"."memberships" mm where mm."organization_id" = v_row."tenant_id" and mm."user_id" = request_shift_swap.to_user_id and mm."disabled_at" is null) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "better_supabase"."shift_swaps" ("tenant_id", "assignment_id", "from_user_id", "to_user_id", "note")
  values (v_row."tenant_id", v_row."id", v_row."user_id", request_shift_swap.to_user_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  null;
  
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) to authenticated, service_role;

-- Approves a pending swap (the other member takes the shift after the same
-- checks as assign_shift) or rejects it. The member who asked may withdraw it
-- (approve false). approval_id links an approvals request.
create or replace function "better_supabase"."decide_shift_swap"(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "better_supabase"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."tenant_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_user_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null then
    raise exception 'approval_id needs the approvals block' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "better_supabase"."shift_assignment_check"(v_shift."id", v_swap."to_user_id", null);
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    begin
      insert into "better_supabase"."shift_assignments" ("tenant_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."tenant_id", v_shift."id", v_swap."to_user_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
  end if;
  update "better_supabase"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid())
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  null;
  if v_status <> 'canceled' then
    
  end if;
  if v_status = 'approved' then
    
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."tenant_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) to authenticated, service_role;

-- Sets a member's availability on a day: available, unavailable or
-- preferred, for the whole day or from_time to until_time. kind null clears
-- the day. Planners (shifts.write) set it for others with user_id.
create or replace function "better_supabase"."set_shift_availability"(tenant uuid, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_availability"%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_user = (select auth.uid()) then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.request'), false)) then
      raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to set another member''s availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if set_shift_availability.on_date is null then
    raise exception 'on_date is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.kind is null then
    delete from "better_supabase"."shift_availability" x
    where x."tenant_id" = set_shift_availability.tenant and x."user_id" = v_user and x."on_date" = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ('available', 'unavailable', 'preferred') then
    raise exception 'kind is one of available, unavailable, preferred' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    raise exception 'from_time and until_time are both set, with until_time after from_time, or both null' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    raise exception 'a note is at most 500 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  insert into "better_supabase"."shift_availability" ("tenant_id", "user_id", "on_date", "from_time", "until_time", "kind", "note")
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind, nullif(trim(set_shift_availability.note), ''))
  on conflict ("tenant_id", "user_id", "on_date") do update set
    "from_time" = excluded."from_time",
    "until_time" = excluded."until_time",
    "kind" = excluded."kind",
    "note" = excluded."note"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'onDate', v_row."on_date", 'fromTime', to_char(v_row."from_time", 'HH24:MI'), 'untilTime', to_char(v_row."until_time", 'HH24:MI'), 'kind', v_row."kind", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) to authenticated, service_role;

-- The availability the caller may read from from_date to until_date: their own,
-- or everyone's (or one member's) with shifts.write.
create or replace function "better_supabase"."list_shift_availability"(tenant uuid, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'onDate', x."on_date", 'fromTime', to_char(x."from_time", 'HH24:MI'), 'untilTime', to_char(x."until_time", 'HH24:MI'), 'kind', x."kind", 'note', x."note", 'createdAt', x."created_at") order by x."on_date", x."user_id"), '[]'::jsonb)
  from "better_supabase"."shift_availability" x
  where x."tenant_id" = list_shift_availability.tenant
    and x."on_date" between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x."user_id" = list_shift_availability.user_id)
$$;
revoke execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) to authenticated, service_role;

-- The shifts the caller may read that start from from_date to until_date (days in
-- the block's time zone), for one team or all, each with its assigned and
-- requested members. Members see published shifts; planners also drafts.
create or replace function "better_supabase"."roster"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."status", y."user_id")
    from "better_supabase"."shift_assignments" y
    where y."shift_id" = x."id" and y."status" <> 'released'
  ), '[]'::jsonb)) order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."shifts" x
  where x."tenant_id" = roster.tenant
    and x."starts_at" >= (roster.from_date)::timestamp at time zone 'UTC'
    and x."starts_at" < (roster.until_date + 1)::timestamp at time zone 'UTC'
    and (roster.team_id is null or x."team_id" = roster.team_id)
$$;
revoke execute on function "better_supabase"."roster"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."roster"(uuid, date, date, uuid) to authenticated, service_role;

-- The caller's shifts (assigned or requested) that start from since to until,
-- in every organization, each with its assignment.
create or replace function "better_supabase"."my_shifts"(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignment', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_at"), '[]'::jsonb)
  from "better_supabase"."shift_assignments" y
  join "better_supabase"."shifts" x on x."id" = y."shift_id"
  where y."user_id" = (select auth.uid())
    and y."status" in ('assigned', 'requested')
    and x."status" <> 'draft'
    and x."starts_at" >= coalesce(my_shifts.since, now())
    and x."starts_at" < coalesce(my_shifts.until, now() + interval '30 days')
$$;
revoke execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) to authenticated, service_role;

-- The hours each member is planned for in the week from week_start (shifts
-- not canceled, breaks taken off), next to their contract hours when the
-- employees block keeps contracts.
create or replace function "better_supabase"."shift_hours"(tenant uuid, week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', shift_hours.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to read planned hours' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if shift_hours.week_start is null then
    raise exception 'week_start is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.shifts,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.shifts, p.planned, null::numeric as contract
      from (
        select y."user_id" as user_id, count(*)::integer as shifts, round((extract(epoch from sum(x."ends_at" - make_interval(mins => x."break_minutes") - x."starts_at")) / 3600)::numeric, 2) as planned
        from "better_supabase"."shift_assignments" y
        join "better_supabase"."shifts" x on x."id" = y."shift_id"
        where y."tenant_id" = shift_hours.tenant
          and y."status" = 'assigned'
          and x."status" <> 'canceled'
          and x."starts_at" >= (shift_hours.week_start)::timestamp at time zone 'UTC'
          and x."starts_at" < (shift_hours.week_start + 7)::timestamp at time zone 'UTC'
        group by y."user_id"
      ) p
    ) u
  );
end;
$$;
revoke execute on function "better_supabase"."shift_hours"(uuid, date) from public, anon;
grant execute on function "better_supabase"."shift_hours"(uuid, date) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_select on "better_supabase"."shift_templates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_templates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_update on "better_supabase"."shift_templates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_templates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
create policy bsb_tenant_scope_select on "better_supabase"."shifts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
create policy bsb_tenant_scope_insert on "better_supabase"."shifts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
create policy bsb_tenant_scope_update on "better_supabase"."shifts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
create policy bsb_tenant_scope_delete on "better_supabase"."shifts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."shift_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."shift_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_select on "better_supabase"."shift_swaps" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_swaps" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_update on "better_supabase"."shift_swaps" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_swaps" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_select on "better_supabase"."shift_availability" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('shifts.write')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_availability" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_update on "better_supabase"."shift_availability" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_availability" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:1885529dd31ecefd0b84d5f3f56b949fcd6011a51a38cbeec6dd8c7bf0fc1545
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block shifts@1 managed
-- @bsb-hash sha256:205580fa0ae6b4347aeb91f725b374e874738ba5a6ba3d239a3b920ed637f72e
-- Shift templates that generate shifts on weekdays, shifts planned in draft and published per team and location, assignments checked for overlap, approved leave, required qualifications and rest time, open shift requests, swaps between members, availability, a roster, planned hours against contract hours, and time entries from worked shifts.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Shifts: templates that generate shifts, shifts planned in draft and
-- published, assignments checked for overlap, leave, qualifications and rest,
-- open shift requests, swaps between members, and availability.

create extension if not exists btree_gist with schema extensions;

create table if not exists "better_supabase"."shift_templates" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  -- An end at or before the start runs into the next day.
  "starts_time" time not null,
  "ends_time" time not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  -- Qualification type keys (qualifications block) everyone on the shift holds.
  "required_qualifications" text[] not null default '{}',
  -- ISO weekdays, 1 (Monday) to 7 (Sunday), generate_shifts creates shifts on.
  "weekdays" integer[] not null default '{1,2,3,4,5}' check ("weekdays" <@ array[1, 2, 3, 4, 5, 6, 7]),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "id")
);
create index if not exists "shift_templates_tenant_idx" on "better_supabase"."shift_templates" ("org_id", "name");
create index if not exists "shift_templates_team_idx" on "better_supabase"."shift_templates" ("team_id") where "team_id" is not null;
create index if not exists "shift_templates_location_idx" on "better_supabase"."shift_templates" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shift_templates" enable row level security;
revoke all on "better_supabase"."shift_templates" from public, anon, authenticated;
grant select on "better_supabase"."shift_templates" to authenticated;
grant all on "better_supabase"."shift_templates" to service_role;
drop policy if exists shift_templates_read on "better_supabase"."shift_templates";
create policy shift_templates_read on "better_supabase"."shift_templates"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shifts" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "template_id" uuid,
  "team_id" uuid references "better_supabase"."teams" ("id") on delete set null,
  "location_id" uuid,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "break_minutes" integer not null default 0 check ("break_minutes" >= 0 and "break_minutes" <= 720),
  "headcount" integer not null default 1 check ("headcount" >= 1 and "headcount" <= 500),
  "required_qualifications" text[] not null default '{}',
  -- draft: planners see it; published: everyone with shifts.read does.
  "status" text not null default 'draft' check ("status" in ('draft', 'published', 'canceled')),
  "note" text check ("note" is null or length("note") <= 2000),
  "published_at" timestamptz,
  "canceled_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_at" > "starts_at"),
  check ("ends_at" - "starts_at" <= interval '24 hours'),
  unique ("org_id", "id"),
  foreign key ("org_id", "template_id") references "better_supabase"."shift_templates" ("org_id", "id") on delete set null ("template_id")
);
create index if not exists "shifts_tenant_idx" on "better_supabase"."shifts" ("org_id", "starts_at");
create index if not exists "shifts_template_idx" on "better_supabase"."shifts" ("org_id", "template_id") where "template_id" is not null;
create index if not exists "shifts_team_idx" on "better_supabase"."shifts" ("team_id") where "team_id" is not null;
create index if not exists "shifts_location_idx" on "better_supabase"."shifts" ("location_id") where "location_id" is not null;
alter table "better_supabase"."shifts" enable row level security;
revoke all on "better_supabase"."shifts" from public, anon, authenticated;
grant select on "better_supabase"."shifts" to authenticated;
grant all on "better_supabase"."shifts" to service_role;
drop policy if exists shifts_read on "better_supabase"."shifts";
create policy shifts_read on "better_supabase"."shifts"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "org_id" in (select better_supabase.tenant_ids_with('shifts.read'))));

create table if not exists "better_supabase"."shift_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "shift_id" uuid not null,
  "user_id" uuid not null,
  -- requested: the member asked for an open shift; released: no longer on it.
  "status" text not null default 'assigned' check ("status" in ('assigned', 'requested', 'released')),
  -- The shift's times, copied so the exclusion constraint can read them.
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "assigned_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("shift_id", "user_id"),
  unique ("org_id", "id"),
  foreign key ("org_id", "shift_id") references "better_supabase"."shifts" ("org_id", "id") on delete cascade,
  constraint "shift_assignments_no_overlap" exclude using gist (
    "org_id" with =,
    "user_id" with =,
    tstzrange("starts_at", "ends_at") with &&
  ) where ("status" = 'assigned')
);
create index if not exists "shift_assignments_tenant_idx" on "better_supabase"."shift_assignments" ("org_id", "shift_id");
create index if not exists "shift_assignments_user_idx" on "better_supabase"."shift_assignments" ("user_id", "starts_at");
alter table "better_supabase"."shift_assignments" enable row level security;
revoke all on "better_supabase"."shift_assignments" from public, anon, authenticated;
grant select on "better_supabase"."shift_assignments" to authenticated;
grant all on "better_supabase"."shift_assignments" to service_role;
drop policy if exists shift_assignments_read on "better_supabase"."shift_assignments";
create policy shift_assignments_read on "better_supabase"."shift_assignments"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('shifts.read')));

create table if not exists "better_supabase"."shift_swaps" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "assignment_id" uuid not null,
  "from_user_id" uuid not null,
  "to_user_id" uuid not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'approved', 'rejected', 'canceled')),
  "approval_id" uuid,
  "note" text check ("note" is null or length("note") <= 2000),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  check ("to_user_id" <> "from_user_id"),
  foreign key ("org_id", "assignment_id") references "better_supabase"."shift_assignments" ("org_id", "id") on delete cascade
);
create index if not exists "shift_swaps_tenant_idx" on "better_supabase"."shift_swaps" ("org_id", "assignment_id");
create unique index if not exists "shift_swaps_pending_idx" on "better_supabase"."shift_swaps" ("assignment_id") where "status" = 'pending';
create index if not exists "shift_swaps_to_user_idx" on "better_supabase"."shift_swaps" ("to_user_id");
alter table "better_supabase"."shift_swaps" enable row level security;
revoke all on "better_supabase"."shift_swaps" from public, anon, authenticated;
grant select on "better_supabase"."shift_swaps" to authenticated;
grant all on "better_supabase"."shift_swaps" to service_role;
drop policy if exists shift_swaps_read on "better_supabase"."shift_swaps";
create policy shift_swaps_read on "better_supabase"."shift_swaps"
  for select to authenticated
  using ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('shifts.manage')));

create table if not exists "better_supabase"."shift_availability" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "user_id" uuid not null,
  "on_date" date not null,
  -- Both null: the whole day.
  "from_time" time,
  "until_time" time,
  "kind" text not null check ("kind" in ('available', 'unavailable', 'preferred')),
  "note" text check ("note" is null or length("note") <= 500),
  "created_at" timestamptz not null default now(),
  check (("from_time" is null) = ("until_time" is null)),
  check ("until_time" is null or "until_time" > "from_time"),
  unique ("org_id", "user_id", "on_date")
);
create index if not exists "shift_availability_day_idx" on "better_supabase"."shift_availability" ("org_id", "on_date");
alter table "better_supabase"."shift_availability" enable row level security;
revoke all on "better_supabase"."shift_availability" from public, anon, authenticated;
grant select on "better_supabase"."shift_availability" to authenticated;
grant all on "better_supabase"."shift_availability" to service_role;
drop policy if exists shift_availability_read on "better_supabase"."shift_availability";
create policy shift_availability_read on "better_supabase"."shift_availability"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('shifts.write')));

-- Creates a shift template, or changes one (template_id). An end at or before
-- the start runs into the next day. weekdays are ISO weekdays (1 is Monday)
-- generate_shifts creates shifts on.
create or replace function "better_supabase"."save_shift_template"(tenant uuid, name text, starts_time time, ends_time time, weekdays integer[] default '{1,2,3,4,5}', team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', template_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
  v_name text := nullif(trim(save_shift_template.name), '');
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift_template.required_qualifications, '{}')) k where k is not null order by k);
  v_weekdays integer[] := array(select distinct d from unnest(coalesce(save_shift_template.weekdays, '{}')) d where d is not null order by d);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift_template.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a shift template needs a name of at most 200 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.starts_time is null or save_shift_template.ends_time is null then
    raise exception 'a shift template needs a start and an end time' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if not (v_weekdays <@ array[1, 2, 3, 4, 5, 6, 7]) then
    raise exception 'weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift_template.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift_template.team_id and o."org_id" = save_shift_template.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift_template.template_id is null then
    insert into "better_supabase"."shift_templates" ("org_id", "name", "team_id", "location_id", "starts_time", "ends_time", "break_minutes", "headcount", "required_qualifications", "weekdays")
    values (save_shift_template.tenant, v_name, save_shift_template.team_id, save_shift_template.location_id, save_shift_template.starts_time, save_shift_template.ends_time, coalesce(save_shift_template.break_minutes, 0), coalesce(save_shift_template.headcount, 1), v_required, v_weekdays)
    returning * into v_row;
  else
    update "better_supabase"."shift_templates" x set
      "name" = v_name,
      "team_id" = save_shift_template.team_id,
      "location_id" = save_shift_template.location_id,
      "starts_time" = save_shift_template.starts_time,
      "ends_time" = save_shift_template.ends_time,
      "break_minutes" = coalesce(save_shift_template.break_minutes, 0),
      "headcount" = coalesce(save_shift_template.headcount, 1),
      "required_qualifications" = v_required,
      "weekdays" = v_weekdays,
      "updated_at" = now(),
      "archived_at" = null
    where x."id" = save_shift_template.template_id and x."org_id" = save_shift_template.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) from public, anon;
grant execute on function "better_supabase"."save_shift_template"(uuid, text, time, time, integer[], uuid, uuid, integer, integer, text[], uuid) to authenticated, service_role;

-- Archives a template: generate_shifts no longer takes it; its shifts stay.
create or replace function "better_supabase"."archive_shift_template"(template_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_templates" x where x."id" = archive_shift_template.template_id;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  update "better_supabase"."shift_templates" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'name', v_row."name", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsTime', to_char(v_row."starts_time", 'HH24:MI'), 'endsTime', to_char(v_row."ends_time", 'HH24:MI'), 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'weekdays', to_jsonb(v_row."weekdays"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_shift_template"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_shift_template"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_shift_templates"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'name', x."name", 'teamId', x."team_id", 'locationId', x."location_id", 'startsTime', to_char(x."starts_time", 'HH24:MI'), 'endsTime', to_char(x."ends_time", 'HH24:MI'), 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'weekdays', to_jsonb(x."weekdays"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."shift_templates" x
  where x."org_id" = list_shift_templates.tenant
    and (coalesce(list_shift_templates.include_archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_shift_templates"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_shift_templates"(uuid, boolean) to authenticated, service_role;

-- Creates draft shifts from a template on each of its weekdays from from_date
-- until_date (at most 92 days), in the block's time zone. A day that
-- already has the template's shift at the same start is skipped. Returns the
-- shifts it created.
create or replace function "better_supabase"."generate_shifts"(tenant uuid, template_id uuid, from_date date, until_date date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_template "better_supabase"."shift_templates"%rowtype;
  v_row "better_supabase"."shifts"%rowtype;
  v_day date;
  v_starts timestamptz;
  v_ends timestamptz;
  v_created jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', generate_shifts.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_template from "better_supabase"."shift_templates" x
  where x."id" = generate_shifts.template_id and x."org_id" = generate_shifts.tenant and x."archived_at" is null;
  if not found then
    raise exception 'shift template not found' using errcode = 'P0002', hint = 'SHIFT_TEMPLATE_NOT_FOUND';
  end if;
  if generate_shifts.from_date is null or generate_shifts.until_date is null or generate_shifts.until_date < generate_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if generate_shifts.until_date - generate_shifts.from_date >= 92 then
    raise exception 'generate_shifts covers at most 92 days' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_day in select d::date from generate_series(generate_shifts.from_date::timestamp, generate_shifts.until_date::timestamp, interval '1 day') d loop
    continue when not (extract(isodow from v_day)::integer = any(v_template."weekdays"));
    v_starts := (v_day + v_template."starts_time") at time zone 'UTC';
    v_ends := (v_day + v_template."ends_time" + case when v_template."ends_time" <= v_template."starts_time" then interval '1 day' else interval '0' end) at time zone 'UTC';
    continue when exists (
      select 1 from "better_supabase"."shifts" x
      where x."org_id" = v_template."org_id" and x."template_id" = v_template."id" and x."starts_at" = v_starts
    );
    insert into "better_supabase"."shifts" ("org_id", "template_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "created_by")
    values (v_template."org_id", v_template."id", v_template."team_id", v_template."location_id", v_starts, v_ends, v_template."break_minutes", v_template."headcount", v_template."required_qualifications", (select auth.uid()))
    returning * into v_row;
    null;
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return v_created;
end;
$$;
revoke execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) from public, anon;
grant execute on function "better_supabase"."generate_shifts"(uuid, uuid, date, date) to authenticated, service_role;

-- Creates a draft shift, or changes one (shift_id). Changing the times moves
-- its assignments with it; a move that overlaps another shift of an assigned
-- member is refused.
drop function if exists "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid, jsonb);
create or replace function "better_supabase"."save_shift"(tenant uuid, starts_at timestamptz, ends_at timestamptz, team_id uuid default null, location_id uuid default null, break_minutes integer default 0, headcount integer default 1, required_qualifications text[] default '{}', note text default null, shift_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_required text[] := array(select distinct k from unnest(coalesce(save_shift.required_qualifications, '{}')) k where k is not null order by k);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_shift.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to plan shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if save_shift.starts_at is null or save_shift.ends_at is null or save_shift.ends_at <= save_shift.starts_at then
    raise exception 'a shift ends after it starts' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.ends_at - save_shift.starts_at > interval '24 hours' then
    raise exception 'a shift lasts at most 24 hours' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.break_minutes, 0) not between 0 and 720 then
    raise exception 'break_minutes is between 0 and 720' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if coalesce(save_shift.headcount, 1) not between 1 and 500 then
    raise exception 'headcount is between 1 and 500' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.note is not null and length(save_shift.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" o where o."id" = save_shift.team_id and o."org_id" = save_shift.tenant
  ) then
    raise exception 'the team isn''t in this organization' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if save_shift.location_id is not null then
    raise exception 'location_id needs the assets block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if cardinality(coalesce(v_required, '{}')) > 0 then
    raise exception 'required_qualifications needs the qualifications block' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_save"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using save_shift.tenant, save_shift.shift_id;
    end if;
  end;
  if save_shift.shift_id is null then
    insert into "better_supabase"."shifts" ("org_id", "team_id", "location_id", "starts_at", "ends_at", "break_minutes", "headcount", "required_qualifications", "note", "created_by")
    values (save_shift.tenant, save_shift.team_id, save_shift.location_id, save_shift.starts_at, save_shift.ends_at, coalesce(save_shift.break_minutes, 0), coalesce(save_shift.headcount, 1), v_required, nullif(trim(save_shift.note), ''), (select auth.uid()))
    returning * into v_row;
    null;
  else
    select * into v_row from "better_supabase"."shifts" x
    where x."id" = save_shift.shift_id and x."org_id" = save_shift.tenant
    for update;
    if not found then
      raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
    end if;
    if v_row."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    update "better_supabase"."shifts" x set
      "starts_at" = save_shift.starts_at,
      "ends_at" = save_shift.ends_at,
      "team_id" = save_shift.team_id,
      "location_id" = save_shift.location_id,
      "break_minutes" = coalesce(save_shift.break_minutes, 0),
      "headcount" = coalesce(save_shift.headcount, 1),
      "required_qualifications" = v_required,
      "note" = nullif(trim(save_shift.note), ''),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    begin
      update "better_supabase"."shift_assignments" x set "starts_at" = v_row."starts_at", "ends_at" = v_row."ends_at", "updated_at" = now()
      where x."shift_id" = v_row."id" and (x."starts_at" <> v_row."starts_at" or x."ends_at" <> v_row."ends_at");
    exception when exclusion_violation then
      raise exception 'an assigned member has another shift at the new time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) from public, anon;
grant execute on function "better_supabase"."save_shift"(uuid, timestamptz, timestamptz, uuid, uuid, integer, integer, text[], text, uuid) to authenticated, service_role;

-- Cancels a shift and releases its assignments. Assigned members are
-- notified. Canceling one already canceled changes nothing.
create or replace function "better_supabase"."cancel_shift"(shift_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_assignment "better_supabase"."shift_assignments"%rowtype;
  v_users jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shifts" x where x."id" = cancel_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to cancel shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'canceled' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    v_users := coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb);
    update "better_supabase"."shifts" x set "status" = 'canceled', "canceled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    for v_assignment in
      update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
      where x."shift_id" = v_row."id" and x."status" <> 'released'
      returning x.*
    loop
      null;
    end loop;
    null;
    if jsonb_array_length(v_users) > 0 then
      
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'templateId', v_row."template_id", 'teamId', v_row."team_id", 'locationId', v_row."location_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'breakMinutes', v_row."break_minutes", 'headcount', v_row."headcount", 'requiredQualifications', to_jsonb(v_row."required_qualifications"), 'status', v_row."status", 'note', v_row."note", 'publishedAt', v_row."published_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_shift"(uuid, text) to authenticated, service_role;

-- Publishes the draft shifts that start from from_date to until_date (days in the
-- block's time zone), for one team or all. Members then see them, and the
-- assigned members are notified. Returns how many it published.
create or replace function "better_supabase"."publish_shifts"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shifts"%rowtype;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', publish_shifts.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to publish shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if publish_shifts.from_date is null or publish_shifts.until_date is null or publish_shifts.until_date < publish_shifts.from_date then
    raise exception 'until_date is on or after from_date' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  for v_row in
    update "better_supabase"."shifts" x set "status" = 'published', "published_at" = now(), "updated_at" = now()
    where x."org_id" = publish_shifts.tenant
      and x."status" = 'draft'
      and x."starts_at" >= publish_shifts.from_date::timestamp at time zone 'UTC'
      and x."starts_at" < (publish_shifts.until_date + 1)::timestamp at time zone 'UTC'
      and (publish_shifts.team_id is null or x."team_id" = publish_shifts.team_id)
    returning x.*
  loop
    v_count := v_count + 1;
    null;
    if jsonb_array_length(coalesce((select jsonb_agg(x."user_id") from "better_supabase"."shift_assignments" x where x."shift_id" = v_row."id" and x."status" = 'assigned'), '[]'::jsonb)) > 0 then
      
    end if;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."publish_shifts"(uuid, date, date, uuid) to authenticated, service_role;

-- Checks that a member may work a shift: no other assigned shift overlaps,
-- no approved leave falls on its day, they hold its required qualifications
-- and they keep the minimum rest between shifts. Returns warnings (with
-- qualificationCheck "warn") and raises otherwise.
create or replace function "better_supabase"."shift_assignment_check"(shift_id uuid, user_id uuid, assignment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
  v_key text;
begin
  select * into v_shift from "better_supabase"."shifts" x where x."id" = shift_assignment_check.shift_id;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if shift_assignment_check.user_id is null or not exists (select 1 from "better_supabase"."memberships" mm where mm."org_id" = v_shift."org_id" and mm."user_id" = shift_assignment_check.user_id and mm."disabled_at" is null) then
    raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."org_id" = v_shift."org_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at", v_shift."ends_at")
  ) then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end if;
  if exists (
    select 1 from "better_supabase"."shift_assignments" x
    where x."org_id" = v_shift."org_id" and x."user_id" = shift_assignment_check.user_id and x."status" = 'assigned'
      and x."id" is distinct from shift_assignment_check.assignment_id
      and tstzrange(x."starts_at", x."ends_at") && tstzrange(v_shift."starts_at" - interval '11 hours', v_shift."ends_at" + interval '11 hours')
  ) then
    raise exception 'the member would have less than 11 hours between shifts' using errcode = '23514', hint = 'SHIFT_ASSIGNMENT_REST_TOO_SHORT';
  end if;
  return v_warnings;
end;
$$;
revoke execute on function "better_supabase"."shift_assignment_check"(uuid, uuid, uuid) from public, anon, authenticated;

-- Assigns a member to a shift. Returns the assignment with its warnings.
-- Assigning someone already on the shift changes nothing.
create or replace function "better_supabase"."assign_shift"(shift_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = assign_shift.shift_id for update;
  if not found then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_shift."org_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = assign_shift.user_id;
  if found and v_row."status" = 'assigned' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", assign_shift.user_id, v_row."id");
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", assign_shift.user_id;
    end if;
  end;
  begin
    insert into "better_supabase"."shift_assignments" ("org_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."org_id", v_shift."id", assign_shift.user_id, 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  exception when exclusion_violation then
    raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
  end;
  null;
  if v_shift."status" = 'published' then
    
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."assign_shift"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."assign_shift"(uuid, uuid) to authenticated, service_role;

-- Takes a member off a shift, or turns down their request for it.
create or replace function "better_supabase"."unassign_shift"(assignment_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = unassign_shift.assignment_id for update;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'shifts.write'), false)) then
    raise exception 'not allowed to assign shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  v_was := v_row."status";
  if v_was <> 'released' then
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    if v_was = 'assigned' and v_shift."status" = 'published' then
      
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."unassign_shift"(uuid, text) from public, anon;
grant execute on function "better_supabase"."unassign_shift"(uuid, text) to authenticated, service_role;

-- Asks for a place on a published open shift that hasn't started. A planner
-- decides with decide_shift_request.
create or replace function "better_supabase"."request_open_shift"(shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_user uuid := (select auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = request_open_shift.shift_id;
  if not found or v_shift."status" = 'draft' then
    raise exception 'shift not found' using errcode = 'P0002', hint = 'SHIFT_NOT_FOUND';
  end if;
  if v_user is null or not coalesce(better_supabase.can('tenant', v_shift."org_id", 'shifts.request'), false) then
    raise exception 'not allowed to request shifts' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_shift."status" = 'canceled' then
    raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
  end if;
  if v_shift."starts_at" <= now() then
    raise exception 'the shift has started' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."user_id" = v_user;
  if found and v_row."status" <> 'released' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
  perform "better_supabase"."shift_assignment_check"(v_shift."id", v_user, v_row."id");
  insert into "better_supabase"."shift_assignments" ("org_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."org_id", v_shift."id", v_user, 'requested', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'requested', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_open_shift"(uuid) from public, anon;
grant execute on function "better_supabase"."request_open_shift"(uuid) to authenticated, service_role;

-- Approves a request for an open shift (the member is assigned after the
-- same checks as assign_shift) or turns it down.
create or replace function "better_supabase"."decide_shift_request"(assignment_id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_warnings jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = decide_shift_request.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'shifts.manage'), false)) then
    raise exception 'not allowed to decide shift requests' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_row."status" <> 'requested' then
    raise exception 'the assignment isn''t a pending request' using errcode = '22023', hint = 'SHIFT_ASSIGNMENT_INVALID';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if coalesce(decide_shift_request.approve, false) then
    if v_shift."status" = 'canceled' then
      raise exception 'the shift is canceled' using errcode = '55000', hint = 'SHIFT_CANCELED';
    end if;
    if (select count(*) from "better_supabase"."shift_assignments" x where x."shift_id" = v_shift."id" and x."status" = 'assigned') >= v_shift."headcount" then
    raise exception 'the shift has no open places' using errcode = '23514', hint = 'SHIFT_FULL';
  end if;
    v_warnings := "better_supabase"."shift_assignment_check"(v_shift."id", v_row."user_id", v_row."id");
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_shift_assignment_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_shift."id", v_row."user_id";
    end if;
  end;
    begin
      update "better_supabase"."shift_assignments" x set "status" = 'assigned', "starts_at" = v_shift."starts_at", "ends_at" = v_shift."ends_at", "assigned_by" = (select auth.uid()), "updated_at" = now()
      where x."id" = v_row."id"
      returning x.* into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
    
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_shift_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'shiftId', v_row."shift_id", 'userId', v_row."user_id", 'status', v_row."status", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'assignedBy', v_row."assigned_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."decide_shift_request"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."decide_shift_request"(uuid, boolean) to authenticated, service_role;

-- Offers an assigned shift that hasn't started to another member. A manager
-- decides with decide_shift_swap; the member who asked may withdraw it there.
create or replace function "better_supabase"."request_shift_swap"(assignment_id uuid, to_user_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = request_shift_swap.assignment_id;
  if not found then
    raise exception 'shift assignment not found' using errcode = 'P0002', hint = 'SHIFT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (v_row."user_id" = (select auth.uid()) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'shifts.write'), false))) then
    raise exception 'not allowed to swap this shift' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id";
  if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' or v_shift."starts_at" <= now() then
    raise exception 'only an assigned shift that hasn''t started can be swapped' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.to_user_id is null or request_shift_swap.to_user_id = v_row."user_id" or not exists (select 1 from "better_supabase"."memberships" mm where mm."org_id" = v_row."org_id" and mm."user_id" = request_shift_swap.to_user_id and mm."disabled_at" is null) then
    raise exception 'the swap goes to another member of this organization' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if request_shift_swap.note is not null and length(request_shift_swap.note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."shift_swaps" x where x."assignment_id" = v_row."id" and x."status" = 'pending') then
    raise exception 'the shift already has a pending swap' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  insert into "better_supabase"."shift_swaps" ("org_id", "assignment_id", "from_user_id", "to_user_id", "note")
  values (v_row."org_id", v_row."id", v_row."user_id", request_shift_swap.to_user_id, nullif(trim(request_shift_swap.note), ''))
  returning * into v_swap;
  null;
  
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."org_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."request_shift_swap"(uuid, uuid, text) to authenticated, service_role;

-- Approves a pending swap (the other member takes the shift after the same
-- checks as assign_shift) or rejects it. The member who asked may withdraw it
-- (approve false). approval_id links an approvals request.
create or replace function "better_supabase"."decide_shift_swap"(swap_id uuid, approve boolean, approval_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_shift "better_supabase"."shifts"%rowtype;
  v_row "better_supabase"."shift_assignments"%rowtype;
  v_swap "better_supabase"."shift_swaps"%rowtype;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_swap from "better_supabase"."shift_swaps" x where x."id" = decide_shift_swap.swap_id for update;
  if not found then
    raise exception 'shift swap not found' using errcode = 'P0002', hint = 'SHIFT_SWAP_NOT_FOUND';
  end if;
  if (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_swap."org_id", 'shifts.manage'), false)) then
    v_status := case when coalesce(decide_shift_swap.approve, false) then 'approved' else 'rejected' end;
  elsif v_swap."from_user_id" = (select auth.uid()) and not coalesce(decide_shift_swap.approve, false) then
    v_status := 'canceled';
  else
    raise exception 'not allowed to decide shift swaps' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_swap."status" <> 'pending' then
    raise exception 'the swap is already decided' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  if decide_shift_swap.approval_id is not null then
    raise exception 'approval_id needs the approvals block' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
  end if;
  select * into v_row from "better_supabase"."shift_assignments" x where x."id" = v_swap."assignment_id";
  select * into v_shift from "better_supabase"."shifts" x where x."id" = v_row."shift_id" for update;
  if v_status = 'approved' then
    if v_row."status" <> 'assigned' or v_shift."status" = 'canceled' then
      raise exception 'the shift is no longer assigned to the member who asked' using errcode = '22023', hint = 'SHIFT_SWAP_INVALID';
    end if;
    perform "better_supabase"."shift_assignment_check"(v_shift."id", v_swap."to_user_id", null);
    update "better_supabase"."shift_assignments" x set "status" = 'released', "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
    begin
      insert into "better_supabase"."shift_assignments" ("org_id", "shift_id", "user_id", "status", "starts_at", "ends_at", "assigned_by")
  values (v_shift."org_id", v_shift."id", v_swap."to_user_id", 'assigned', v_shift."starts_at", v_shift."ends_at", (select auth.uid()))
  on conflict ("shift_id", "user_id") do update set "status" = 'assigned', "starts_at" = excluded."starts_at", "ends_at" = excluded."ends_at", "assigned_by" = excluded."assigned_by", "updated_at" = now()
  returning * into v_row;
    exception when exclusion_violation then
      raise exception 'the member has another shift at that time' using errcode = '23P01', hint = 'SHIFT_ASSIGNMENT_OVERLAP';
    end;
    null;
  end if;
  update "better_supabase"."shift_swaps" x set "status" = v_status, "decided_at" = now(), "decided_by" = (select auth.uid())
  where x."id" = v_swap."id"
  returning x.* into v_swap;
  null;
  if v_status <> 'canceled' then
    
  end if;
  if v_status = 'approved' then
    
  end if;
  return jsonb_build_object('id', v_swap."id", 'organizationId', v_swap."org_id", 'assignmentId', v_swap."assignment_id", 'fromUserId', v_swap."from_user_id", 'toUserId', v_swap."to_user_id", 'status', v_swap."status", 'approvalId', v_swap."approval_id", 'note', v_swap."note", 'decidedBy', v_swap."decided_by", 'decidedAt', v_swap."decided_at", 'createdAt', v_swap."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."decide_shift_swap"(uuid, boolean, uuid) to authenticated, service_role;

-- Sets a member's availability on a day: available, unavailable or
-- preferred, for the whole day or from_time to until_time. kind null clears
-- the day. Planners (shifts.write) set it for others with user_id.
create or replace function "better_supabase"."set_shift_availability"(tenant uuid, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."shift_availability"%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if v_user = (select auth.uid()) then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.request'), false)) then
      raise exception 'not allowed to set availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_shift_availability.tenant, 'shifts.write'), false)) then
    raise exception 'not allowed to set another member''s availability' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if set_shift_availability.on_date is null then
    raise exception 'on_date is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.kind is null then
    delete from "better_supabase"."shift_availability" x
    where x."org_id" = set_shift_availability.tenant and x."user_id" = v_user and x."on_date" = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ('available', 'unavailable', 'preferred') then
    raise exception 'kind is one of available, unavailable, preferred' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    raise exception 'from_time and until_time are both set, with until_time after from_time, or both null' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    raise exception 'a note is at most 500 characters' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  insert into "better_supabase"."shift_availability" ("org_id", "user_id", "on_date", "from_time", "until_time", "kind", "note")
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind, nullif(trim(set_shift_availability.note), ''))
  on conflict ("org_id", "user_id", "on_date") do update set
    "from_time" = excluded."from_time",
    "until_time" = excluded."until_time",
    "kind" = excluded."kind",
    "note" = excluded."note"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'onDate', v_row."on_date", 'fromTime', to_char(v_row."from_time", 'HH24:MI'), 'untilTime', to_char(v_row."until_time", 'HH24:MI'), 'kind', v_row."kind", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_shift_availability"(uuid, date, text, time, time, text, uuid) to authenticated, service_role;

-- The availability the caller may read from from_date to until_date: their own,
-- or everyone's (or one member's) with shifts.write.
create or replace function "better_supabase"."list_shift_availability"(tenant uuid, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'userId', x."user_id", 'onDate', x."on_date", 'fromTime', to_char(x."from_time", 'HH24:MI'), 'untilTime', to_char(x."until_time", 'HH24:MI'), 'kind', x."kind", 'note', x."note", 'createdAt', x."created_at") order by x."on_date", x."user_id"), '[]'::jsonb)
  from "better_supabase"."shift_availability" x
  where x."org_id" = list_shift_availability.tenant
    and x."on_date" between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x."user_id" = list_shift_availability.user_id)
$$;
revoke execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."list_shift_availability"(uuid, date, date, uuid) to authenticated, service_role;

-- The shifts the caller may read that start from from_date to until_date (days in
-- the block's time zone), for one team or all, each with its assigned and
-- requested members. Members see published shifts; planners also drafts.
create or replace function "better_supabase"."roster"(tenant uuid, from_date date, until_date date, team_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."status", y."user_id")
    from "better_supabase"."shift_assignments" y
    where y."shift_id" = x."id" and y."status" <> 'released'
  ), '[]'::jsonb)) order by x."starts_at", x."id"), '[]'::jsonb)
  from "better_supabase"."shifts" x
  where x."org_id" = roster.tenant
    and x."starts_at" >= (roster.from_date)::timestamp at time zone 'UTC'
    and x."starts_at" < (roster.until_date + 1)::timestamp at time zone 'UTC'
    and (roster.team_id is null or x."team_id" = roster.team_id)
$$;
revoke execute on function "better_supabase"."roster"(uuid, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."roster"(uuid, date, date, uuid) to authenticated, service_role;

-- The caller's shifts (assigned or requested) that start from since to until,
-- in every organization, each with its assignment.
create or replace function "better_supabase"."my_shifts"(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'templateId', x."template_id", 'teamId', x."team_id", 'locationId', x."location_id", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'breakMinutes', x."break_minutes", 'headcount', x."headcount", 'requiredQualifications', to_jsonb(x."required_qualifications"), 'status', x."status", 'note', x."note", 'publishedAt', x."published_at", 'canceledAt', x."canceled_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignment', jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'shiftId', y."shift_id", 'userId', y."user_id", 'status', y."status", 'startsAt', y."starts_at", 'endsAt', y."ends_at", 'assignedBy', y."assigned_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_at"), '[]'::jsonb)
  from "better_supabase"."shift_assignments" y
  join "better_supabase"."shifts" x on x."id" = y."shift_id"
  where y."user_id" = (select auth.uid())
    and y."status" in ('assigned', 'requested')
    and x."status" <> 'draft'
    and x."starts_at" >= coalesce(my_shifts.since, now())
    and x."starts_at" < coalesce(my_shifts.until, now() + interval '30 days')
$$;
revoke execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."my_shifts"(timestamptz, timestamptz) to authenticated, service_role;

-- The hours each member is planned for in the week from week_start (shifts
-- not canceled, breaks taken off), next to their contract hours when the
-- employees block keeps contracts.
create or replace function "better_supabase"."shift_hours"(tenant uuid, week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', shift_hours.tenant, 'shifts.manage'), false)) then
    raise exception 'not allowed to read planned hours' using errcode = '42501', hint = 'SHIFT_FORBIDDEN';
  end if;
  if shift_hours.week_start is null then
    raise exception 'week_start is required' using errcode = '22023', hint = 'SHIFT_INVALID';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.shifts,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.shifts, p.planned, null::numeric as contract
      from (
        select y."user_id" as user_id, count(*)::integer as shifts, round((extract(epoch from sum(x."ends_at" - make_interval(mins => x."break_minutes") - x."starts_at")) / 3600)::numeric, 2) as planned
        from "better_supabase"."shift_assignments" y
        join "better_supabase"."shifts" x on x."id" = y."shift_id"
        where y."org_id" = shift_hours.tenant
          and y."status" = 'assigned'
          and x."status" <> 'canceled'
          and x."starts_at" >= (shift_hours.week_start)::timestamp at time zone 'UTC'
          and x."starts_at" < (shift_hours.week_start + 7)::timestamp at time zone 'UTC'
        group by y."user_id"
      ) p
    ) u
  );
end;
$$;
revoke execute on function "better_supabase"."shift_hours"(uuid, date) from public, anon;
grant execute on function "better_supabase"."shift_hours"(uuid, date) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_templates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_select on "better_supabase"."shift_templates" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_templates" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_update on "better_supabase"."shift_templates" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_templates";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_templates" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shifts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shifts";
create policy bsb_tenant_scope_select on "better_supabase"."shifts" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('shifts.write')) or ("status" <> 'draft' and "org_id" in (select better_supabase.tenant_ids_with('shifts.read'))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shifts";
create policy bsb_tenant_scope_insert on "better_supabase"."shifts" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shifts";
create policy bsb_tenant_scope_update on "better_supabase"."shifts" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shifts";
create policy bsb_tenant_scope_delete on "better_supabase"."shifts" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."shift_assignments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('shifts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_assignments" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."shift_assignments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_assignments" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_swaps";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_select on "better_supabase"."shift_swaps" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("from_user_id" = (select auth.uid()) or "to_user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('shifts.manage')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_swaps" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_update on "better_supabase"."shift_swaps" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_swaps";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_swaps" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shift_availability";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_select on "better_supabase"."shift_availability" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('shifts.write')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_insert on "better_supabase"."shift_availability" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_update on "better_supabase"."shift_availability" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shift_availability";
create policy bsb_tenant_scope_delete on "better_supabase"."shift_availability" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_144_shifts.sql
-- better-supabase module: shifts
-- @bsb-block-data shifts
-- @bsb-hash sha256:1885529dd31ecefd0b84d5f3f56b949fcd6011a51a38cbeec6dd8c7bf0fc1545
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('shifts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
