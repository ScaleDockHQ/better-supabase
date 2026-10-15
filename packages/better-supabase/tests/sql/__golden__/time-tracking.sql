-- ==== alone: schema supabase/schemas/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module time-tracking@1 managed
-- Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
create extension if not exists btree_gist with schema extensions;

create table if not exists "better_supabase"."time_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "subject_type" text,
  "subject_id" text,
  "started_at" timestamptz not null,
  "ended_at" timestamptz,
  "billable" boolean not null default false,
  "rate" numeric(12, 2) check ("rate" is null or "rate" >= 0),
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  -- What metrics sum: the length of a finished entry, null while it runs.
  "seconds" bigint generated always as (extract(epoch from "ended_at" - "started_at")::bigint) stored,
  check ("ended_at" is null or "ended_at" > "started_at"),
  check (("subject_type" is null) = ("subject_id" is null)),
  -- A running entry reaches to infinity, so this also allows one running timer per user.
  constraint "time_entries_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&
  )
);
create unique index if not exists "time_entries_running_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id") where "ended_at" is null;
create index if not exists "time_entries_user_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id", "started_at" desc);
create index if not exists "time_entries_subject_idx" on "better_supabase"."time_entries" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."time_entries" enable row level security;
revoke all on "better_supabase"."time_entries" from anon, authenticated;
grant select on "better_supabase"."time_entries" to authenticated;
grant all on "better_supabase"."time_entries" to service_role;
drop policy if exists "time_entries_read" on "better_supabase"."time_entries";
create policy "time_entries_read" on "better_supabase"."time_entries" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

create table if not exists "better_supabase"."timesheets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "week" date not null check (extract(isodow from "week") = 1),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "week")
);
create index if not exists "timesheets_approval_idx" on "better_supabase"."timesheets" ("approval_id") where "approval_id" is not null;
create index if not exists "timesheets_week_idx" on "better_supabase"."timesheets" ("tenant_id", "week" desc);
alter table "better_supabase"."timesheets" enable row level security;
revoke all on "better_supabase"."timesheets" from anon, authenticated;
grant select on "better_supabase"."timesheets" to authenticated;
grant all on "better_supabase"."timesheets" to service_role;
drop policy if exists "timesheets_read" on "better_supabase"."timesheets";
create policy "timesheets_read" on "better_supabase"."timesheets" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

-- The Monday of the week an instant falls in, in options.timeZone.
create or replace function "better_supabase"."time_week"(at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select (date_trunc('week', time_week.at at time zone 'UTC'))::date;
$$;
revoke execute on function "better_supabase"."time_week"(timestamptz) from public, anon;
grant execute on function "better_supabase"."time_week"(timestamptz) to authenticated, service_role;

-- A week is locked while its timesheet waits for approval and once it is approved.
create or replace function "better_supabase"."time_week_locked"(tenant uuid, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = time_week_locked.tenant and s."user_id" = time_week_locked.user_id
      and s."week" = "better_supabase"."time_week"(time_week_locked.at)
      and (s."approved_at" is not null or x."status" = 'pending')
  );
$$;
revoke execute on function "better_supabase"."time_week_locked"(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."time_entry_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and "better_supabase"."time_week_locked"(old."tenant_id", old."user_id", old."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and "better_supabase"."time_week_locked"(new."tenant_id", new."user_id", new."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."time_entry_guard"() from public, anon, authenticated;
drop trigger if exists bs_time_entry_guard on "better_supabase"."time_entries";
create trigger bs_time_entry_guard
  before insert or update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."time_entry_guard"();

-- Starts a timer for the caller, stopping the one that runs.
create or replace function "better_supabase"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    null;
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) from public, anon;
grant execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) to authenticated, service_role;

create or replace function "better_supabase"."stop_timer"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x
    where x."tenant_id" = stop_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    for update;
  if not found then
    raise exception 'no timer is running' using errcode = 'P0002', hint = 'TIME_NO_TIMER';
  end if;
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."stop_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."stop_timer"(uuid) to authenticated, service_role;

-- The caller's running timer, or null.
create or replace function "better_supabase"."running_timer"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timer.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "better_supabase"."running_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."running_timer"(uuid) to authenticated, service_role;

-- Records finished time. Logging for another member needs the manage permission.
create or replace function "better_supabase"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) from public, anon;
grant execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) to authenticated, service_role;

