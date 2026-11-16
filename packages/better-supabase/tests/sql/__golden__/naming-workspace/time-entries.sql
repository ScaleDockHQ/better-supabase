-- ==== schema supabase/schemas/900_better_supabase_088_time_entries.sql
-- better-supabase module: time-entries
-- @bsb-block time-entries@4 managed
-- @bsb-hash sha256:08b6774f93f26017ea9e0ffba0e1712059cc8c2d91e56fb72a16022828e5a8cb
-- Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists btree_gist with schema extensions;

create table "better_supabase"."time_entries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "subject_type" text,
  "subject_id" text,
  "started_at" timestamptz not null,
  "ended_at" timestamptz,
  "billable" boolean not null default false,
  -- Minor units of rate_currency per hour (ADR 0037).
  "rate" bigint constraint bsb_time_entries_rate_check check ("rate" is null or "rate" >= 0),
  "rate_currency" text,
  "note" text constraint bsb_time_entries_note_check check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  -- Set while the entry is archived: it leaves totals, reports and the overlap check.
  "archived_at" timestamptz,
  -- What metrics sum: the length of a finished entry, null while it runs.
  "seconds" bigint generated always as (extract(epoch from "ended_at" - "started_at")::bigint) stored,
  constraint bsb_time_entries_check check ("ended_at" is null or "ended_at" > "started_at"),
  constraint bsb_time_entries_check1 check (("subject_type" is null) = ("subject_id" is null)),
  -- A running entry reaches to infinity, so this also allows one running timer per user.
  constraint "time_entries_no_overlap_excl" exclude using gist (
    "tenant_id" with =,
    "user_id" with =,
    tstzrange("started_at", coalesce("ended_at", 'infinity'::timestamptz)) with &&
  ) where ("archived_at" is null)
);
alter table "better_supabase"."time_entries" add constraint bsb_time_entries_rate_currency_check
  check ("rate_currency" is null or "rate_currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."time_entries" add constraint bsb_time_entries_rate_needs_currency_check
  check ("rate" is null or "rate_currency" is not null);
create unique index "time_entries_running_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id") where "ended_at" is null;
create index "time_entries_user_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id", "started_at" desc);
create index "time_entries_subject_idx" on "better_supabase"."time_entries" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."time_entries" enable row level security;
revoke all on "better_supabase"."time_entries" from public, anon, authenticated;
grant select on "better_supabase"."time_entries" to authenticated;
grant all on "better_supabase"."time_entries" to service_role;
create policy bsb_time_entries_read on "better_supabase"."time_entries"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_entries.read')));

create table "better_supabase"."timesheets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "week" date not null constraint bsb_timesheets_week_check check (extract(isodow from "week") = 1),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "note" text constraint bsb_timesheets_note_check check ("note" is null or length("note") <= 2000),
  "submitted_at" timestamptz,
  "approved_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "user_id", "week")
);
create index "timesheets_approval_idx" on "better_supabase"."timesheets" ("approval_id") where "approval_id" is not null;
create index "timesheets_week_idx" on "better_supabase"."timesheets" ("tenant_id", "week" desc);
alter table "better_supabase"."timesheets" enable row level security;
revoke all on "better_supabase"."timesheets" from public, anon, authenticated;
grant select on "better_supabase"."timesheets" to authenticated;
grant all on "better_supabase"."timesheets" to service_role;
create policy bsb_timesheets_read on "better_supabase"."timesheets"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_entries.read')));

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

-- Whether the week an instant falls in has an approved timesheet. Payroll runs
-- read only the entries of approved weeks.
create or replace function "better_supabase"."time_week_approved"(tenant uuid, user_id uuid, at timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from "better_supabase"."timesheets" s
    where s."tenant_id" = time_week_approved.tenant and s."user_id" = time_week_approved.user_id
      and s."week" = "better_supabase"."time_week"(time_week_approved.at)
      and s."approved_at" is not null
  );
