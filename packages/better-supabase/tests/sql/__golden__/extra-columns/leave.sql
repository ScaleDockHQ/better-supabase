-- ==== schema supabase/schemas/900_better_supabase_109_leave.sql
-- better-supabase module: leave
-- @bs-module leave@1 managed
-- Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."leave_types" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 100),
  "unit" text not null default 'days' check ("unit" in ('days', 'hours')),
  "paid" boolean not null default true,
  -- Untracked types (unpaid leave, say) book no ledger entries and skip the balance check.
  "tracked" boolean not null default true,
  -- What accrue_leave grants each member per period when it names no amount.
  "allowance" numeric(8, 2) check ("allowance" is null or "allowance" >= 0),
  -- How much close_leave_year carries into the next period; null carries everything.
  "carryover_max" numeric(8, 2) check ("carryover_max" is null or "carryover_max" >= 0),
  "color" text check ("color" is null or "color" ~ '^#[0-9a-fA-F]{6}$'),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id")
);
alter table "better_supabase"."leave_types" enable row level security;
revoke all on "better_supabase"."leave_types" from anon, authenticated;
grant select on "better_supabase"."leave_types" to authenticated;
grant all on "better_supabase"."leave_types" to service_role;
drop policy if exists "leave_types_read" on "better_supabase"."leave_types";
create policy "leave_types_read" on "better_supabase"."leave_types" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));

create table if not exists "better_supabase"."leave_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "type_id" uuid not null,
  "starts_on" date not null,
  "ends_on" date not null,
  "partial" text not null default 'full' check ("partial" in ('full', 'morning', 'afternoon', 'hours')),
  -- Working days, or hours for an hours type, that the request books.
  "amount" numeric(8, 2) not null check ("amount" > 0),
  "note" text check ("note" is null or length("note") <= 2000),
  "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null,
  "approved_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancelled_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" >= "starts_on"),
  foreign key ("tenant_id", "type_id") references "better_supabase"."leave_types" ("tenant_id", "id") on delete restrict
);
alter table "better_supabase"."leave_requests" add column if not exists "app_note" text;
create index if not exists "leave_requests_user_idx" on "better_supabase"."leave_requests" ("tenant_id", "user_id", "starts_on" desc);
create index if not exists "leave_requests_dates_idx" on "better_supabase"."leave_requests" ("tenant_id", "starts_on", "ends_on");
create index if not exists "leave_requests_approval_idx" on "better_supabase"."leave_requests" ("approval_id") where "approval_id" is not null;
alter table "better_supabase"."leave_requests" enable row level security;
revoke all on "better_supabase"."leave_requests" from anon, authenticated;
grant select on "better_supabase"."leave_requests" to authenticated;
grant all on "better_supabase"."leave_requests" to service_role;
drop policy if exists "leave_requests_read" on "better_supabase"."leave_requests";
create policy "leave_requests_read" on "better_supabase"."leave_requests" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));

create table if not exists "better_supabase"."leave_ledger" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "type_id" uuid not null,
  "kind" text not null check ("kind" in ('grant', 'accrual', 'taken', 'adjustment', 'carryover', 'expiry')),
  -- Signed: grants add, taken leave subtracts, a cancelled request adds back.
  "amount" numeric(8, 2) not null check ("amount" <> 0),
  -- The year the entry counts toward.
  "period" integer not null check ("period" between 1900 and 9999),
  "request_id" uuid references "better_supabase"."leave_requests" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "idempotency_key" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  foreign key ("tenant_id", "type_id") references "better_supabase"."leave_types" ("tenant_id", "id") on delete restrict
);
create index if not exists "leave_ledger_balance_idx" on "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "period");
create unique index if not exists "leave_ledger_key_idx" on "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "idempotency_key") where "idempotency_key" is not null;
alter table "better_supabase"."leave_ledger" enable row level security;
revoke all on "better_supabase"."leave_ledger" from anon, authenticated;
grant select on "better_supabase"."leave_ledger" to authenticated;
grant all on "better_supabase"."leave_ledger" to service_role;
drop policy if exists "leave_ledger_read" on "better_supabase"."leave_ledger";
create policy "leave_ledger_read" on "better_supabase"."leave_ledger" for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));

