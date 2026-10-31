-- better-supabase module: time-tracking
-- @bsb-block time-tracking@3 managed
-- @bsb-hash sha256:e5873b0d8075276a8c12a878601e9ebd5b42151685e58876aea865c90784491b
-- Time entries with one running timer per member and no overlaps, on any record, billable with a rate. Weekly timesheets go through approvals, and a submitted or approved week is locked.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."time_entries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_entries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_entries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_entries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_entries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."timesheets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."timesheets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."timesheets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."timesheets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."timesheets";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
  -- Minor units of rate_currency per hour (ADR 0037).
  "rate" bigint check ("rate" is null or "rate" >= 0),
  "rate_currency" text,
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
alter table "better_supabase"."time_entries" add column if not exists "rate_currency" text;
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."time_entries"'::regclass and conname = 'time_entries_rate_currency_check'
  ) then
    alter table "better_supabase"."time_entries" add constraint "time_entries_rate_currency_check"
      check ("rate_currency" is null or "rate_currency" ~ '^[A-Z]{3}$') not valid;
    begin
      alter table "better_supabase"."time_entries" validate constraint "time_entries_rate_currency_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."time_entries"', 'time_entries_rate_currency_check', '"better_supabase"."time_entries"', 'time_entries_rate_currency_check';
    end;
  end if;
end;
$$;
alter table "better_supabase"."time_entries" drop constraint if exists "time_entries_rate_pair_check";
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"better_supabase"."time_entries"'::regclass and conname = 'time_entries_rate_needs_currency_check'
  ) then
    alter table "better_supabase"."time_entries" add constraint "time_entries_rate_needs_currency_check"
      check ("rate" is null or "rate_currency" is not null) not valid;
    begin
      alter table "better_supabase"."time_entries" validate constraint "time_entries_rate_needs_currency_check";
    exception when check_violation then
      raise warning '% has rows that fail %, so only new rows are checked. Fix them, then run: alter table % validate constraint %',
        '"better_supabase"."time_entries"', 'time_entries_rate_needs_currency_check', '"better_supabase"."time_entries"', 'time_entries_rate_needs_currency_check';
    end;
  end if;
end;
$$;
create unique index if not exists "time_entries_running_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id") where "ended_at" is null;
create index if not exists "time_entries_user_idx" on "better_supabase"."time_entries" ("tenant_id", "user_id", "started_at" desc);
create index if not exists "time_entries_subject_idx" on "better_supabase"."time_entries" ("tenant_id", "subject_type", "subject_id") where "subject_type" is not null;
alter table "better_supabase"."time_entries" enable row level security;
revoke all on "better_supabase"."time_entries" from public, anon, authenticated;
grant select on "better_supabase"."time_entries" to authenticated;
grant all on "better_supabase"."time_entries" to service_role;
drop policy if exists time_entries_read on "better_supabase"."time_entries";
create policy time_entries_read on "better_supabase"."time_entries"
  for select to authenticated
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
revoke all on "better_supabase"."timesheets" from public, anon, authenticated;
grant select on "better_supabase"."timesheets" to authenticated;
grant all on "better_supabase"."timesheets" to service_role;
drop policy if exists timesheets_read on "better_supabase"."timesheets";
create policy timesheets_read on "better_supabase"."timesheets"
  for select to authenticated
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
  -- Only a change to logged time (options.lockedColumns) touches the week.
  if tg_op = 'UPDATE' and (new."started_at", new."ended_at", new."subject_type", new."subject_id", new."user_id", new."rate", new."rate_currency") is not distinct from (old."started_at", old."ended_at", old."subject_type", old."subject_id", old."user_id", old."rate", old."rate_currency") then
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
drop trigger if exists bsb_time_entry_guard on "better_supabase"."time_entries";
create trigger bsb_time_entry_guard
  before insert or update or delete on "better_supabase"."time_entries"
  for each row execute function "better_supabase"."time_entry_guard"();

-- Starts a timer for the caller, stopping the one that runs. fields: the
-- extra columns (blocks.time-tracking.options.extraColumns) to set.
drop function if exists "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text);
drop function if exists "better_supabase"."start_timer"(uuid, text, text, boolean, numeric, text, jsonb);
drop function if exists "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid);
drop function if exists "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid, jsonb);
drop function if exists "better_supabase"."start_timer"(uuid, text, text, boolean, bigint, text, text, jsonb);
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
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case start_timer.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'forms.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant and (coalesce(better_supabase.can('tenant', start_timer.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    else false
  end) then
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
    perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
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
  perform "better_supabase".emit_event('time_entry.started', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, bigint, text, text) from public, anon;