-- Changes the keys in patch: startedAt, endedAt, subjectType and subjectId
-- together, billable, rate and note.
create or replace function "better_supabase"."update_time_entry"(entry_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' then
    v_row."rate" := (v_patch ->> 'rate')::numeric;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_time_entry"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_time_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = delete_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to delete this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "better_supabase"."time_entries" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_entry"(uuid) to authenticated, service_role;

-- A member's entries (the caller's by default), or every member's on a
-- record with everyone. Other members' entries need the read permission.
create or replace function "better_supabase"."list_time_entries"(tenant uuid, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((v_user = auth.uid() and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."time_entries" x
    where x."tenant_id" = list_time_entries.tenant
      and (list_time_entries.everyone or x."user_id" = v_user)
      and (list_time_entries.starts is null or coalesce(x."ended_at", 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x."started_at" < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x."subject_type" = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x."subject_id" = list_time_entries.subject_id)
    order by x."started_at" desc
    limit least(greatest(coalesce(list_time_entries.page_size, 200), 1), 1000)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) to authenticated, service_role;

-- One member's week: the timesheet (status open when there is none yet),
-- the entries that start in it and their totals.
create or replace function "better_supabase"."get_timesheet"(tenant uuid, week date, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read this timesheet' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = get_timesheet.tenant and s."user_id" = v_user and s."week" = v_week;
  if found then
    select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
    v_json := jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, 'userId', v_user, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."started_at"), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")) filter (where x."billable"), 0)::bigint,
      'amount', round(coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at") / 3600 * x."rate") filter (where x."billable"), 0), 2)
    )
    into v_entries, v_totals
  from "better_supabase"."time_entries" x
  where x."tenant_id" = get_timesheet.tenant and x."user_id" = v_user
    and "better_supabase"."time_week"(x."started_at") = v_week;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
end;
$$;
revoke execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) to authenticated, service_role;

-- Sends the caller's week for approval. The week locks until a rejection.
create or replace function "better_supabase"."submit_timesheet"(tenant uuid, week date, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "better_supabase"."time_week"(x."started_at") = v_week;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_tracking.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "better_supabase"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."submit_timesheet"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."submit_timesheet"(uuid, date, text) to authenticated, service_role;

-- Locks the week once the approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function "better_supabase"."approve_timesheet"(timesheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
begin
  update "better_supabase"."timesheets" s set "approved_at" = now()
    where s."id" = approve_timesheet.timesheet_id and s."approved_at" is null
    returning * into v_sheet;
  if found then
    null;
  end if;
end;
$$;
revoke execute on function "better_supabase"."approve_timesheet"(uuid) from public, anon, authenticated;

-- Unlocks an approved week so its entries can change and it can be sent again.
create or replace function "better_supabase"."reopen_timesheet"(timesheet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s where s."id" = reopen_timesheet.timesheet_id for update;
  if not found then
    raise exception 'timesheet not found' using errcode = 'P0002', hint = 'TIMESHEET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sheet."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to reopen timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_sheet."approved_at" is null then
    raise exception 'only an approved week can be reopened' using errcode = '55000', hint = 'TIMESHEET_NOT_APPROVED';
  end if;
  update "better_supabase"."timesheets" s set "approved_at" = null, "approval_id" = null, "submitted_at" = null
    where s."id" = v_sheet."id"
    returning * into v_sheet;
  null;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_timesheet"(uuid) from public, anon;
grant execute on function "better_supabase"."reopen_timesheet"(uuid) to authenticated, service_role;

-- Newest week first: the caller's timesheets, or everyone's with the read permission.
create or replace function "better_supabase"."list_timesheets"(tenant uuid, user_id uuid default null, status text default null, page_size integer default 50, before date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.track'), false)) then
    raise exception 'not allowed to list timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id <> auth.uid() then
    raise exception 'not allowed to read another member''s timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.week desc, q.created desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', s."id", 'organizationId', s."tenant_id", 'userId', s."user_id", 'week', s."week", 'status', case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', s."approval_id", 'note', s."note", 'submittedAt', s."submitted_at", 'approvedAt', s."approved_at", 'createdAt', s."created_at") as item, s."week" as week, s."created_at" as created
    from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = list_timesheets.tenant
      and (case when v_reader then list_timesheets.user_id is null or s."user_id" = list_timesheets.user_id else s."user_id" = auth.uid() end)
      and (list_timesheets.status is null or case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end = list_timesheets.status)
      and (list_timesheets.before is null or s."week" < list_timesheets.before)
    order by s."week" desc, s."created_at" desc
    limit least(greatest(coalesce(list_timesheets.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) from public, anon;
grant execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module-data time-tracking
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('time-tracking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module time-tracking@1 managed
-- Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
create extension if not exists btree_gist with schema extensions;

create table if not exists "better_supabase"."time_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "subject_type" text,
  "subject_id" text,
  "started_at" timestamptz not null,
  "ended_at" timestamptz,
  "billable" boolean not null default false,
  "rate" numeric(12, 2) check ("rate" is null or "rate" >= 0),
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  -- What metrics sum: the length of a finished entry, null while it runs.
  "seconds" bigint generated always as (extract(epoch from "ended_at" - "started_at")::bigint) stored,
  check ("ended_at" is null or "ended_at" > "started_at"),
  check (("subject_type" is null) = ("subject_id" is null)),
  -- A running entry reaches to infinity, so this also allows one running timer per user.
  constraint "time_entries_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&
  )
);
create unique index if not exists "time_entries_running_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id") where "ended_at" is null;
create index if not exists "time_entries_user_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id", "started_at" desc);
create index if not exists "time_entries_subject_idx" on "better_supabase"."time_entries" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."time_entries" enable row level security;
revoke all on "better_supabase"."time_entries" from anon, authenticated;
grant select on "better_supabase"."time_entries" to authenticated;
grant all on "better_supabase"."time_entries" to service_role;
drop policy if exists "time_entries_read" on "better_supabase"."time_entries";
create policy "time_entries_read" on "better_supabase"."time_entries" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

create table if not exists "better_supabase"."timesheets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "week" date not null check (extract(isodow from "week") = 1),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "week")
);
create index if not exists "timesheets_approval_idx" on "better_supabase"."timesheets" ("approval_id") where "approval_id" is not null;
create index if not exists "timesheets_week_idx" on "better_supabase"."timesheets" ("tenant_id", "week" desc);
alter table "better_supabase"."timesheets" enable row level security;
revoke all on "better_supabase"."timesheets" from anon, authenticated;
grant select on "better_supabase"."timesheets" to authenticated;
grant all on "better_supabase"."timesheets" to service_role;
drop policy if exists "timesheets_read" on "better_supabase"."timesheets";
create policy "timesheets_read" on "better_supabase"."timesheets" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

-- The Monday of the week an instant falls in, in options.timeZone.
create or replace function "better_supabase"."time_week"(at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select (date_trunc('week', time_week.at at time zone 'UTC'))::date;
$$;
revoke execute on function "better_supabase"."time_week"(timestamptz) from public, anon;
grant execute on function "better_supabase"."time_week"(timestamptz) to authenticated, service_role;

-- A week is locked while its timesheet waits for approval and once it is approved.
create or replace function "better_supabase"."time_week_locked"(tenant uuid, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = time_week_locked.tenant and s."user_id" = time_week_locked.user_id
      and s."week" = "better_supabase"."time_week"(time_week_locked.at)
      and (s."approved_at" is not null or x."status" = 'pending')
  );
$$;
revoke execute on function "better_supabase"."time_week_locked"(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."time_entry_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and "better_supabase"."time_week_locked"(old."tenant_id", old."user_id", old."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and "better_supabase"."time_week_locked"(new."tenant_id", new."user_id", new."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."time_entry_guard"() from public, anon, authenticated;
drop trigger if exists bs_time_entry_guard on "better_supabase"."time_entries";
create trigger bs_time_entry_guard
  before insert or update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."time_entry_guard"();

-- Starts a timer for the caller, stopping the one that runs.
create or replace function "better_supabase"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.started', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) from public, anon;
grant execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) to authenticated, service_role;

create or replace function "better_supabase"."stop_timer"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x
    where x."tenant_id" = stop_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    for update;
  if not found then
    raise exception 'no timer is running' using errcode = 'P0002', hint = 'TIME_NO_TIMER';
  end if;
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."stop_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."stop_timer"(uuid) to authenticated, service_role;

-- The caller's running timer, or null.
create or replace function "better_supabase"."running_timer"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timer.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "better_supabase"."running_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."running_timer"(uuid) to authenticated, service_role;

-- Records finished time. Logging for another member needs the manage permission.
create or replace function "better_supabase"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) from public, anon;
grant execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) to authenticated, service_role;

-- Changes the keys in patch: startedAt, endedAt, subjectType and subjectId
-- together, billable, rate and note.
create or replace function "better_supabase"."update_time_entry"(entry_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' then
    v_row."rate" := (v_patch ->> 'rate')::numeric;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'previousStartedAt', v_previous_started_at), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_time_entry"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_time_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = delete_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to delete this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "better_supabase"."time_entries" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('time_entry.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_entry"(uuid) to authenticated, service_role;

-- A member's entries (the caller's by default), or every member's on a
-- record with everyone. Other members' entries need the read permission.
create or replace function "better_supabase"."list_time_entries"(tenant uuid, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((v_user = auth.uid() and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."time_entries" x
    where x."tenant_id" = list_time_entries.tenant
      and (list_time_entries.everyone or x."user_id" = v_user)
      and (list_time_entries.starts is null or coalesce(x."ended_at", 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x."started_at" < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x."subject_type" = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x."subject_id" = list_time_entries.subject_id)
    order by x."started_at" desc
    limit least(greatest(coalesce(list_time_entries.page_size, 200), 1), 1000)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) to authenticated, service_role;

-- One member's week: the timesheet (status open when there is none yet),
-- the entries that start in it and their totals.
create or replace function "better_supabase"."get_timesheet"(tenant uuid, week date, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read this timesheet' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = get_timesheet.tenant and s."user_id" = v_user and s."week" = v_week;
  if found then
    select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
    v_json := jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, 'userId', v_user, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."started_at"), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")) filter (where x."billable"), 0)::bigint,
      'amount', round(coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at") / 3600 * x."rate") filter (where x."billable"), 0), 2)
    )
    into v_entries, v_totals
  from "better_supabase"."time_entries" x
  where x."tenant_id" = get_timesheet.tenant and x."user_id" = v_user
    and "better_supabase"."time_week"(x."started_at") = v_week;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
end;
$$;
revoke execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) to authenticated, service_role;

-- Sends the caller's week for approval. The week locks until a rejection.
create or replace function "better_supabase"."submit_timesheet"(tenant uuid, week date, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "better_supabase"."time_week"(x."started_at") = v_week;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_tracking.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "better_supabase"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  perform "better_supabase".emit_event('timesheet.submitted', jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id"), 'timesheets/' || v_sheet."id"::text, (v_sheet."tenant_id")::text, null, 'better-supabase/time-tracking');
  perform better_supabase.audit_event(
    event_type => 'timesheet.submitted',
    category => 'data',
    target_type => 'timesheet',
    record_id => v_sheet."id"::text,
    summary => 'submitted a timesheet' || ' for the week of ' || v_sheet."week"::text,
    tenant => (v_sheet."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."submit_timesheet"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."submit_timesheet"(uuid, date, text) to authenticated, service_role;

-- Locks the week once the approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function "better_supabase"."approve_timesheet"(timesheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
begin
  update "better_supabase"."timesheets" s set "approved_at" = now()
    where s."id" = approve_timesheet.timesheet_id and s."approved_at" is null
    returning * into v_sheet;
  if found then
    perform "better_supabase".emit_event('timesheet.approved', jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id"), 'timesheets/' || v_sheet."id"::text, (v_sheet."tenant_id")::text, null, 'better-supabase/time-tracking');
  perform better_supabase.audit_event(
    event_type => 'timesheet.approved',
    category => 'data',
    target_type => 'timesheet',
    record_id => v_sheet."id"::text,
    summary => 'approved a timesheet' || ' for the week of ' || v_sheet."week"::text,
    tenant => (v_sheet."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id")
  );
  end if;
end;
$$;
revoke execute on function "better_supabase"."approve_timesheet"(uuid) from public, anon, authenticated;

-- Unlocks an approved week so its entries can change and it can be sent again.
create or replace function "better_supabase"."reopen_timesheet"(timesheet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s where s."id" = reopen_timesheet.timesheet_id for update;
  if not found then
    raise exception 'timesheet not found' using errcode = 'P0002', hint = 'TIMESHEET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sheet."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to reopen timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_sheet."approved_at" is null then
    raise exception 'only an approved week can be reopened' using errcode = '55000', hint = 'TIMESHEET_NOT_APPROVED';
  end if;
  update "better_supabase"."timesheets" s set "approved_at" = null, "approval_id" = null, "submitted_at" = null
    where s."id" = v_sheet."id"
    returning * into v_sheet;
  perform "better_supabase".emit_event('timesheet.reopened', jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id"), 'timesheets/' || v_sheet."id"::text, (v_sheet."tenant_id")::text, null, 'better-supabase/time-tracking');
  perform better_supabase.audit_event(
    event_type => 'timesheet.reopened',
    category => 'data',
    target_type => 'timesheet',
    record_id => v_sheet."id"::text,
    summary => 'reopened a timesheet' || ' for the week of ' || v_sheet."week"::text,
    tenant => (v_sheet."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_sheet."tenant_id", 'id', v_sheet."id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'approvalId', v_sheet."approval_id")
  );
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_timesheet"(uuid) from public, anon;
grant execute on function "better_supabase"."reopen_timesheet"(uuid) to authenticated, service_role;

-- Newest week first: the caller's timesheets, or everyone's with the read permission.
create or replace function "better_supabase"."list_timesheets"(tenant uuid, user_id uuid default null, status text default null, page_size integer default 50, before date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.track'), false)) then
    raise exception 'not allowed to list timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id <> auth.uid() then
    raise exception 'not allowed to read another member''s timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.week desc, q.created desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', s."id", 'organizationId', s."tenant_id", 'userId', s."user_id", 'week', s."week", 'status', case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', s."approval_id", 'note', s."note", 'submittedAt', s."submitted_at", 'approvedAt', s."approved_at", 'createdAt', s."created_at") as item, s."week" as week, s."created_at" as created
    from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = list_timesheets.tenant
      and (case when v_reader then list_timesheets.user_id is null or s."user_id" = list_timesheets.user_id else s."user_id" = auth.uid() end)
      and (list_timesheets.status is null or case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end = list_timesheets.status)
      and (list_timesheets.before is null or s."week" < list_timesheets.before)
    order by s."week" desc, s."created_at" desc
    limit least(greatest(coalesce(list_timesheets.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) from public, anon;
grant execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module-data time-tracking
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('time-tracking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module time-tracking@1 managed
-- Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create extension if not exists btree_gist with schema extensions;

create table if not exists "app_private"."time_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "subject_type" text,
  "subject_id" text,
  "started_at" timestamptz not null,
  "ended_at" timestamptz,
  "billable" boolean not null default false,
  "rate" numeric(12, 2) check ("rate" is null or "rate" >= 0),
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  -- What metrics sum: the length of a finished entry, null while it runs.
  "seconds" bigint generated always as (extract(epoch from "ended_at" - "started_at")::bigint) stored,
  check ("ended_at" is null or "ended_at" > "started_at"),
  check (("subject_type" is null) = ("subject_id" is null)),
  -- A running entry reaches to infinity, so this also allows one running timer per user.
  constraint "time_entries_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&
  )
);
create unique index if not exists "time_entries_running_idx" on "app_private"."time_entries" ("tenant_id", "user_id") where "ended_at" is null;
create index if not exists "time_entries_user_idx" on "app_private"."time_entries" ("tenant_id", "user_id", "started_at" desc);
create index if not exists "time_entries_subject_idx" on "app_private"."time_entries" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "app_private"."time_entries" enable row level security;
revoke all on "app_private"."time_entries" from anon, authenticated;
grant select on "app_private"."time_entries" to authenticated;
grant all on "app_private"."time_entries" to service_role;
drop policy if exists "time_entries_read" on "app_private"."time_entries";
create policy "time_entries_read" on "app_private"."time_entries" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

create table if not exists "app_private"."timesheets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "week" date not null check (extract(isodow from "week") = 1),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "week")
);
create index if not exists "timesheets_approval_idx" on "app_private"."timesheets" ("approval_id") where "approval_id" is not null;
create index if not exists "timesheets_week_idx" on "app_private"."timesheets" ("tenant_id", "week" desc);
alter table "app_private"."timesheets" enable row level security;
revoke all on "app_private"."timesheets" from anon, authenticated;
grant select on "app_private"."timesheets" to authenticated;
grant all on "app_private"."timesheets" to service_role;
drop policy if exists "timesheets_read" on "app_private"."timesheets";
create policy "timesheets_read" on "app_private"."timesheets" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

-- The Monday of the week an instant falls in, in options.timeZone.
create or replace function "app_private"."time_week"(at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select (date_trunc('week', time_week.at at time zone 'UTC'))::date;
$$;
revoke execute on function "app_private"."time_week"(timestamptz) from public, anon;
grant execute on function "app_private"."time_week"(timestamptz) to authenticated, service_role;

-- A week is locked while its timesheet waits for approval and once it is approved.
create or replace function "app_private"."time_week_locked"(tenant uuid, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "app_private"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = time_week_locked.tenant and s."user_id" = time_week_locked.user_id
      and s."week" = "app_private"."time_week"(time_week_locked.at)
      and (s."approved_at" is not null or x."status" = 'pending')
  );
$$;
revoke execute on function "app_private"."time_week_locked"(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function "app_private"."time_entry_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and "app_private"."time_week_locked"(old."tenant_id", old."user_id", old."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and "app_private"."time_week_locked"(new."tenant_id", new."user_id", new."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function "app_private"."time_entry_guard"() from public, anon, authenticated;
drop trigger if exists bs_time_entry_guard on "app_private"."time_entries";
create trigger bs_time_entry_guard
  before insert or update or delete on "app_private"."time_entries"
  for each row execute function "app_private"."time_entry_guard"();

-- Starts a timer for the caller, stopping the one that runs.
create or replace function "app_private"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "app_private"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "app_private"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    null;
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "app_private"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "app_private"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."start_timer"(uuid, text, text, boolean, numeric, text) from public, anon;
grant execute on function "app_private"."start_timer"(uuid, text, text, boolean, numeric, text) to authenticated, service_role;

create or replace function "app_private"."stop_timer"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "app_private"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."time_entries" x
    where x."tenant_id" = stop_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    for update;
  if not found then
    raise exception 'no timer is running' using errcode = 'P0002', hint = 'TIME_NO_TIMER';
  end if;
  update "app_private"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."stop_timer"(uuid) from public, anon;
grant execute on function "app_private"."stop_timer"(uuid) to authenticated, service_role;

-- The caller's running timer, or null.
create or replace function "app_private"."running_timer"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "app_private"."time_entries" x
  where x."tenant_id" = running_timer.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "app_private"."running_timer"(uuid) from public, anon;
grant execute on function "app_private"."running_timer"(uuid) to authenticated, service_role;

-- Records finished time. Logging for another member needs the manage permission.
create or replace function "app_private"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "app_private"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "app_private"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "app_private"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) from public, anon;
grant execute on function "app_private"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) to authenticated, service_role;

-- Changes the keys in patch: startedAt, endedAt, subjectType and subjectId
-- together, billable, rate and note.
create or replace function "app_private"."update_time_entry"(entry_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' then
    v_row."rate" := (v_patch ->> 'rate')::numeric;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "app_private"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "app_private"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_time_entry"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_time_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "app_private"."delete_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."time_entries" x where x."id" = delete_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to delete this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "app_private"."time_entries" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."delete_time_entry"(uuid) from public, anon;
grant execute on function "app_private"."delete_time_entry"(uuid) to authenticated, service_role;

-- A member's entries (the caller's by default), or every member's on a
-- record with everyone. Other members' entries need the read permission.
create or replace function "app_private"."list_time_entries"(tenant uuid, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((v_user = auth.uid() and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "app_private"."time_entries" x
    where x."tenant_id" = list_time_entries.tenant
      and (list_time_entries.everyone or x."user_id" = v_user)
      and (list_time_entries.starts is null or coalesce(x."ended_at", 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x."started_at" < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x."subject_type" = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x."subject_id" = list_time_entries.subject_id)
    order by x."started_at" desc
    limit least(greatest(coalesce(list_time_entries.page_size, 200), 1), 1000)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) from public, anon;
grant execute on function "app_private"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) to authenticated, service_role;

-- One member's week: the timesheet (status open when there is none yet),
-- the entries that start in it and their totals.
create or replace function "app_private"."get_timesheet"(tenant uuid, week date, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet "app_private"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read this timesheet' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select * into v_sheet from "app_private"."timesheets" s
    where s."tenant_id" = get_timesheet.tenant and s."user_id" = v_user and s."week" = v_week;
  if found then
    select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
    v_json := jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, 'userId', v_user, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."started_at"), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")) filter (where x."billable"), 0)::bigint,
      'amount', round(coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at") / 3600 * x."rate") filter (where x."billable"), 0), 2)
    )
    into v_entries, v_totals
  from "app_private"."time_entries" x
  where x."tenant_id" = get_timesheet.tenant and x."user_id" = v_user
    and "app_private"."time_week"(x."started_at") = v_week;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
end;
$$;
revoke execute on function "app_private"."get_timesheet"(uuid, date, uuid) from public, anon;
grant execute on function "app_private"."get_timesheet"(uuid, date, uuid) to authenticated, service_role;

-- Sends the caller's week for approval. The week locks until a rejection.
create or replace function "app_private"."submit_timesheet"(tenant uuid, week date, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "app_private"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "app_private"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "app_private"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "app_private"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "app_private"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "app_private"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "app_private"."time_week"(x."started_at") = v_week;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_tracking.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "app_private"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "app_private"."submit_timesheet"(uuid, date, text) from public, anon;
grant execute on function "app_private"."submit_timesheet"(uuid, date, text) to authenticated, service_role;

-- Locks the week once the approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function "app_private"."approve_timesheet"(timesheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "app_private"."timesheets"%rowtype;
begin
  update "app_private"."timesheets" s set "approved_at" = now()
    where s."id" = approve_timesheet.timesheet_id and s."approved_at" is null
    returning * into v_sheet;
  if found then
    null;
  end if;
end;
$$;
revoke execute on function "app_private"."approve_timesheet"(uuid) from public, anon, authenticated;

-- Unlocks an approved week so its entries can change and it can be sent again.
create or replace function "app_private"."reopen_timesheet"(timesheet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "app_private"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sheet from "app_private"."timesheets" s where s."id" = reopen_timesheet.timesheet_id for update;
  if not found then
    raise exception 'timesheet not found' using errcode = 'P0002', hint = 'TIMESHEET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sheet."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to reopen timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_sheet."approved_at" is null then
    raise exception 'only an approved week can be reopened' using errcode = '55000', hint = 'TIMESHEET_NOT_APPROVED';
  end if;
  update "app_private"."timesheets" s set "approved_at" = null, "approval_id" = null, "submitted_at" = null
    where s."id" = v_sheet."id"
    returning * into v_sheet;
  null;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "app_private"."reopen_timesheet"(uuid) from public, anon;
grant execute on function "app_private"."reopen_timesheet"(uuid) to authenticated, service_role;

-- Newest week first: the caller's timesheets, or everyone's with the read permission.
create or replace function "app_private"."list_timesheets"(tenant uuid, user_id uuid default null, status text default null, page_size integer default 50, before date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.track'), false)) then
    raise exception 'not allowed to list timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id <> auth.uid() then
    raise exception 'not allowed to read another member''s timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.week desc, q.created desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', s."id", 'organizationId', s."tenant_id", 'userId', s."user_id", 'week', s."week", 'status', case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', s."approval_id", 'note', s."note", 'submittedAt', s."submitted_at", 'approvedAt', s."approved_at", 'createdAt', s."created_at") as item, s."week" as week, s."created_at" as created
    from "app_private"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = list_timesheets.tenant
      and (case when v_reader then list_timesheets.user_id is null or s."user_id" = list_timesheets.user_id else s."user_id" = auth.uid() end)
      and (list_timesheets.status is null or case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end = list_timesheets.status)
      and (list_timesheets.before is null or s."week" < list_timesheets.before)
    order by s."week" desc, s."created_at" desc
    limit least(greatest(coalesce(list_timesheets.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."list_timesheets"(uuid, uuid, text, integer, date) from public, anon;
grant execute on function "app_private"."list_timesheets"(uuid, uuid, text, integer, date) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module-data time-tracking
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('time-tracking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module time-tracking@1 managed
-- Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
create extension if not exists btree_gist with schema extensions;

create table if not exists "better_supabase"."time_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "subject_type" text,
  "subject_id" text,
  "started_at" timestamptz not null,
  "ended_at" timestamptz,
  "billable" boolean not null default false,
  "rate" numeric(12, 2) check ("rate" is null or "rate" >= 0),
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  -- What metrics sum: the length of a finished entry, null while it runs.
  "seconds" bigint generated always as (extract(epoch from "ended_at" - "started_at")::bigint) stored,
  check ("ended_at" is null or "ended_at" > "started_at"),
  check (("subject_type" is null) = ("subject_id" is null)),
  -- A running entry reaches to infinity, so this also allows one running timer per user.
  constraint "time_entries_no_overlap" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&
  )
);
create unique index if not exists "time_entries_running_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id") where "ended_at" is null;
create index if not exists "time_entries_user_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id", "started_at" desc);
create index if not exists "time_entries_subject_idx" on "better_supabase"."time_entries" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."time_entries" enable row level security;
revoke all on "better_supabase"."time_entries" from anon, authenticated;
grant select on "better_supabase"."time_entries" to authenticated;
grant all on "better_supabase"."time_entries" to service_role;
drop policy if exists "time_entries_read" on "better_supabase"."time_entries";
create policy "time_entries_read" on "better_supabase"."time_entries" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

create table if not exists "better_supabase"."timesheets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "week" date not null check (extract(isodow from "week") = 1),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "week")
);
create index if not exists "timesheets_approval_idx" on "better_supabase"."timesheets" ("approval_id") where "approval_id" is not null;
create index if not exists "timesheets_week_idx" on "better_supabase"."timesheets" ("tenant_id", "week" desc);
alter table "better_supabase"."timesheets" enable row level security;
revoke all on "better_supabase"."timesheets" from anon, authenticated;
grant select on "better_supabase"."timesheets" to authenticated;
grant all on "better_supabase"."timesheets" to service_role;
drop policy if exists "timesheets_read" on "better_supabase"."timesheets";
create policy "timesheets_read" on "better_supabase"."timesheets" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')));

-- The Monday of the week an instant falls in, in options.timeZone.
create or replace function "better_supabase"."time_week"(at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select (date_trunc('week', time_week.at at time zone 'UTC'))::date;
$$;
revoke execute on function "better_supabase"."time_week"(timestamptz) from public, anon;
grant execute on function "better_supabase"."time_week"(timestamptz) to authenticated, service_role;

-- A week is locked while its timesheet waits for approval and once it is approved.
create or replace function "better_supabase"."time_week_locked"(tenant uuid, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = time_week_locked.tenant and s."user_id" = time_week_locked.user_id
      and s."week" = "better_supabase"."time_week"(time_week_locked.at)
      and (s."approved_at" is not null or x."status" = 'pending')
  );
$$;
revoke execute on function "better_supabase"."time_week_locked"(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."time_entry_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and "better_supabase"."time_week_locked"(old."tenant_id", old."user_id", old."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and "better_supabase"."time_week_locked"(new."tenant_id", new."user_id", new."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."time_entry_guard"() from public, anon, authenticated;
drop trigger if exists bs_time_entry_guard on "better_supabase"."time_entries";
create trigger bs_time_entry_guard
  before insert or update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."time_entry_guard"();

-- Starts a timer for the caller, stopping the one that runs.
create or replace function "better_supabase"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    null;
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) from public, anon;
grant execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) to authenticated, service_role;

create or replace function "better_supabase"."stop_timer"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x
    where x."tenant_id" = stop_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    for update;
  if not found then
    raise exception 'no timer is running' using errcode = 'P0002', hint = 'TIME_NO_TIMER';
  end if;
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."stop_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."stop_timer"(uuid) to authenticated, service_role;

-- The caller's running timer, or null.
create or replace function "better_supabase"."running_timer"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timer.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "better_supabase"."running_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."running_timer"(uuid) to authenticated, service_role;

-- Records finished time. Logging for another member needs the manage permission.
create or replace function "better_supabase"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) from public, anon;
grant execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) to authenticated, service_role;

-- Changes the keys in patch: startedAt, endedAt, subjectType and subjectId
-- together, billable, rate and note.
create or replace function "better_supabase"."update_time_entry"(entry_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' then
    v_row."rate" := (v_patch ->> 'rate')::numeric;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_time_entry"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_time_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = delete_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to delete this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "better_supabase"."time_entries" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_entry"(uuid) to authenticated, service_role;

-- A member's entries (the caller's by default), or every member's on a
-- record with everyone. Other members' entries need the read permission.
create or replace function "better_supabase"."list_time_entries"(tenant uuid, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((v_user = auth.uid() and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."time_entries" x
    where x."tenant_id" = list_time_entries.tenant
      and (list_time_entries.everyone or x."user_id" = v_user)
      and (list_time_entries.starts is null or coalesce(x."ended_at", 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x."started_at" < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x."subject_type" = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x."subject_id" = list_time_entries.subject_id)
    order by x."started_at" desc
    limit least(greatest(coalesce(list_time_entries.page_size, 200), 1), 1000)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) to authenticated, service_role;

-- One member's week: the timesheet (status open when there is none yet),
-- the entries that start in it and their totals.
create or replace function "better_supabase"."get_timesheet"(tenant uuid, week date, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read this timesheet' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = get_timesheet.tenant and s."user_id" = v_user and s."week" = v_week;
  if found then
    select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
    v_json := jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, 'userId', v_user, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."started_at"), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")) filter (where x."billable"), 0)::bigint,
      'amount', round(coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at") / 3600 * x."rate") filter (where x."billable"), 0), 2)
    )
    into v_entries, v_totals
  from "better_supabase"."time_entries" x
  where x."tenant_id" = get_timesheet.tenant and x."user_id" = v_user
    and "better_supabase"."time_week"(x."started_at") = v_week;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
end;
$$;
revoke execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) to authenticated, service_role;

-- Sends the caller's week for approval. The week locks until a rejection.
create or replace function "better_supabase"."submit_timesheet"(tenant uuid, week date, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "better_supabase"."time_week"(x."started_at") = v_week;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_tracking.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "better_supabase"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."submit_timesheet"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."submit_timesheet"(uuid, date, text) to authenticated, service_role;

-- Locks the week once the approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function "better_supabase"."approve_timesheet"(timesheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
begin
  update "better_supabase"."timesheets" s set "approved_at" = now()
    where s."id" = approve_timesheet.timesheet_id and s."approved_at" is null
    returning * into v_sheet;
  if found then
    null;
  end if;
end;
$$;
revoke execute on function "better_supabase"."approve_timesheet"(uuid) from public, anon, authenticated;

-- Unlocks an approved week so its entries can change and it can be sent again.
create or replace function "better_supabase"."reopen_timesheet"(timesheet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s where s."id" = reopen_timesheet.timesheet_id for update;
  if not found then
    raise exception 'timesheet not found' using errcode = 'P0002', hint = 'TIMESHEET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sheet."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to reopen timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_sheet."approved_at" is null then
    raise exception 'only an approved week can be reopened' using errcode = '55000', hint = 'TIMESHEET_NOT_APPROVED';
  end if;
  update "better_supabase"."timesheets" s set "approved_at" = null, "approval_id" = null, "submitted_at" = null
    where s."id" = v_sheet."id"
    returning * into v_sheet;
  null;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_timesheet"(uuid) from public, anon;
grant execute on function "better_supabase"."reopen_timesheet"(uuid) to authenticated, service_role;

-- Newest week first: the caller's timesheets, or everyone's with the read permission.
create or replace function "better_supabase"."list_timesheets"(tenant uuid, user_id uuid default null, status text default null, page_size integer default 50, before date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.track'), false)) then
    raise exception 'not allowed to list timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id <> auth.uid() then
    raise exception 'not allowed to read another member''s timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.week desc, q.created desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', s."id", 'organizationId', s."tenant_id", 'userId', s."user_id", 'week', s."week", 'status', case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', s."approval_id", 'note', s."note", 'submittedAt', s."submitted_at", 'approvedAt', s."approved_at", 'createdAt', s."created_at") as item, s."week" as week, s."created_at" as created
    from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = list_timesheets.tenant
      and (case when v_reader then list_timesheets.user_id is null or s."user_id" = list_timesheets.user_id else s."user_id" = auth.uid() end)
      and (list_timesheets.status is null or case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end = list_timesheets.status)
      and (list_timesheets.before is null or s."week" < list_timesheets.before)
    order by s."week" desc, s."created_at" desc
    limit least(greatest(coalesce(list_timesheets.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) from public, anon;
grant execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) to authenticated, service_role;

-- blocks.time-tracking.api: entry points for the Data API.
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

create or replace function "api"."time_week"(at timestamptz)
returns date
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."time_week"($1) $$;
revoke execute on function "api"."time_week"(timestamptz) from public, anon;
grant execute on function "api"."time_week"(timestamptz) to authenticated, service_role;

create or replace function "api"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_timer"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."start_timer"(uuid, text, text, boolean, numeric, text) from public, anon;
grant execute on function "api"."start_timer"(uuid, text, text, boolean, numeric, text) to authenticated, service_role;

create or replace function "api"."stop_timer"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."stop_timer"($1) $$;
revoke execute on function "api"."stop_timer"(uuid) from public, anon;
grant execute on function "api"."stop_timer"(uuid) to authenticated, service_role;

create or replace function "api"."running_timer"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."running_timer"($1) $$;
revoke execute on function "api"."running_timer"(uuid) from public, anon;
grant execute on function "api"."running_timer"(uuid) to authenticated, service_role;

create or replace function "api"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null, user_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."log_time"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) from public, anon;
grant execute on function "api"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) to authenticated, service_role;

create or replace function "api"."update_time_entry"(entry_id uuid, patch jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_time_entry"($1, $2) $$;
revoke execute on function "api"."update_time_entry"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_time_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_time_entry"(entry_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_time_entry"($1) $$;
revoke execute on function "api"."delete_time_entry"(uuid) from public, anon;
grant execute on function "api"."delete_time_entry"(uuid) to authenticated, service_role;

create or replace function "api"."list_time_entries"(tenant uuid, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_time_entries"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) from public, anon;
grant execute on function "api"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) to authenticated, service_role;

create or replace function "api"."get_timesheet"(tenant uuid, week date, user_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_timesheet"($1, $2, $3) $$;
revoke execute on function "api"."get_timesheet"(uuid, date, uuid) from public, anon;
grant execute on function "api"."get_timesheet"(uuid, date, uuid) to authenticated, service_role;

create or replace function "api"."submit_timesheet"(tenant uuid, week date, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_timesheet"($1, $2, $3) $$;
revoke execute on function "api"."submit_timesheet"(uuid, date, text) from public, anon;
grant execute on function "api"."submit_timesheet"(uuid, date, text) to authenticated, service_role;

create or replace function "api"."reopen_timesheet"(timesheet_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reopen_timesheet"($1) $$;
revoke execute on function "api"."reopen_timesheet"(uuid) from public, anon;
grant execute on function "api"."reopen_timesheet"(uuid) to authenticated, service_role;

create or replace function "api"."list_timesheets"(tenant uuid, user_id uuid default null, status text default null, page_size integer default 50, before date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_timesheets"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_timesheets"(uuid, uuid, text, integer, date) from public, anon;
grant execute on function "api"."list_timesheets"(uuid, uuid, text, integer, date) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module-data time-tracking
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

insert into better_supabase.modules (name, version, mode)
values ('time-tracking', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module time-tracking@1 adopt
-- Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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

-- The Monday of the week an instant falls in, in options.timeZone.
create or replace function "better_supabase"."time_week"(at timestamptz)
returns date
language sql
stable
set search_path = ''
as $$
  select (date_trunc('week', time_week.at at time zone 'UTC'))::date;
$$;
revoke execute on function "better_supabase"."time_week"(timestamptz) from public, anon;
grant execute on function "better_supabase"."time_week"(timestamptz) to authenticated, service_role;

-- A week is locked while its timesheet waits for approval and once it is approved.
create or replace function "better_supabase"."time_week_locked"(tenant uuid, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = time_week_locked.tenant and s."user_id" = time_week_locked.user_id
      and s."week" = "better_supabase"."time_week"(time_week_locked.at)
      and (s."approved_at" is not null or x."status" = 'pending')
  );
$$;
revoke execute on function "better_supabase"."time_week_locked"(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."time_entry_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and "better_supabase"."time_week_locked"(old."tenant_id", old."user_id", old."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op in ('INSERT', 'UPDATE') and "better_supabase"."time_week_locked"(new."tenant_id", new."user_id", new."started_at") then
    raise exception 'this week''s timesheet is submitted or approved' using errcode = '55000', hint = 'TIME_PERIOD_LOCKED';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."time_entry_guard"() from public, anon, authenticated;
drop trigger if exists bs_time_entry_guard on "better_supabase"."time_entries";
create trigger bs_time_entry_guard
  before insert or update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."time_entry_guard"();

-- Starts a timer for the caller, stopping the one that runs.
create or replace function "better_supabase"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    null;
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) from public, anon;
grant execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text) to authenticated, service_role;

create or replace function "better_supabase"."stop_timer"(tenant uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x
    where x."tenant_id" = stop_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    for update;
  if not found then
    raise exception 'no timer is running' using errcode = 'P0002', hint = 'TIME_NO_TIMER';
  end if;
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."stop_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."stop_timer"(uuid) to authenticated, service_role;

-- The caller's running timer, or null.
create or replace function "better_supabase"."running_timer"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timer.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "better_supabase"."running_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."running_timer"(uuid) to authenticated, service_role;

-- Records finished time. Logging for another member needs the manage permission.
create or replace function "better_supabase"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate numeric default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."note")
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) from public, anon;
grant execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid) to authenticated, service_role;

-- Changes the keys in patch: startedAt, endedAt, subjectType and subjectId
-- together, billable, rate and note.
create or replace function "better_supabase"."update_time_entry"(entry_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' then
    v_row."rate" := (v_patch ->> 'rate')::numeric;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_time_entry"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_time_entry"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = delete_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."user_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to delete this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "better_supabase"."time_entries" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_time_entry"(uuid) to authenticated, service_role;

-- A member's entries (the caller's by default), or every member's on a
-- record with everyone. Other members' entries need the read permission.
create or replace function "better_supabase"."list_time_entries"(tenant uuid, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(list_time_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((v_user = auth.uid() and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."time_entries" x
    where x."tenant_id" = list_time_entries.tenant
      and (list_time_entries.everyone or x."user_id" = v_user)
      and (list_time_entries.starts is null or coalesce(x."ended_at", 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x."started_at" < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x."subject_type" = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x."subject_id" = list_time_entries.subject_id)
    order by x."started_at" desc
    limit least(greatest(coalesce(list_time_entries.page_size, 200), 1), 1000)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer) to authenticated, service_role;

-- One member's week: the timesheet (status open when there is none yet),
-- the entries that start in it and their totals.
create or replace function "better_supabase"."get_timesheet"(tenant uuid, week date, user_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := coalesce(get_timesheet.user_id, auth.uid());
  v_week date := date_trunc('week', get_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_json jsonb;
  v_entries jsonb;
  v_totals jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read this timesheet' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = get_timesheet.tenant and s."user_id" = v_user and s."week" = v_week;
  if found then
    select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
    v_json := jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
  else
    v_json := jsonb_build_object('id', null, 'organizationId', get_timesheet.tenant, 'userId', v_user, 'week', v_week, 'status', 'open');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."started_at"), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")) filter (where x."billable"), 0)::bigint,
      'amount', round(coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at") / 3600 * x."rate") filter (where x."billable"), 0), 2)
    )
    into v_entries, v_totals
  from "better_supabase"."time_entries" x
  where x."tenant_id" = get_timesheet.tenant and x."user_id" = v_user
    and "better_supabase"."time_week"(x."started_at") = v_week;
  return v_json || jsonb_build_object('entries', v_entries, 'totals', v_totals);
end;
$$;
revoke execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) from public, anon;
grant execute on function "better_supabase"."get_timesheet"(uuid, date, uuid) to authenticated, service_role;

-- Sends the caller's week for approval. The week locks until a rejection.
create or replace function "better_supabase"."submit_timesheet"(tenant uuid, week date, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_week date := date_trunc('week', submit_timesheet.week)::date;
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
  v_seconds bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIMESHEET_SUBMITTED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_timesheet_submit"(uuid, uuid, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date)', v_hook::oid::regproc)
        using v_sheet."id", submit_timesheet.tenant, v_week;
    end if;
  end;
  select coalesce(sum(extract(epoch from x."ended_at" - x."started_at")), 0)::bigint into v_seconds
    from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me
      and "better_supabase"."time_week"(x."started_at") = v_week;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_tracking.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
    jsonb_build_object('userId', v_me, 'week', v_week, 'seconds', v_seconds)
  );
  update "better_supabase"."timesheets" s
  set "approval_id" = (v_request ->> 'id')::uuid, "note" = submit_timesheet.note, "submitted_at" = now()
  where s."id" = v_sheet."id"
  returning * into v_sheet;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_timesheet_submit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_sheet."id";
    end if;
  end;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."submit_timesheet"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."submit_timesheet"(uuid, date, text) to authenticated, service_role;

-- Locks the week once the approval is final. Approvals calls it; it isn't
-- granted to anyone.
create or replace function "better_supabase"."approve_timesheet"(timesheet_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
begin
  update "better_supabase"."timesheets" s set "approved_at" = now()
    where s."id" = approve_timesheet.timesheet_id and s."approved_at" is null
    returning * into v_sheet;
  if found then
    null;
  end if;
end;
$$;
revoke execute on function "better_supabase"."approve_timesheet"(uuid) from public, anon, authenticated;

-- Unlocks an approved week so its entries can change and it can be sent again.
create or replace function "better_supabase"."reopen_timesheet"(timesheet_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sheet "better_supabase"."timesheets"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sheet from "better_supabase"."timesheets" s where s."id" = reopen_timesheet.timesheet_id for update;
  if not found then
    raise exception 'timesheet not found' using errcode = 'P0002', hint = 'TIMESHEET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sheet."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to reopen timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_sheet."approved_at" is null then
    raise exception 'only an approved week can be reopened' using errcode = '55000', hint = 'TIMESHEET_NOT_APPROVED';
  end if;
  update "better_supabase"."timesheets" s set "approved_at" = null, "approval_id" = null, "submitted_at" = null
    where s."id" = v_sheet."id"
    returning * into v_sheet;
  null;
  return jsonb_build_object('id', v_sheet."id", 'organizationId', v_sheet."tenant_id", 'userId', v_sheet."user_id", 'week', v_sheet."week", 'status', case when v_sheet."approved_at" is not null then 'approved' when v_approval."status" = 'pending' then 'submitted' when v_approval."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', v_sheet."approval_id", 'note', v_sheet."note", 'submittedAt', v_sheet."submitted_at", 'approvedAt', v_sheet."approved_at", 'createdAt', v_sheet."created_at");
end;
$$;
revoke execute on function "better_supabase"."reopen_timesheet"(uuid) from public, anon;
grant execute on function "better_supabase"."reopen_timesheet"(uuid) to authenticated, service_role;

-- Newest week first: the caller's timesheets, or everyone's with the read permission.
create or replace function "better_supabase"."list_timesheets"(tenant uuid, user_id uuid default null, status text default null, page_size integer default 50, before date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_tracking.track'), false)) then
    raise exception 'not allowed to list timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id <> auth.uid() then
    raise exception 'not allowed to read another member''s timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(q.item order by q.week desc, q.created desc), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', s."id", 'organizationId', s."tenant_id", 'userId', s."user_id", 'week', s."week", 'status', case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end, 'approvalId', s."approval_id", 'note', s."note", 'submittedAt', s."submitted_at", 'approvedAt', s."approved_at", 'createdAt', s."created_at") as item, s."week" as week, s."created_at" as created
    from "better_supabase"."timesheets" s
    left join "better_supabase"."approval_requests" x on x."id" = s."approval_id"
    where s."tenant_id" = list_timesheets.tenant
      and (case when v_reader then list_timesheets.user_id is null or s."user_id" = list_timesheets.user_id else s."user_id" = auth.uid() end)
      and (list_timesheets.status is null or case when s."approved_at" is not null then 'approved' when x."status" = 'pending' then 'submitted' when x."status" = 'rejected' then 'rejected' else 'open' end = list_timesheets.status)
      and (list_timesheets.before is null or s."week" < list_timesheets.before)
    order by s."week" desc, s."created_at" desc
    limit least(greatest(coalesce(list_timesheets.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) from public, anon;
grant execute on function "better_supabase"."list_timesheets"(uuid, uuid, text, integer, date) to authenticated, service_role;

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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_88_time_tracking.sql
-- better-supabase module: time-tracking
-- @bs-module-data time-tracking
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('time-tracking', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