-- The working days (options.workingDays) from one date to another, inclusive.
create or replace function "better_supabase"."leave_working_days"(starts_on date, ends_on date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer
  from generate_series(leave_working_days.starts_on, leave_working_days.ends_on, interval '1 day') d
  where extract(isodow from d)::integer = any (array[1, 2, 3, 4, 5])
$$;
revoke execute on function "better_supabase"."leave_working_days"(date, date) from public, anon;
grant execute on function "better_supabase"."leave_working_days"(date, date) to authenticated, service_role;

-- A member's balance of one type for one period: every ledger entry, minus
-- the requests still waiting for approval.
create or replace function "better_supabase"."leave_available"(tenant uuid, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select sum(x."amount") from "better_supabase"."leave_ledger" x
      where x."tenant_id" = leave_available.tenant and x."user_id" = leave_available.user_id
        and x."type_id" = leave_available.type_id and x."period" = leave_available.period), 0)
    - coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_available.tenant and r."user_id" = leave_available.user_id
        and r."type_id" = leave_available.type_id and extract(year from r."starts_on")::integer = leave_available.period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0)
$$;
revoke execute on function "better_supabase"."leave_available"(uuid, uuid, uuid, integer) from public, anon, authenticated;

-- Creates or updates a leave type by key.
create or replace function "better_supabase"."save_leave_type"(tenant uuid, key text, name text, unit text default 'days', paid boolean default true, tracked boolean default true, allowance numeric default null, carryover_max numeric default null, color text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leave_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_leave_type.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to manage leave types' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  insert into "better_supabase"."leave_types" ("tenant_id", "key", "name", "unit", "paid", "tracked", "allowance", "carryover_max", "color")
  values (save_leave_type.tenant, save_leave_type.key, save_leave_type.name, coalesce(save_leave_type.unit, 'days'), coalesce(save_leave_type.paid, true), coalesce(save_leave_type.tracked, true), save_leave_type.allowance, save_leave_type.carryover_max, save_leave_type.color)
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "unit" = excluded."unit", "paid" = excluded."paid",
      "tracked" = excluded."tracked", "allowance" = excluded."allowance",
      "carryover_max" = excluded."carryover_max", "color" = excluded."color",
      "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'paid', v_row."paid", 'tracked', v_row."tracked", 'allowance', v_row."allowance"::text, 'carryoverMax', v_row."carryover_max"::text, 'color', v_row."color", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_leave_type"(uuid, text, text, text, boolean, boolean, numeric, numeric, text) from public, anon;
grant execute on function "better_supabase"."save_leave_type"(uuid, text, text, text, boolean, boolean, numeric, numeric, text) to authenticated, service_role;

-- Hides a type from new requests; its requests and ledger stay.
create or replace function "better_supabase"."archive_leave_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leave_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_types" x where x."id" = archive_leave_type.type_id for update;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then
    raise exception 'not allowed to manage leave types' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "better_supabase"."leave_types" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'paid', v_row."paid", 'tracked', v_row."tracked", 'allowance', v_row."allowance"::text, 'carryoverMax', v_row."carryover_max"::text, 'color', v_row."color", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_leave_type"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_leave_type"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_leave_types"(tenant uuid, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'paid', x."paid", 'tracked', x."tracked", 'allowance', x."allowance"::text, 'carryoverMax', x."carryover_max"::text, 'color', x."color", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."leave_types" x
  where x."tenant_id" = list_leave_types.tenant
    and (coalesce(list_leave_types.archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_leave_types"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_leave_types"(uuid, boolean) to authenticated, service_role;

-- Asks for leave and opens its approval. A day type books working days
-- (half a day for a morning or afternoon); an hours type books hours.
-- Without options.allowNegative the request can't exceed the balance of
-- the period it starts in. fields: the extra columns to set.
drop function if exists "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text);
create or replace function "better_supabase"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_type "better_supabase"."leave_types"%rowtype;
  v_partial text := coalesce(request_leave.partial, 'full');
  v_amount numeric;
  v_row "better_supabase"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', request_leave.tenant, 'leave.request'), false) then
    raise exception 'not allowed to request leave here' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."leave_types" x
    where x."id" = request_leave.type_id and x."tenant_id" = request_leave.tenant and x."archived_at" is null;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  if request_leave.starts_on is null or request_leave.ends_on is null or request_leave.ends_on < request_leave.starts_on then
    raise exception 'ends_on must be on or after starts_on' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    raise exception 'partial must be full, morning, afternoon or hours' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_type."unit" = 'hours' then
    if v_partial <> 'hours' and v_partial <> 'full' then
      raise exception 'an hours type takes partial hours' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if request_leave.hours is null or request_leave.hours <= 0 then
      raise exception 'an hours type needs hours greater than zero' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_partial := 'hours';
    v_amount := request_leave.hours;
  else
    if v_partial = 'hours' then
      raise exception 'a day type takes partial full, morning or afternoon' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if v_partial in ('morning', 'afternoon') and request_leave.starts_on <> request_leave.ends_on then
      raise exception 'a half day starts and ends on the same date' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_amount := "better_supabase"."leave_working_days"(request_leave.starts_on, request_leave.ends_on)
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  if v_amount <= 0 then
    raise exception 'the request covers no working days' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leave:' || request_leave.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = request_leave.tenant and r."user_id" = v_me
      and r."cancelled_at" is null and (r."approved_at" is not null or p."status" = 'pending')
      and daterange(r."starts_on", r."ends_on", '[]') && daterange(request_leave.starts_on, request_leave.ends_on, '[]')
      and not (r."partial" = 'morning' and v_partial = 'afternoon')
      and not (r."partial" = 'afternoon' and v_partial = 'morning')
  ) then
    raise exception 'this overlaps another leave request' using errcode = '23P01', hint = 'LEAVE_OVERLAP';
  end if;
  if v_type."tracked" and "better_supabase"."leave_available"(request_leave.tenant, v_me, v_type."id", extract(year from request_leave.starts_on)::integer) < v_amount then
    raise exception 'this request is more than the available balance' using errcode = '23514', hint = 'LEAVE_BALANCE_EXCEEDED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_leave_request"(uuid, uuid, date, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date, $5::numeric)', v_hook::oid::regproc)
        using request_leave.tenant, v_type."id", request_leave.starts_on, request_leave.ends_on, v_amount;
    end if;
  end;
  insert into "better_supabase"."leave_requests" ("tenant_id", "user_id", "type_id", "starts_on", "ends_on", "partial", "amount", "note")
  values (request_leave.tenant, v_me, v_type."id", request_leave.starts_on, request_leave.ends_on, v_partial, v_amount, nullif(trim(request_leave.note), ''))
  returning * into v_row;
  update "better_supabase"."leave_requests" x set "app_note" = case when request_leave.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."leave_requests", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(request_leave.fields) e where e.key in ('app_note'))) r
  where x."id" = v_row."id"
  returning x.* into v_row;
  v_request := "better_supabase"."open_approval"(
    request_leave.tenant, 'leave_request', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"leave.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_me, 'typeId', v_type."id", 'type', v_type."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_amount::text, 'unit', v_type."unit")
  );
  update "better_supabase"."leave_requests" x set "approval_id" = (v_request ->> 'id')::uuid
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_leave_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb) from public, anon;
grant execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb) to authenticated, service_role;