$$;
revoke execute on function "better_supabase"."time_week_approved"(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function "better_supabase"."time_entry_guard"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Only a change to logged time (options.lockedColumns) touches the week.
  if tg_op = 'UPDATE' and (new."started_at", new."ended_at", new."subject_type", new."subject_id", new."user_id", new."rate", new."rate_currency", new."archived_at") is not distinct from (old."started_at", old."ended_at", old."subject_type", old."subject_id", old."user_id", old."rate", old."rate_currency", old."archived_at") then
    return new;
  end if;
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
create trigger bsb_time_entry_guard
  before insert or update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."time_entry_guard"();

-- Starts a timer for the caller, stopping the one that runs. fields: the
-- extra columns (columns your schema files add) to set.

create or replace function "better_supabase"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate bigint default null, rate_currency text default null, note text default null)
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
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_entries.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or true) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if start_timer.rate is not null and start_timer.rate_currency is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if start_timer.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
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
  v_row."rate_currency" := start_timer.rate_currency;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
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
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, bigint, text, text) from public, anon;
grant execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, bigint, text, text) to authenticated, service_role;
create or replace function "better_supabase"."stop_timer"(tenant uuid, entry uuid default null)
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
      and (stop_timer.entry is null or x."id" = stop_timer.entry)
    order by x."started_at" desc
    limit 1
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."stop_timer"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."stop_timer"(uuid, uuid) to authenticated, service_role;

-- The caller's running timer, or null.
create or replace function "better_supabase"."running_timer"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timer.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "better_supabase"."running_timer"(uuid) from public, anon;
grant execute on function "better_supabase"."running_timer"(uuid) to authenticated, service_role;

-- Every timer the caller has running, newest first.
create or replace function "better_supabase"."running_timers"(tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."started_at" desc), '[]'::jsonb) from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timers.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "better_supabase"."running_timers"(uuid) from public, anon;
grant execute on function "better_supabase"."running_timers"(uuid) to authenticated, service_role;

-- Records finished time. Logging for another member needs the manage permission.

create or replace function "better_supabase"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate bigint default null, rate_currency text default null, note text default null, user_id uuid default null)
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
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_entries.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_entries.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "better_supabase"."memberships" m where m."workspace_id" = log_time.tenant and m."user_id" = v_user) then
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
  if log_time.rate is not null and log_time.rate_currency is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if log_time.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
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
  v_row."rate_currency" := log_time.rate_currency;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
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
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid) to authenticated, service_role;

-- Changes the keys in patch: startedAt, endedAt, subjectType and subjectId
-- together, billable, rate and rateCurrency together (minor units per
-- hour as text), note and fields (the extra columns).
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
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
  if v_patch ? 'rate' or v_patch ? 'rateCurrency' then
    v_row."rate" := (v_patch ->> 'rate')::bigint;
    v_row."rate_currency" := v_patch ->> 'rateCurrency';
    if v_row."rate" is not null and v_row."rate_currency" is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if v_row."rate_currency" !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
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
      "rate_currency" = v_row."rate_currency",
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."update_time_entry"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_time_entry"(uuid, jsonb) to authenticated, service_role;


-- Archives a finished entry: it leaves totals, reports, invoices and payroll. A locked week, a running timer and an invoiced entry refuse it.
create or replace function "better_supabase"."archive_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = archive_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_row."archived_at" is not null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  if v_row."ended_at" is null then
    raise exception 'stop the running timer before archiving it' using errcode = '55000', hint = 'TIME_TIMER_RUNNING';
  end if;
  update "better_supabase"."time_entries" x set
    "archived_at" = now(),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."archive_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_time_entry"(uuid) to authenticated, service_role;

-- Brings an archived entry back. A locked week and an overlapping entry refuse it.
create or replace function "better_supabase"."restore_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = restore_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_row."archived_at" is null then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and x."archived_at" is null
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  update "better_supabase"."time_entries" x set
    "archived_at" = null,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."restore_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."restore_time_entry"(uuid) to authenticated, service_role;

-- Removes an entry for good. Needs permissions.purge, which falls back to the
-- entry's owner (with track) and manage. A locked week and an invoiced entry
-- refuse it.
create or replace function "better_supabase"."purge_time_entry"(entry_id uuid)
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
  select * into v_row from "better_supabase"."time_entries" x where x."id" = purge_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to purge this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "better_supabase"."time_entries" x where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."purge_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_time_entry"(uuid) to authenticated, service_role;