grant execute on function "better_supabase"."start_timer"(uuid, text, text, boolean, bigint, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."stop_timer"(uuid);
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
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."time_entries" x
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
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."started_at" desc), '[]'::jsonb) from "better_supabase"."time_entries" x
  where x."tenant_id" = running_timers.tenant and x."user_id" = auth.uid() and x."ended_at" is null;
$$;
revoke execute on function "better_supabase"."running_timers"(uuid) from public, anon;
grant execute on function "better_supabase"."running_timers"(uuid) to authenticated, service_role;

-- Records finished time. Logging for another member needs the manage permission.
drop function if exists "better_supabase"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid, jsonb);
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
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "public"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case log_time.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'forms.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant and (coalesce(better_supabase.can('tenant', log_time.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    else false
  end) then
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
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
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
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case v_row."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id" and (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    else false
  end) then
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
  perform "better_supabase".emit_event('time_entry.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'previousStartedAt', v_previous_started_at), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to delete this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  delete from "better_supabase"."time_entries" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('time_entry.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(v_user = auth.uid(), false) and not list_time_entries.everyone) and coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', list_time_entries.tenant, 'time_tracking.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'userId', q."user_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'startedAt', q."started_at", 'endedAt', q."ended_at", 'seconds', case when q."ended_at" is null then null else extract(epoch from q."ended_at" - q."started_at")::bigint end, 'billable', q."billable", 'rate', q."rate"::text, 'rateCurrency', q."rate_currency", 'note', q."note", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."started_at" desc), '[]'::jsonb) into v_rows
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', get_timesheet.tenant, 'time_tracking.read'), false)) then
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
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."started_at"), '[]'::jsonb),
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
            and y."billable" and y."rate" is not null
          group by y."rate_currency"
        ) q
      )
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
drop function if exists "better_supabase"."approve_timesheet"(uuid, uuid);
drop function if exists "better_supabase"."reject_timesheet"(uuid, text, uuid);
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
drop policy if exists bsb_tenant_scope on "better_supabase"."time_entries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."time_entries";
create policy bsb_tenant_scope_select on "better_supabase"."time_entries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."time_entries";
create policy bsb_tenant_scope_insert on "better_supabase"."time_entries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."time_entries";
create policy bsb_tenant_scope_update on "better_supabase"."time_entries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."time_entries";
create policy bsb_tenant_scope_delete on "better_supabase"."time_entries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."timesheets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."timesheets";
create policy bsb_tenant_scope_select on "better_supabase"."timesheets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('time_tracking.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."timesheets";
create policy bsb_tenant_scope_insert on "better_supabase"."timesheets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."timesheets";
create policy bsb_tenant_scope_update on "better_supabase"."timesheets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."timesheets";
create policy bsb_tenant_scope_delete on "better_supabase"."timesheets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.time-tracking.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."start_timer"(uuid, text, text, boolean, numeric, text);
drop function if exists "api"."start_timer"(uuid, text, text, boolean, numeric, text, jsonb);
drop function if exists "api"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid);
drop function if exists "api"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, numeric, text, uuid, jsonb);
drop function if exists "api"."start_timer"(uuid, text, text, boolean, bigint, text, text, jsonb);
drop function if exists "api"."stop_timer"(uuid);
drop function if exists "api"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid, jsonb);

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

create or replace function "api"."start_timer"(tenant uuid, subject_type text default null, subject_id text default null, billable boolean default false, rate bigint default null, rate_currency text default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_timer"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."start_timer"(uuid, text, text, boolean, bigint, text, text) from public, anon;
grant execute on function "api"."start_timer"(uuid, text, text, boolean, bigint, text, text) to authenticated, service_role;

create or replace function "api"."stop_timer"(tenant uuid, entry uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."stop_timer"($1, $2) $$;
revoke execute on function "api"."stop_timer"(uuid, uuid) from public, anon;
grant execute on function "api"."stop_timer"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."running_timer"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."running_timer"($1) $$;
revoke execute on function "api"."running_timer"(uuid) from public, anon;
grant execute on function "api"."running_timer"(uuid) to authenticated, service_role;

create or replace function "api"."running_timers"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."running_timers"($1) $$;
revoke execute on function "api"."running_timers"(uuid) from public, anon;
grant execute on function "api"."running_timers"(uuid) to authenticated, service_role;

create or replace function "api"."log_time"(tenant uuid, started_at timestamptz, ended_at timestamptz, subject_type text default null, subject_id text default null, billable boolean default false, rate bigint default null, rate_currency text default null, note text default null, user_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."log_time"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid) from public, anon;
grant execute on function "api"."log_time"(uuid, timestamptz, timestamptz, text, text, boolean, bigint, text, text, uuid) to authenticated, service_role;

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