-- Books the leave once the approval is final: approved_at and, for a
-- tracked type, a taken entry. Approvals calls it; it isn't granted to anyone.
create or replace function "better_supabase"."approve_leave_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leave_requests"%rowtype;
begin
  update "better_supabase"."leave_requests" x set "approved_at" = now(), "updated_at" = now()
    where x."id" = approve_leave_request.request_id and x."approved_at" is null and x."cancelled_at" is null
    returning * into v_row;
  if not found then
    return;
  end if;
  insert into "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "kind", "amount", "period", "request_id")
  select v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id"
  from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  null;
end;
$$;
revoke execute on function "better_supabase"."approve_leave_request"(uuid) from public, anon, authenticated;

-- Cancels a request: the requester before it starts, or a manager any
-- time. A pending approval is cancelled with it; approved leave goes back
-- to the balance.
create or replace function "better_supabase"."cancel_leave_request"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_manager boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = cancel_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  v_manager := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false);
  if not (v_manager or v_row."user_id" = auth.uid()) then
    raise exception 'not allowed to cancel this leave request' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_row."cancelled_at" is not null then
    raise exception 'this leave request is already cancelled' using errcode = '55000', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  if not v_manager and v_row."approved_at" is not null and v_row."starts_on" <= current_date then
    raise exception 'leave that has started can only be cancelled by a manager' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  if v_row."approved_at" is not null then
    insert into "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "kind", "amount", "period", "request_id", "note", "created_by")
    select v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled', auth.uid()
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."cancel_leave_request"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_leave_request"(uuid) to authenticated, service_role;