-- A member's entries (the caller's by default), or every member's on a
-- record with everyone. Other members' entries need the read permission.

-- archived: false hides archived entries, true lists only them.
create or replace function "better_supabase"."list_time_entries"(tenant uuid, user_id uuid default null, starts timestamptz default null, ends timestamptz default null, subject_type text default null, subject_id text default null, everyone boolean default false, page_size integer default 200, archived boolean default false)
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(v_user = auth.uid(), false) and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_entries.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate"::text, 'rateCurrency', q."rate_currency", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at", 'archivedAt', q."archived_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."time_entries" x
    where x."tenant_id" = list_time_entries.tenant
      and (list_time_entries.everyone or x."user_id" = v_user)
      and (list_time_entries.starts is null or coalesce(x."ended_at", 'infinity'::timestamptz) > list_time_entries.starts)
      and (list_time_entries.ends is null or x."started_at" < list_time_entries.ends)
      and (list_time_entries.subject_type is null or x."subject_type" = list_time_entries.subject_type)
      and (list_time_entries.subject_id is null or x."subject_id" = list_time_entries.subject_id)
      and ((x."archived_at" is not null) = coalesce(list_time_entries.archived, false))
    order by x."started_at" desc
    limit least(greatest(coalesce(list_time_entries.page_size, 200), 1), 1000)
  ) q;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer, boolean) from public, anon;
grant execute on function "better_supabase"."list_time_entries"(uuid, uuid, timestamptz, timestamptz, text, text, boolean, integer, boolean) to authenticated, service_role;