-- Requests that overlap a date range, earliest first: the caller's, or
-- everyone's with the read permission.
create or replace function "better_supabase"."list_leave_requests"(tenant uuid, user_id uuid default null, status text default null, starts date default null, ends date default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leave_requests.tenant, 'leave.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_leave_requests.tenant, 'leave.request'), false)) then
    raise exception 'not allowed to list leave requests' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id <> auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', r."note", 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at", 'fields', jsonb_build_object('app_note', r."app_note")) as item, r."starts_on" as starts, r."created_at" as created
    from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = list_leave_requests.tenant
      and (case
        when coalesce(list_leave_requests.everyone, false) then true
        when list_leave_requests.user_id is not null then r."user_id" = list_leave_requests.user_id
        else r."user_id" = auth.uid()
      end)
      and (list_leave_requests.status is null or case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end = list_leave_requests.status)
      and (list_leave_requests.starts is null or r."ends_on" >= list_leave_requests.starts)
      and (list_leave_requests.ends is null or r."starts_on" <= list_leave_requests.ends)
    order by r."starts_on", r."created_at"
    limit least(greatest(coalesce(list_leave_requests.page_size, 100), 1), 500)
  ) z;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."list_leave_requests"(uuid, uuid, text, date, date, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_leave_requests"(uuid, uuid, text, date, date, boolean, integer) to authenticated, service_role;

-- A member's balance of each tracked type for one period (default this
-- year): granted, taken, pending and available.
create or replace function "better_supabase"."leave_balances"(tenant uuid, user_id uuid default null, period integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(leave_balances.user_id, auth.uid());
  v_period integer := coalesce(leave_balances.period, extract(year from current_date)::integer);
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.read'), false)
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_user is null then
    raise exception 'name user_id' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t."id", 'key', t."key", 'name', t."name", 'unit', t."unit",
      'userId', v_user, 'period', v_period,
      'granted', coalesce(b.granted, 0)::text,
      'taken', coalesce(b.taken, 0)::text,
      'pending', coalesce(w.pending, 0)::text,
      'available', (coalesce(b.total, 0) - coalesce(w.pending, 0))::text
    ) order by t."name"), '[]'::jsonb) into v_rows
  from "better_supabase"."leave_types" t
  left join lateral (
    select sum(x."amount") filter (where x."kind" <> 'taken') as granted,
      -sum(x."amount") filter (where x."kind" = 'taken') as taken,
      sum(x."amount") as total
    from "better_supabase"."leave_ledger" x
    where x."tenant_id" = leave_balances.tenant and x."user_id" = v_user
      and x."type_id" = t."id" and x."period" = v_period
  ) b on true
  left join lateral (
    select sum(r."amount") as pending
    from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = leave_balances.tenant and r."user_id" = v_user
      and r."type_id" = t."id" and extract(year from r."starts_on")::integer = v_period and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'
  ) w on true
  where t."tenant_id" = leave_balances.tenant and t."tracked" and t."archived_at" is null;
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."leave_balances"(uuid, uuid, integer) from public, anon;
grant execute on function "better_supabase"."leave_balances"(uuid, uuid, integer) to authenticated, service_role;

-- A member's ledger entries of one period, newest first.
create or replace function "better_supabase"."leave_ledger_entries"(tenant uuid, user_id uuid default null, period integer default null, type_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(leave_ledger_entries.user_id, auth.uid());
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.read'), false)
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'kind', x."kind", 'amount', x."amount"::text, 'period', x."period", 'requestId', x."request_id", 'note', x."note", 'createdAt', x."created_at") order by x."created_at" desc, x."id" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."leave_ledger" x
  where x."tenant_id" = leave_ledger_entries.tenant and x."user_id" = v_user
    and (leave_ledger_entries.period is null or x."period" = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x."type_id" = leave_ledger_entries.type_id);
  return v_rows;
end;
$$;
revoke execute on function "better_supabase"."leave_ledger_entries"(uuid, uuid, integer, uuid) from public, anon;
grant execute on function "better_supabase"."leave_ledger_entries"(uuid, uuid, integer, uuid) to authenticated, service_role;

-- Adds a grant or a manual adjustment (signed) to a member's balance.
create or replace function "better_supabase"."adjust_leave_balance"(tenant uuid, user_id uuid, type_id uuid, amount numeric, period integer default null, kind text default 'adjustment', note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leave_ledger"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', adjust_leave_balance.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to adjust leave balances' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if coalesce(adjust_leave_balance.kind, 'adjustment') not in ('grant', 'adjustment') then
    raise exception 'kind must be grant or adjustment' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if adjust_leave_balance.amount is null or adjust_leave_balance.amount = 0 then
    raise exception 'amount must not be zero' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = adjust_leave_balance.tenant and m."user_id" = adjust_leave_balance.user_id) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."leave_types" t where t."id" = adjust_leave_balance.type_id and t."tenant_id" = adjust_leave_balance.tenant) then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  insert into "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "kind", "amount", "period", "note", "created_by")
  values (adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id, coalesce(adjust_leave_balance.kind, 'adjustment'),
    adjust_leave_balance.amount, coalesce(adjust_leave_balance.period, extract(year from current_date)::integer), nullif(trim(adjust_leave_balance.note), ''), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'kind', v_row."kind", 'amount', v_row."amount"::text, 'period', v_row."period", 'requestId', v_row."request_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."adjust_leave_balance"(uuid, uuid, uuid, numeric, integer, text, text) from public, anon;
grant execute on function "better_supabase"."adjust_leave_balance"(uuid, uuid, uuid, numeric, integer, text, text) to authenticated, service_role;

-- Grants every member (or user_ids) an accrual of one type: amount, or the
-- type's allowance. With idempotency_key a member gets it once, so a
-- scheduled job can run it again safely. Returns how many entries it wrote.
create or replace function "better_supabase"."accrue_leave"(tenant uuid, type_id uuid, amount numeric default null, period integer default null, user_ids uuid[] default null, idempotency_key text default null, note text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type "better_supabase"."leave_types"%rowtype;
  v_amount numeric;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', accrue_leave.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to accrue leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."leave_types" t where t."id" = accrue_leave.type_id and t."tenant_id" = accrue_leave.tenant;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  v_amount := coalesce(accrue_leave.amount, v_type."allowance");
  if v_amount is null or v_amount <= 0 then
    raise exception 'name an amount, or give the type an allowance' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  insert into "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "kind", "amount", "period", "idempotency_key", "note", "created_by")
  select accrue_leave.tenant, m."user_id", v_type."id", 'accrual', v_amount,
    coalesce(accrue_leave.period, extract(year from current_date)::integer), accrue_leave.idempotency_key, nullif(trim(accrue_leave.note), ''), auth.uid()
  from "better_supabase"."memberships" m
  where m."organization_id" = accrue_leave.tenant
    and (accrue_leave.user_ids is null or m."user_id" = any (accrue_leave.user_ids))
  on conflict ("tenant_id", "user_id", "type_id", "idempotency_key") where "idempotency_key" is not null do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries it wrote.
create or replace function "better_supabase"."close_leave_year"(tenant uuid, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_written integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_leave_year.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to close leave periods' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if close_leave_year.period is null then
    raise exception 'name the period to close' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  with balances as (
    select x."user_id" as user_id, x."type_id" as type_id, sum(x."amount") as balance,
      least(sum(x."amount"), coalesce(t."carryover_max", sum(x."amount"))) as carry
    from "better_supabase"."leave_ledger" x
    join "better_supabase"."leave_types" t on t."id" = x."type_id" and t."tracked"
    where x."tenant_id" = close_leave_year.tenant and x."period" = close_leave_year.period
    group by x."user_id", x."type_id", t."carryover_max"
    having sum(x."amount") > 0
  )
  insert into "better_supabase"."leave_ledger" ("tenant_id", "user_id", "type_id", "kind", "amount", "period", "idempotency_key", "created_by")
  select close_leave_year.tenant, b.user_id, b.type_id, e.kind, e.amount, e.period, v_key || ':' || e.kind || ':' || e.period::text, auth.uid()
  from balances b
  cross join lateral (values
    ('carryover', -b.carry, close_leave_year.period),
    ('carryover', b.carry, close_leave_year.period + 1),
    ('expiry', -(b.balance - b.carry), close_leave_year.period)
  ) as e(kind, amount, period)
  where e.amount <> 0
  on conflict ("tenant_id", "user_id", "type_id", "idempotency_key") where "idempotency_key" is not null do nothing;
  get diagnostics v_written = row_count;
  return v_written;
end;
$$;
revoke execute on function "better_supabase"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."close_leave_year"(uuid, integer) to authenticated, service_role;

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

-- ==== data supabase/better-supabase-data/900_better_supabase_109_leave.sql
-- better-supabase module: leave
-- @bs-module-data leave
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('leave', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