-- A member's entries (the caller's by default) as a keyset page, newest first
-- (ADR 1077). filters is { subjectType, subjectId, billable (each a value or a
-- list), userId, from, to (the first value counts), everyone (true for all
-- members), archived (true lists only archived entries), search (note), sort
-- (startedAt, endedAt, seconds, createdAt), direction, facet, count, limit,
-- after, offset, paged, total, totalCap }.
create or replace function "better_supabase"."page_time_entries"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_time_entries.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_everyone boolean := coalesce(nullif(coalesce(v_filters #>> '{everyone,0}', v_filters ->> 'everyone'), '') = 'true', false);
  v_user uuid := coalesce(nullif(nullif(coalesce(v_filters #>> '{userId,0}', v_filters ->> 'userId'), ''), '')::uuid, auth.uid());
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(v_user = auth.uid(), false) and not v_everyone) and coalesce(better_supabase.can('tenant', page_time_entries.tenant, 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', page_time_entries.tenant, 'time_entries.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'billable') then
      raise exception 'facet is one of subjectType, billable' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'billable' then (x."billable"::text)::text end) as v
      from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startedAt', 'endedAt', 'seconds', 'createdAt') then
    raise exception 'sort is one of startedAt, endedAt, seconds, createdAt' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at" >= (v_after ->> 0)::timestamptz and ((x."started_at" > (v_after ->> 0)::timestamptz) or (x."started_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."started_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."started_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at" >= (v_after ->> 0)::timestamptz and ((x."started_at" > (v_after ->> 0)::timestamptz) or (x."started_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."started_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."started_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(x."ended_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(x."ended_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."ended_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."ended_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."ended_at", 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(x."ended_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(x."ended_at", 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."ended_at", 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'seconds' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) >= (v_after ->> 0)::bigint and ((coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) > (v_after ->> 0)::bigint) or (coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) = (v_after ->> 0)::bigint and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'seconds' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0), x."id") < ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."page_time_entries"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_time_entries"(uuid, jsonb) to authenticated, service_role;

-- One entry the caller may read, or null.
create or replace function "better_supabase"."get_time_entry"(entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."time_entries" x where x."id" = get_time_entry.entry_id;
  if not found then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.read'), false)) then
    raise exception 'not allowed to read this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$$;
revoke execute on function "better_supabase"."get_time_entry"(uuid) from public, anon;
grant execute on function "better_supabase"."get_time_entry"(uuid) to authenticated, service_role;


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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_entries.read'), false)) then
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
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") order by x."started_at"), '[]'::jsonb),
    jsonb_build_object(
      'seconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")), 0)::bigint,
      'billableSeconds', coalesce(sum(extract(epoch from coalesce(x."ended_at", now()) - x."started_at")) filter (where x."billable"), 0)::bigint,
      -- Billable hours times the rate, per currency, rounded to minor units.
      'amounts', (
        select coalesce(jsonb_agg(jsonb_build_object('amount', q.amount::text, 'currency', q.currency) order by q.currency), '[]'::jsonb)
        from (
          select y."rate_currency" as currency,
            round(sum(extract(epoch from coalesce(y."ended_at", now()) - y."started_at") * y."rate" / 3600))::bigint as amount
          from "better_supabase"."time_entries" y
          where y."tenant_id" = get_timesheet.tenant and y."user_id" = v_user
            and "better_supabase"."time_week"(y."started_at") = v_week
            and y."billable" and y."rate" is not null and y."archived_at" is null
          group by y."rate_currency"
        ) q
      )
    )
    into v_entries, v_totals
  from "better_supabase"."time_entries" x
  where x."tenant_id" = get_timesheet.tenant and x."user_id" = v_user
    and "better_supabase"."time_week"(x."started_at") = v_week and x."archived_at" is null;
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
  if v_me is null or not coalesce(better_supabase.can('tenant', submit_timesheet.tenant, 'time_entries.track'), false) then
    raise exception 'not allowed to submit a timesheet here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || submit_timesheet.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = submit_timesheet.tenant and x."user_id" = v_me and x."ended_at" is null
      and "better_supabase"."time_week"(x."started_at") = v_week
  ) then
    raise exception 'stop the running timer before submitting this week' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_TIMER_RUNNING';
  end if;
  insert into "better_supabase"."timesheets" ("tenant_id", "user_id", "week")
  values (submit_timesheet.tenant, v_me, v_week)
  on conflict ("tenant_id", "user_id", "week") do nothing;
  select * into v_sheet from "better_supabase"."timesheets" s
    where s."tenant_id" = submit_timesheet.tenant and s."user_id" = v_me and s."week" = v_week
    for update;
  if v_sheet."approved_at" is not null then
    raise exception 'this week is already approved' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_APPROVED';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_sheet."approval_id";
  if v_approval."status" = 'pending' then
    raise exception 'this week is already waiting for approval' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_SUBMITTED';
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
      and "better_supabase"."time_week"(x."started_at") = v_week and x."archived_at" is null;
  v_request := "better_supabase"."open_approval"(
    submit_timesheet.tenant, 'timesheet', v_sheet."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"time_entries.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, submit_timesheet.note,
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
    raise exception 'timesheet not found' using errcode = 'P0002', hint = 'TIME_ENTRIES_TIMESHEET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_sheet."tenant_id", 'time_entries.manage'), false)) then
    raise exception 'not allowed to reopen timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_sheet."approved_at" is null then
    raise exception 'only an approved week can be reopened' using errcode = '55000', hint = 'TIME_ENTRIES_TIMESHEET_NOT_APPROVED';
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
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_entries.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_timesheets.tenant, 'time_entries.track'), false)) then
    raise exception 'not allowed to list timesheets' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if not v_reader and list_timesheets.user_id is not null and list_timesheets.user_id is distinct from auth.uid() then
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."time_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_entries.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."time_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."time_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."time_entries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."timesheets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_entries.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."timesheets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."timesheets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."timesheets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_088_time_entries.sql
-- better-supabase module: time-entries
-- @bsb-block-data time-entries
-- @bsb-hash sha256:f85ff49e3b22289036c5d7c2dc2d3e6a0e5277a0eb522b1451ced706e9f0828e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "btree_gist" with schema "extensions";

delete from better_supabase.blocks
  where name = 'time-tracking'
    and exists (select 1 from better_supabase.blocks where name = 'time-entries');
update better_supabase.blocks set name = 'time-entries'
  where name = 'time-tracking'
    and not exists (select 1 from better_supabase.blocks where name = 'time-entries');
insert into better_supabase.blocks (name, version, mode)
values ('time-entries', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
