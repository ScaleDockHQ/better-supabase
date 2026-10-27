-- ==== alone: schema supabase/schemas/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block leave@3 managed
-- @bsb-hash sha256:a3714088f9884f8e19134bc5e8dd61916245e44da955ccfaab24132c91e2eb20
-- Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."leave_types" from public, anon, authenticated;
grant select on "better_supabase"."leave_types" to authenticated;
grant all on "better_supabase"."leave_types" to service_role;
drop policy if exists leave_types_read on "better_supabase"."leave_types";
create policy leave_types_read on "better_supabase"."leave_types"
  for select to authenticated
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
create index if not exists "leave_requests_user_idx" on "better_supabase"."leave_requests" ("tenant_id", "user_id", "starts_on" desc);
create index if not exists "leave_requests_dates_idx" on "better_supabase"."leave_requests" ("tenant_id", "starts_on", "ends_on");
create index if not exists "leave_requests_approval_idx" on "better_supabase"."leave_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "leave_requests_type_idx" on "better_supabase"."leave_requests" ("tenant_id", "type_id");
alter table "better_supabase"."leave_requests" enable row level security;
revoke all on "better_supabase"."leave_requests" from public, anon, authenticated;
grant select on "better_supabase"."leave_requests" to authenticated;
grant all on "better_supabase"."leave_requests" to service_role;
drop policy if exists leave_requests_read on "better_supabase"."leave_requests";
create policy leave_requests_read on "better_supabase"."leave_requests"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));


-- Posts one leave movement to a member's account of a type and period:
-- against the type's taken account for taken leave, the member's account
-- of to_period for a carryover, else the type's pool. Returns the ledger
-- transaction; with a key a second post returns the first.
create or replace function "better_supabase"."leave_post"(tenant uuid, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_account uuid;
  v_counter uuid;
  v_amount bigint := round(leave_post.amount * 100);
begin
  select t."unit" into v_unit from "better_supabase"."leave_types" t where t."id" = leave_post.type_id;
  v_account := "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period));
  v_counter := case
    when leave_post.to_period is not null then
      "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.to_period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.to_period))
    else "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave_pool',
      'leave:' || leave_post.type_id::text || case when leave_post.kind = 'taken' then ':taken' else ':pool' end,
      case when leave_post.kind = 'taken' then 'Leave taken' else 'Leave pool' end, v_unit, 2::smallint,
      'leave-types', leave_post.type_id::text, null, true, 'leave.read', 'leave', null)
  end;
  return "better_supabase"."ledger_post"(leave_post.tenant, 'leave.' || leave_post.kind,
    jsonb_build_array(
      jsonb_build_object('account', v_account, 'amount', v_amount),
      jsonb_build_object('account', v_counter, 'amount', -v_amount)),
    case when leave_post.request_id is not null then 'leave-requests' end, leave_post.request_id::text,
    nullif(trim(leave_post.note), ''),
    case when leave_post.key is not null then 'leave:' || leave_post.user_id::text || ':' || leave_post.type_id::text || ':' || leave_post.key end,
    null,
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period, 'kind', leave_post.kind));
end;
$$;
revoke execute on function "better_supabase"."leave_post"(uuid, uuid, uuid, text, numeric, integer, uuid, text, text, integer) from public, anon, authenticated;

-- Whether a member already has the leave movement with this key.
create or replace function "better_supabase"."leave_posted"(tenant uuid, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from "better_supabase"."ledger_transactions" r where r."tenant_id" = leave_posted.tenant
    and r."idempotency_key" = 'leave:' || leave_posted.user_id::text || ':' || leave_posted.type_id::text || ':' || leave_posted.key)
$$;
revoke execute on function "better_supabase"."leave_posted"(uuid, uuid, uuid, text) from public, anon, authenticated;

-- A member's balance of one type for one period: the account's balance,
-- minus the requests still waiting for approval.
create or replace function "better_supabase"."leave_available"(tenant uuid, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b."balance"::numeric / 100 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
      where x."tenant_id" = leave_available.tenant and x."code" = 'leave:' || leave_available.type_id::text || ':' || leave_available.user_id::text || ':' || leave_available.period::text), 0)
    - coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_available.tenant and r."user_id" = leave_available.user_id
        and r."type_id" = leave_available.type_id and extract(year from r."starts_on")::integer = leave_available.period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0)
$$;
revoke execute on function "better_supabase"."leave_available"(uuid, uuid, uuid, integer) from public, anon, authenticated;

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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_user is null then
    raise exception 'name user_id' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t."id", 'key', t."key", 'name', t."name", 'unit', t."unit",
      'userId', v_user, 'period', v_period,
      'granted', (coalesce(b.granted, 0)::numeric / 100)::numeric(10, 2)::text,
      'taken', (coalesce(b.taken, 0)::numeric / 100)::numeric(10, 2)::text,
      'pending', w.pending::numeric(10, 2)::text,
      'available', (coalesce(b.total, 0)::numeric / 100 - w.pending)::numeric(10, 2)::text
    ) order by t."name"), '[]'::jsonb) into v_rows
  from "better_supabase"."leave_types" t
  left join lateral (
    select sum(y."amount") filter (where r."kind" <> 'leave.taken') as granted,
      -sum(y."amount") filter (where r."kind" = 'leave.taken') as taken,
      sum(y."amount") as total
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."tenant_id" = leave_balances.tenant and x."code" = 'leave:' || t."id"::text || ':' || v_user::text || ':' || v_period::text
  ) b on true
  cross join lateral (
    select coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_balances.tenant and r."user_id" = v_user
        and r."type_id" = t."id" and extract(year from r."starts_on")::integer = v_period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0) as pending
  ) w
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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") order by y."created_at" desc, y."id" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where x."tenant_id" = leave_ledger_entries.tenant and x."owner_id" = v_user
    and (leave_ledger_entries.period is null or (x."metadata" ->> 'period')::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x."holder_id" = leave_ledger_entries.type_id::text);
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
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;
begin
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
  v_transaction := "better_supabase"."leave_post"(adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y."id", jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") into v_entry, v_row
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where y."transaction_id" = v_transaction and x."owner_id" = adjust_leave_balance.user_id;
  null;
  return v_row;
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
  v_user uuid;
  v_count integer := 0;
begin
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
  for v_user in
    select m."user_id" from "better_supabase"."memberships" m
    where m."organization_id" = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m."user_id" = any (accrue_leave.user_ids))
  loop
    continue when accrue_leave.idempotency_key is not null
      and "better_supabase"."leave_posted"(accrue_leave.tenant, v_user, v_type."id", accrue_leave.idempotency_key);
    perform "better_supabase"."leave_post"(accrue_leave.tenant, v_user, v_type."id", 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from current_date)::integer), null, accrue_leave.note, accrue_leave.idempotency_key);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries on members' accounts it wrote.
create or replace function "better_supabase"."close_leave_year"(tenant uuid, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_row record;
  v_written integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_leave_year.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to close leave periods' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if close_leave_year.period is null then
    raise exception 'name the period to close' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_row in
    select x."owner_id" as user_id, t."id" as type_id, b."balance"::numeric / 100 as balance,
      least(b."balance"::numeric / 100, coalesce(t."carryover_max", b."balance"::numeric / 100)) as carry
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
    join "better_supabase"."leave_types" t on t."id"::text = x."holder_id" and t."tracked"
    where x."tenant_id" = close_leave_year.tenant and x."managed_by" = 'leave' and x."kind" = 'leave'
      and (x."metadata" ->> 'period')::integer = close_leave_year.period and b."balance" > 0
  loop
    if v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':carryover:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'carryover', -v_row.carry, close_leave_year.period,
        null, null, v_key || ':carryover:' || close_leave_year.period::text, close_leave_year.period + 1);
      v_written := v_written + 2;
    end if;
    if v_row.balance - v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':expiry:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry), close_leave_year.period,
        null, null, v_key || ':expiry:' || close_leave_year.period::text);
      v_written := v_written + 1;
    end if;
  end loop;
  return v_written;
end;
$$;
revoke execute on function "better_supabase"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."close_leave_year"(uuid, integer) to authenticated, service_role;

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
drop function if exists "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb);
create or replace function "better_supabase"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null)
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) from public, anon;
grant execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) to authenticated, service_role;

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
  perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
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
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
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
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', r."note", 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at") as item, r."starts_on" as starts, r."created_at" as created
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
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
create policy bsb_tenant_scope_select on "better_supabase"."leave_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
create policy bsb_tenant_scope_update on "better_supabase"."leave_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_select on "better_supabase"."leave_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_update on "better_supabase"."leave_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_requests" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block-data leave
-- @bsb-hash sha256:469ff4c4bc15d1e8ee80aa4c07064294ad84d3ad846f25e7bfca61c713c861e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block leave@3 managed
-- @bsb-hash sha256:563b898c0738ec59ed994b7459f9ef32e004451f55d84020bcf5c22d0aacab5e
-- Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."leave_types" from public, anon, authenticated;
grant select on "better_supabase"."leave_types" to authenticated;
grant all on "better_supabase"."leave_types" to service_role;
drop policy if exists leave_types_read on "better_supabase"."leave_types";
create policy leave_types_read on "better_supabase"."leave_types"
  for select to authenticated
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
create index if not exists "leave_requests_user_idx" on "better_supabase"."leave_requests" ("tenant_id", "user_id", "starts_on" desc);
create index if not exists "leave_requests_dates_idx" on "better_supabase"."leave_requests" ("tenant_id", "starts_on", "ends_on");
create index if not exists "leave_requests_approval_idx" on "better_supabase"."leave_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "leave_requests_type_idx" on "better_supabase"."leave_requests" ("tenant_id", "type_id");
alter table "better_supabase"."leave_requests" enable row level security;
revoke all on "better_supabase"."leave_requests" from public, anon, authenticated;
grant select on "better_supabase"."leave_requests" to authenticated;
grant all on "better_supabase"."leave_requests" to service_role;
drop policy if exists leave_requests_read on "better_supabase"."leave_requests";
create policy leave_requests_read on "better_supabase"."leave_requests"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));


-- leave_requests.employee_id: the employee behind the row's user, kept in step with
-- employees by the two triggers below.
alter table "better_supabase"."leave_requests" add column if not exists employee_id uuid references "better_supabase"."employees" ("id") on delete set null;
create index if not exists "leave_requests_employee_idx" on "better_supabase"."leave_requests" (employee_id) where employee_id is not null;

create or replace function better_supabase.bsb_leave_requests_employee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.employee_id := (
    select x."id" from "better_supabase"."employees" x
    where x."tenant_id" = new."tenant_id" and x."user_id" = new."user_id"
  );
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_leave_requests_employee() from public, anon, authenticated;
drop trigger if exists bsb_leave_requests_employee on "better_supabase"."leave_requests";
create trigger bsb_leave_requests_employee before insert or update of "user_id" on "better_supabase"."leave_requests"
for each row execute function better_supabase.bsb_leave_requests_employee();

create or replace function better_supabase.bsb_leave_requests_employee_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old."user_id" is not null then
    update "better_supabase"."leave_requests" set employee_id = null
    where employee_id = old."id" and "user_id" is distinct from new."user_id";
  end if;
  if new."user_id" is not null then
    update "better_supabase"."leave_requests" set employee_id = new."id"
    where "tenant_id" = new."tenant_id" and "user_id" = new."user_id"
      and employee_id is distinct from new."id";
  end if;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_leave_requests_employee_sync() from public, anon, authenticated;
drop trigger if exists bsb_leave_requests_employee_sync on "better_supabase"."employees";
create trigger bsb_leave_requests_employee_sync after insert or update of "user_id" on "better_supabase"."employees"
for each row execute function better_supabase.bsb_leave_requests_employee_sync();

-- Posts one leave movement to a member's account of a type and period:
-- against the type's taken account for taken leave, the member's account
-- of to_period for a carryover, else the type's pool. Returns the ledger
-- transaction; with a key a second post returns the first.
create or replace function "better_supabase"."leave_post"(tenant uuid, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_account uuid;
  v_counter uuid;
  v_amount bigint := round(leave_post.amount * 100);
begin
  select t."unit" into v_unit from "better_supabase"."leave_types" t where t."id" = leave_post.type_id;
  v_account := "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period));
  v_counter := case
    when leave_post.to_period is not null then
      "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.to_period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.to_period))
    else "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave_pool',
      'leave:' || leave_post.type_id::text || case when leave_post.kind = 'taken' then ':taken' else ':pool' end,
      case when leave_post.kind = 'taken' then 'Leave taken' else 'Leave pool' end, v_unit, 2::smallint,
      'leave-types', leave_post.type_id::text, null, true, 'leave.read', 'leave', null)
  end;
  return "better_supabase"."ledger_post"(leave_post.tenant, 'leave.' || leave_post.kind,
    jsonb_build_array(
      jsonb_build_object('account', v_account, 'amount', v_amount),
      jsonb_build_object('account', v_counter, 'amount', -v_amount)),
    case when leave_post.request_id is not null then 'leave-requests' end, leave_post.request_id::text,
    nullif(trim(leave_post.note), ''),
    case when leave_post.key is not null then 'leave:' || leave_post.user_id::text || ':' || leave_post.type_id::text || ':' || leave_post.key end,
    null,
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period, 'kind', leave_post.kind));
end;
$$;
revoke execute on function "better_supabase"."leave_post"(uuid, uuid, uuid, text, numeric, integer, uuid, text, text, integer) from public, anon, authenticated;

-- Whether a member already has the leave movement with this key.
create or replace function "better_supabase"."leave_posted"(tenant uuid, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from "better_supabase"."ledger_transactions" r where r."tenant_id" = leave_posted.tenant
    and r."idempotency_key" = 'leave:' || leave_posted.user_id::text || ':' || leave_posted.type_id::text || ':' || leave_posted.key)
$$;
revoke execute on function "better_supabase"."leave_posted"(uuid, uuid, uuid, text) from public, anon, authenticated;

-- A member's balance of one type for one period: the account's balance,
-- minus the requests still waiting for approval.
create or replace function "better_supabase"."leave_available"(tenant uuid, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b."balance"::numeric / 100 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
      where x."tenant_id" = leave_available.tenant and x."code" = 'leave:' || leave_available.type_id::text || ':' || leave_available.user_id::text || ':' || leave_available.period::text), 0)
    - coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_available.tenant and r."user_id" = leave_available.user_id
        and r."type_id" = leave_available.type_id and extract(year from r."starts_on")::integer = leave_available.period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0)
$$;
revoke execute on function "better_supabase"."leave_available"(uuid, uuid, uuid, integer) from public, anon, authenticated;

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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_user is null then
    raise exception 'name user_id' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t."id", 'key', t."key", 'name', t."name", 'unit', t."unit",
      'userId', v_user, 'period', v_period,
      'granted', (coalesce(b.granted, 0)::numeric / 100)::numeric(10, 2)::text,
      'taken', (coalesce(b.taken, 0)::numeric / 100)::numeric(10, 2)::text,
      'pending', w.pending::numeric(10, 2)::text,
      'available', (coalesce(b.total, 0)::numeric / 100 - w.pending)::numeric(10, 2)::text
    ) order by t."name"), '[]'::jsonb) into v_rows
  from "better_supabase"."leave_types" t
  left join lateral (
    select sum(y."amount") filter (where r."kind" <> 'leave.taken') as granted,
      -sum(y."amount") filter (where r."kind" = 'leave.taken') as taken,
      sum(y."amount") as total
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."tenant_id" = leave_balances.tenant and x."code" = 'leave:' || t."id"::text || ':' || v_user::text || ':' || v_period::text
  ) b on true
  cross join lateral (
    select coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_balances.tenant and r."user_id" = v_user
        and r."type_id" = t."id" and extract(year from r."starts_on")::integer = v_period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0) as pending
  ) w
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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") order by y."created_at" desc, y."id" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where x."tenant_id" = leave_ledger_entries.tenant and x."owner_id" = v_user
    and (leave_ledger_entries.period is null or (x."metadata" ->> 'period')::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x."holder_id" = leave_ledger_entries.type_id::text);
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
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;
begin
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
  v_transaction := "better_supabase"."leave_post"(adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y."id", jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") into v_entry, v_row
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where y."transaction_id" = v_transaction and x."owner_id" = adjust_leave_balance.user_id;
  perform "better_supabase".emit_event('leave.adjusted', jsonb_build_object('organizationId', adjust_leave_balance.tenant, 'id', v_entry, 'userId', adjust_leave_balance.user_id, 'typeId', adjust_leave_balance.type_id, 'kind', coalesce(adjust_leave_balance.kind, 'adjustment'), 'amount', adjust_leave_balance.amount::numeric(8, 2)::text, 'period', v_period), 'leave-ledger-entries/' || v_entry::text, (adjust_leave_balance.tenant)::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave.adjusted',
    category => 'data',
    target_type => 'leave_balance',
    record_id => v_entry::text,
    summary => 'adjusted a leave balance by ' || adjust_leave_balance.amount::numeric(8, 2)::text,
    tenant => (adjust_leave_balance.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', adjust_leave_balance.tenant, 'id', v_entry, 'userId', adjust_leave_balance.user_id, 'typeId', adjust_leave_balance.type_id, 'kind', coalesce(adjust_leave_balance.kind, 'adjustment'), 'amount', adjust_leave_balance.amount::numeric(8, 2)::text, 'period', v_period)
  );
  return v_row;
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
  v_user uuid;
  v_count integer := 0;
begin
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
  for v_user in
    select m."user_id" from "better_supabase"."memberships" m
    where m."organization_id" = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m."user_id" = any (accrue_leave.user_ids))
  loop
    continue when accrue_leave.idempotency_key is not null
      and "better_supabase"."leave_posted"(accrue_leave.tenant, v_user, v_type."id", accrue_leave.idempotency_key);
    perform "better_supabase"."leave_post"(accrue_leave.tenant, v_user, v_type."id", 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from current_date)::integer), null, accrue_leave.note, accrue_leave.idempotency_key);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries on members' accounts it wrote.
create or replace function "better_supabase"."close_leave_year"(tenant uuid, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_row record;
  v_written integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_leave_year.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to close leave periods' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if close_leave_year.period is null then
    raise exception 'name the period to close' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_row in
    select x."owner_id" as user_id, t."id" as type_id, b."balance"::numeric / 100 as balance,
      least(b."balance"::numeric / 100, coalesce(t."carryover_max", b."balance"::numeric / 100)) as carry
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
    join "better_supabase"."leave_types" t on t."id"::text = x."holder_id" and t."tracked"
    where x."tenant_id" = close_leave_year.tenant and x."managed_by" = 'leave' and x."kind" = 'leave'
      and (x."metadata" ->> 'period')::integer = close_leave_year.period and b."balance" > 0
  loop
    if v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':carryover:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'carryover', -v_row.carry, close_leave_year.period,
        null, null, v_key || ':carryover:' || close_leave_year.period::text, close_leave_year.period + 1);
      v_written := v_written + 2;
    end if;
    if v_row.balance - v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':expiry:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry), close_leave_year.period,
        null, null, v_key || ':expiry:' || close_leave_year.period::text);
      v_written := v_written + 1;
    end if;
  end loop;
  return v_written;
end;
$$;
revoke execute on function "better_supabase"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."close_leave_year"(uuid, integer) to authenticated, service_role;

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
drop function if exists "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb);
create or replace function "better_supabase"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null)
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
  v_request := "better_supabase"."open_approval"(
    request_leave.tenant, 'leave_request', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"leave.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_me, 'typeId', v_type."id", 'type', v_type."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_amount::text, 'unit', v_type."unit")
  );
  update "better_supabase"."leave_requests" x set "approval_id" = (v_request ->> 'id')::uuid
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  perform "better_supabase".emit_event('leave.requested', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave.requested',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'requested leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_leave_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) from public, anon;
grant execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) to authenticated, service_role;

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
  perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
  from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  perform "better_supabase".emit_event('leave.approved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave.approved',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'approved leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
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
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
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
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  perform "better_supabase".emit_event('leave.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave.cancelled',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'cancelled leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_leave_request"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_leave_request"(uuid) to authenticated, service_role;

-- The approved leave of the organization a share link points at, for an
-- iCal feed: a year back and everything ahead. Open to anon: the token is
-- the credential, and the link's creator must still read everyone's leave.
create or replace function "better_supabase"."leave_feed"(token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_link uuid;
  v_tenant uuid;
  v_creator uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if leave_feed.token is null or length(leave_feed.token) < 32 then
    return null;
  end if;
  select l."id", l."tenant_id", l."created_by" into v_link, v_tenant, v_creator
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(leave_feed.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'leave_feed'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses") and l."subject_id" = l."tenant_id"::text
  for update;
  if v_tenant is null or v_creator is null or not coalesce(better_supabase.can_user(v_creator, 'tenant', v_tenant, 'leave.read'), false) then
    return null;
  end if;
  update "better_supabase"."share_links" set "use_count" = "use_count" + 1, "last_used_at" = now() where "id" = v_link;
  return jsonb_build_object(
    'organizationId', v_tenant,
    'requests', coalesce((
      select jsonb_agg(x.item order by x.starts_on, x.id)
      from (
        select jsonb_build_object('id', r."id", 'userId', r."user_id", 'typeId', r."type_id", 'type', t."name", 'unit', t."unit",
          'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'approvedAt', r."approved_at", 'updatedAt', r."updated_at") as item,
          r."starts_on" as starts_on, r."id" as id
        from "better_supabase"."leave_requests" r
        join "better_supabase"."leave_types" t on t."id" = r."type_id"
        where r."tenant_id" = v_tenant and r."approved_at" is not null and r."cancelled_at" is null
          and r."ends_on" >= current_date - 366
        order by r."starts_on", r."id"
        limit 5000
      ) x
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function "better_supabase"."leave_feed"(text) from public;
grant execute on function "better_supabase"."leave_feed"(text) to anon, authenticated, service_role;

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
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', r."note", 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at") as item, r."starts_on" as starts, r."created_at" as created
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
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
create policy bsb_tenant_scope_select on "better_supabase"."leave_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
create policy bsb_tenant_scope_update on "better_supabase"."leave_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_select on "better_supabase"."leave_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_update on "better_supabase"."leave_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_requests" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block-data leave
-- @bsb-hash sha256:469ff4c4bc15d1e8ee80aa4c07064294ad84d3ad846f25e7bfca61c713c861e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block leave@3 managed
-- @bsb-hash sha256:878c98886bb61c5b00e1c6c99d408f66498ab0aa8d5e38566f507ff26930caad
-- Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member.
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
    drop policy if exists bsb_tenant_scope on "app_private"."leave_types";
    drop policy if exists bsb_tenant_scope_select on "app_private"."leave_types";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."leave_types";
    drop policy if exists bsb_tenant_scope_update on "app_private"."leave_types";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."leave_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."leave_requests";
    drop policy if exists bsb_tenant_scope_select on "app_private"."leave_requests";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."leave_requests";
    drop policy if exists bsb_tenant_scope_update on "app_private"."leave_requests";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."leave_requests";
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
create table if not exists "app_private"."leave_types" (
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
alter table "app_private"."leave_types" enable row level security;
revoke all on "app_private"."leave_types" from public, anon, authenticated;
grant select on "app_private"."leave_types" to authenticated;
grant all on "app_private"."leave_types" to service_role;
drop policy if exists leave_types_read on "app_private"."leave_types";
create policy leave_types_read on "app_private"."leave_types"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));

create table if not exists "app_private"."leave_requests" (
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
  foreign key ("tenant_id", "type_id") references "app_private"."leave_types" ("tenant_id", "id") on delete restrict
);
create index if not exists "leave_requests_user_idx" on "app_private"."leave_requests" ("tenant_id", "user_id", "starts_on" desc);
create index if not exists "leave_requests_dates_idx" on "app_private"."leave_requests" ("tenant_id", "starts_on", "ends_on");
create index if not exists "leave_requests_approval_idx" on "app_private"."leave_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "leave_requests_type_idx" on "app_private"."leave_requests" ("tenant_id", "type_id");
alter table "app_private"."leave_requests" enable row level security;
revoke all on "app_private"."leave_requests" from public, anon, authenticated;
grant select on "app_private"."leave_requests" to authenticated;
grant all on "app_private"."leave_requests" to service_role;
drop policy if exists leave_requests_read on "app_private"."leave_requests";
create policy leave_requests_read on "app_private"."leave_requests"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));


-- Posts one leave movement to a member's account of a type and period:
-- against the type's taken account for taken leave, the member's account
-- of to_period for a carryover, else the type's pool. Returns the ledger
-- transaction; with a key a second post returns the first.
create or replace function "app_private"."leave_post"(tenant uuid, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_account uuid;
  v_counter uuid;
  v_amount bigint := round(leave_post.amount * 100);
begin
  select t."unit" into v_unit from "app_private"."leave_types" t where t."id" = leave_post.type_id;
  v_account := "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period));
  v_counter := case
    when leave_post.to_period is not null then
      "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.to_period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.to_period))
    else "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave_pool',
      'leave:' || leave_post.type_id::text || case when leave_post.kind = 'taken' then ':taken' else ':pool' end,
      case when leave_post.kind = 'taken' then 'Leave taken' else 'Leave pool' end, v_unit, 2::smallint,
      'leave-types', leave_post.type_id::text, null, true, 'leave.read', 'leave', null)
  end;
  return "better_supabase"."ledger_post"(leave_post.tenant, 'leave.' || leave_post.kind,
    jsonb_build_array(
      jsonb_build_object('account', v_account, 'amount', v_amount),
      jsonb_build_object('account', v_counter, 'amount', -v_amount)),
    case when leave_post.request_id is not null then 'leave-requests' end, leave_post.request_id::text,
    nullif(trim(leave_post.note), ''),
    case when leave_post.key is not null then 'leave:' || leave_post.user_id::text || ':' || leave_post.type_id::text || ':' || leave_post.key end,
    null,
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period, 'kind', leave_post.kind));
end;
$$;
revoke execute on function "app_private"."leave_post"(uuid, uuid, uuid, text, numeric, integer, uuid, text, text, integer) from public, anon, authenticated;

-- Whether a member already has the leave movement with this key.
create or replace function "app_private"."leave_posted"(tenant uuid, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from "better_supabase"."ledger_transactions" r where r."tenant_id" = leave_posted.tenant
    and r."idempotency_key" = 'leave:' || leave_posted.user_id::text || ':' || leave_posted.type_id::text || ':' || leave_posted.key)
$$;
revoke execute on function "app_private"."leave_posted"(uuid, uuid, uuid, text) from public, anon, authenticated;

-- A member's balance of one type for one period: the account's balance,
-- minus the requests still waiting for approval.
create or replace function "app_private"."leave_available"(tenant uuid, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b."balance"::numeric / 100 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
      where x."tenant_id" = leave_available.tenant and x."code" = 'leave:' || leave_available.type_id::text || ':' || leave_available.user_id::text || ':' || leave_available.period::text), 0)
    - coalesce((select sum(r."amount") from "app_private"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_available.tenant and r."user_id" = leave_available.user_id
        and r."type_id" = leave_available.type_id and extract(year from r."starts_on")::integer = leave_available.period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0)
$$;
revoke execute on function "app_private"."leave_available"(uuid, uuid, uuid, integer) from public, anon, authenticated;

-- A member's balance of each tracked type for one period (default this
-- year): granted, taken, pending and available.
create or replace function "app_private"."leave_balances"(tenant uuid, user_id uuid default null, period integer default null)
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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_user is null then
    raise exception 'name user_id' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t."id", 'key', t."key", 'name', t."name", 'unit', t."unit",
      'userId', v_user, 'period', v_period,
      'granted', (coalesce(b.granted, 0)::numeric / 100)::numeric(10, 2)::text,
      'taken', (coalesce(b.taken, 0)::numeric / 100)::numeric(10, 2)::text,
      'pending', w.pending::numeric(10, 2)::text,
      'available', (coalesce(b.total, 0)::numeric / 100 - w.pending)::numeric(10, 2)::text
    ) order by t."name"), '[]'::jsonb) into v_rows
  from "app_private"."leave_types" t
  left join lateral (
    select sum(y."amount") filter (where r."kind" <> 'leave.taken') as granted,
      -sum(y."amount") filter (where r."kind" = 'leave.taken') as taken,
      sum(y."amount") as total
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."tenant_id" = leave_balances.tenant and x."code" = 'leave:' || t."id"::text || ':' || v_user::text || ':' || v_period::text
  ) b on true
  cross join lateral (
    select coalesce((select sum(r."amount") from "app_private"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_balances.tenant and r."user_id" = v_user
        and r."type_id" = t."id" and extract(year from r."starts_on")::integer = v_period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0) as pending
  ) w
  where t."tenant_id" = leave_balances.tenant and t."tracked" and t."archived_at" is null;
  return v_rows;
end;
$$;
revoke execute on function "app_private"."leave_balances"(uuid, uuid, integer) from public, anon;
grant execute on function "app_private"."leave_balances"(uuid, uuid, integer) to authenticated, service_role;

-- A member's ledger entries of one period, newest first.
create or replace function "app_private"."leave_ledger_entries"(tenant uuid, user_id uuid default null, period integer default null, type_id uuid default null)
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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") order by y."created_at" desc, y."id" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where x."tenant_id" = leave_ledger_entries.tenant and x."owner_id" = v_user
    and (leave_ledger_entries.period is null or (x."metadata" ->> 'period')::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x."holder_id" = leave_ledger_entries.type_id::text);
  return v_rows;
end;
$$;
revoke execute on function "app_private"."leave_ledger_entries"(uuid, uuid, integer, uuid) from public, anon;
grant execute on function "app_private"."leave_ledger_entries"(uuid, uuid, integer, uuid) to authenticated, service_role;

-- Adds a grant or a manual adjustment (signed) to a member's balance.
create or replace function "app_private"."adjust_leave_balance"(tenant uuid, user_id uuid, type_id uuid, amount numeric, period integer default null, kind text default 'adjustment', note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;
begin
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
  if not exists (select 1 from "app_private"."leave_types" t where t."id" = adjust_leave_balance.type_id and t."tenant_id" = adjust_leave_balance.tenant) then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  v_transaction := "app_private"."leave_post"(adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y."id", jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") into v_entry, v_row
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where y."transaction_id" = v_transaction and x."owner_id" = adjust_leave_balance.user_id;
  null;
  return v_row;
end;
$$;
revoke execute on function "app_private"."adjust_leave_balance"(uuid, uuid, uuid, numeric, integer, text, text) from public, anon;
grant execute on function "app_private"."adjust_leave_balance"(uuid, uuid, uuid, numeric, integer, text, text) to authenticated, service_role;

-- Grants every member (or user_ids) an accrual of one type: amount, or the
-- type's allowance. With idempotency_key a member gets it once, so a
-- scheduled job can run it again safely. Returns how many entries it wrote.
create or replace function "app_private"."accrue_leave"(tenant uuid, type_id uuid, amount numeric default null, period integer default null, user_ids uuid[] default null, idempotency_key text default null, note text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type "app_private"."leave_types"%rowtype;
  v_amount numeric;
  v_user uuid;
  v_count integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', accrue_leave.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to accrue leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "app_private"."leave_types" t where t."id" = accrue_leave.type_id and t."tenant_id" = accrue_leave.tenant;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  v_amount := coalesce(accrue_leave.amount, v_type."allowance");
  if v_amount is null or v_amount <= 0 then
    raise exception 'name an amount, or give the type an allowance' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_user in
    select m."user_id" from "better_supabase"."memberships" m
    where m."organization_id" = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m."user_id" = any (accrue_leave.user_ids))
  loop
    continue when accrue_leave.idempotency_key is not null
      and "app_private"."leave_posted"(accrue_leave.tenant, v_user, v_type."id", accrue_leave.idempotency_key);
    perform "app_private"."leave_post"(accrue_leave.tenant, v_user, v_type."id", 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from current_date)::integer), null, accrue_leave.note, accrue_leave.idempotency_key);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "app_private"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries on members' accounts it wrote.
create or replace function "app_private"."close_leave_year"(tenant uuid, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_row record;
  v_written integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_leave_year.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to close leave periods' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if close_leave_year.period is null then
    raise exception 'name the period to close' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_row in
    select x."owner_id" as user_id, t."id" as type_id, b."balance"::numeric / 100 as balance,
      least(b."balance"::numeric / 100, coalesce(t."carryover_max", b."balance"::numeric / 100)) as carry
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
    join "app_private"."leave_types" t on t."id"::text = x."holder_id" and t."tracked"
    where x."tenant_id" = close_leave_year.tenant and x."managed_by" = 'leave' and x."kind" = 'leave'
      and (x."metadata" ->> 'period')::integer = close_leave_year.period and b."balance" > 0
  loop
    if v_row.carry <> 0 and not "app_private"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':carryover:' || close_leave_year.period::text) then
      perform "app_private"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'carryover', -v_row.carry, close_leave_year.period,
        null, null, v_key || ':carryover:' || close_leave_year.period::text, close_leave_year.period + 1);
      v_written := v_written + 2;
    end if;
    if v_row.balance - v_row.carry <> 0 and not "app_private"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':expiry:' || close_leave_year.period::text) then
      perform "app_private"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry), close_leave_year.period,
        null, null, v_key || ':expiry:' || close_leave_year.period::text);
      v_written := v_written + 1;
    end if;
  end loop;
  return v_written;
end;
$$;
revoke execute on function "app_private"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "app_private"."close_leave_year"(uuid, integer) to authenticated, service_role;

-- The working days (options.workingDays) from one date to another, inclusive.
create or replace function "app_private"."leave_working_days"(starts_on date, ends_on date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer
  from generate_series(leave_working_days.starts_on, leave_working_days.ends_on, interval '1 day') d
  where extract(isodow from d)::integer = any (array[1, 2, 3, 4, 5])
$$;
revoke execute on function "app_private"."leave_working_days"(date, date) from public, anon;
grant execute on function "app_private"."leave_working_days"(date, date) to authenticated, service_role;

-- Creates or updates a leave type by key.
create or replace function "app_private"."save_leave_type"(tenant uuid, key text, name text, unit text default 'days', paid boolean default true, tracked boolean default true, allowance numeric default null, carryover_max numeric default null, color text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."leave_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_leave_type.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to manage leave types' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  insert into "app_private"."leave_types" ("tenant_id", "key", "name", "unit", "paid", "tracked", "allowance", "carryover_max", "color")
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
revoke execute on function "app_private"."save_leave_type"(uuid, text, text, text, boolean, boolean, numeric, numeric, text) from public, anon;
grant execute on function "app_private"."save_leave_type"(uuid, text, text, text, boolean, boolean, numeric, numeric, text) to authenticated, service_role;

-- Hides a type from new requests; its requests and ledger stay.
create or replace function "app_private"."archive_leave_type"(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."leave_types"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."leave_types" x where x."id" = archive_leave_type.type_id for update;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then
    raise exception 'not allowed to manage leave types' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "app_private"."leave_types" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'paid', v_row."paid", 'tracked', v_row."tracked", 'allowance', v_row."allowance"::text, 'carryoverMax', v_row."carryover_max"::text, 'color', v_row."color", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."archive_leave_type"(uuid) from public, anon;
grant execute on function "app_private"."archive_leave_type"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_leave_types"(tenant uuid, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'paid', x."paid", 'tracked', x."tracked", 'allowance', x."allowance"::text, 'carryoverMax', x."carryover_max"::text, 'color', x."color", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "app_private"."leave_types" x
  where x."tenant_id" = list_leave_types.tenant
    and (coalesce(list_leave_types.archived, false) or x."archived_at" is null)
$$;
revoke execute on function "app_private"."list_leave_types"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_leave_types"(uuid, boolean) to authenticated, service_role;

-- Asks for leave and opens its approval. A day type books working days
-- (half a day for a morning or afternoon); an hours type books hours.
-- Without options.allowNegative the request can't exceed the balance of
-- the period it starts in. fields: the extra columns to set.
drop function if exists "app_private"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb);
create or replace function "app_private"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_type "app_private"."leave_types"%rowtype;
  v_partial text := coalesce(request_leave.partial, 'full');
  v_amount numeric;
  v_row "app_private"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', request_leave.tenant, 'leave.request'), false) then
    raise exception 'not allowed to request leave here' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "app_private"."leave_types" x
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
    v_amount := "app_private"."leave_working_days"(request_leave.starts_on, request_leave.ends_on)
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  if v_amount <= 0 then
    raise exception 'the request covers no working days' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leave:' || request_leave.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "app_private"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = request_leave.tenant and r."user_id" = v_me
      and r."cancelled_at" is null and (r."approved_at" is not null or p."status" = 'pending')
      and daterange(r."starts_on", r."ends_on", '[]') && daterange(request_leave.starts_on, request_leave.ends_on, '[]')
      and not (r."partial" = 'morning' and v_partial = 'afternoon')
      and not (r."partial" = 'afternoon' and v_partial = 'morning')
  ) then
    raise exception 'this overlaps another leave request' using errcode = '23P01', hint = 'LEAVE_OVERLAP';
  end if;
  if v_type."tracked" and "app_private"."leave_available"(request_leave.tenant, v_me, v_type."id", extract(year from request_leave.starts_on)::integer) < v_amount then
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
  insert into "app_private"."leave_requests" ("tenant_id", "user_id", "type_id", "starts_on", "ends_on", "partial", "amount", "note")
  values (request_leave.tenant, v_me, v_type."id", request_leave.starts_on, request_leave.ends_on, v_partial, v_amount, nullif(trim(request_leave.note), ''))
  returning * into v_row;
  v_request := "better_supabase"."open_approval"(
    request_leave.tenant, 'leave_request', v_row."id"::text, 'approve',
    '{"steps":[{"approvers":{"permission":"leave.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
    jsonb_build_object('userId', v_me, 'typeId', v_type."id", 'type', v_type."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_amount::text, 'unit', v_type."unit")
  );
  update "app_private"."leave_requests" x set "approval_id" = (v_request ->> 'id')::uuid
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."request_leave"(uuid, uuid, date, date, text, numeric, text) from public, anon;
grant execute on function "app_private"."request_leave"(uuid, uuid, date, date, text, numeric, text) to authenticated, service_role;

-- Books the leave once the approval is final: approved_at and, for a
-- tracked type, a taken entry. Approvals calls it; it isn't granted to anyone.
create or replace function "app_private"."approve_leave_request"(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."leave_requests"%rowtype;
begin
  update "app_private"."leave_requests" x set "approved_at" = now(), "updated_at" = now()
    where x."id" = approve_leave_request.request_id and x."approved_at" is null and x."cancelled_at" is null
    returning * into v_row;
  if not found then
    return;
  end if;
  perform "app_private"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
  from "app_private"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  null;
end;
$$;
revoke execute on function "app_private"."approve_leave_request"(uuid) from public, anon, authenticated;

-- Cancels a request: the requester before it starts, or a manager any
-- time. A pending approval is cancelled with it; approved leave goes back
-- to the balance.
create or replace function "app_private"."cancel_leave_request"(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_manager boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."leave_requests" x where x."id" = cancel_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  v_manager := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false);
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
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
    perform "app_private"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "app_private"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "app_private"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."cancel_leave_request"(uuid) from public, anon;
grant execute on function "app_private"."cancel_leave_request"(uuid) to authenticated, service_role;

-- Requests that overlap a date range, earliest first: the caller's, or
-- everyone's with the read permission.
create or replace function "app_private"."list_leave_requests"(tenant uuid, user_id uuid default null, status text default null, starts date default null, ends date default null, everyone boolean default false, page_size integer default 100)
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
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', r."note", 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at") as item, r."starts_on" as starts, r."created_at" as created
    from "app_private"."leave_requests" r
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
revoke execute on function "app_private"."list_leave_requests"(uuid, uuid, text, date, date, boolean, integer) from public, anon;
grant execute on function "app_private"."list_leave_requests"(uuid, uuid, text, date, date, boolean, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."leave_types";
drop policy if exists bsb_tenant_scope_select on "app_private"."leave_types";
create policy bsb_tenant_scope_select on "app_private"."leave_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."leave_types";
create policy bsb_tenant_scope_insert on "app_private"."leave_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."leave_types";
create policy bsb_tenant_scope_update on "app_private"."leave_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."leave_types";
create policy bsb_tenant_scope_delete on "app_private"."leave_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."leave_requests";
drop policy if exists bsb_tenant_scope_select on "app_private"."leave_requests";
create policy bsb_tenant_scope_select on "app_private"."leave_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."leave_requests";
create policy bsb_tenant_scope_insert on "app_private"."leave_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."leave_requests";
create policy bsb_tenant_scope_update on "app_private"."leave_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."leave_requests";
create policy bsb_tenant_scope_delete on "app_private"."leave_requests" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block-data leave
-- @bsb-hash sha256:469ff4c4bc15d1e8ee80aa4c07064294ad84d3ad846f25e7bfca61c713c861e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block leave@3 managed
-- @bsb-hash sha256:d903e7d21b7eaf32163d1170c867963d4a5eac1e4179d5d803216069ad610e71
-- Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
revoke all on "better_supabase"."leave_types" from public, anon, authenticated;
grant select on "better_supabase"."leave_types" to authenticated;
grant all on "better_supabase"."leave_types" to service_role;
drop policy if exists leave_types_read on "better_supabase"."leave_types";
create policy leave_types_read on "better_supabase"."leave_types"
  for select to authenticated
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
create index if not exists "leave_requests_user_idx" on "better_supabase"."leave_requests" ("tenant_id", "user_id", "starts_on" desc);
create index if not exists "leave_requests_dates_idx" on "better_supabase"."leave_requests" ("tenant_id", "starts_on", "ends_on");
create index if not exists "leave_requests_approval_idx" on "better_supabase"."leave_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "leave_requests_type_idx" on "better_supabase"."leave_requests" ("tenant_id", "type_id");
alter table "better_supabase"."leave_requests" enable row level security;
revoke all on "better_supabase"."leave_requests" from public, anon, authenticated;
grant select on "better_supabase"."leave_requests" to authenticated;
grant all on "better_supabase"."leave_requests" to service_role;
drop policy if exists leave_requests_read on "better_supabase"."leave_requests";
create policy leave_requests_read on "better_supabase"."leave_requests"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));


-- Posts one leave movement to a member's account of a type and period:
-- against the type's taken account for taken leave, the member's account
-- of to_period for a carryover, else the type's pool. Returns the ledger
-- transaction; with a key a second post returns the first.
create or replace function "better_supabase"."leave_post"(tenant uuid, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_account uuid;
  v_counter uuid;
  v_amount bigint := round(leave_post.amount * 100);
begin
  select t."unit" into v_unit from "better_supabase"."leave_types" t where t."id" = leave_post.type_id;
  v_account := "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period));
  v_counter := case
    when leave_post.to_period is not null then
      "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.to_period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.to_period))
    else "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave_pool',
      'leave:' || leave_post.type_id::text || case when leave_post.kind = 'taken' then ':taken' else ':pool' end,
      case when leave_post.kind = 'taken' then 'Leave taken' else 'Leave pool' end, v_unit, 2::smallint,
      'leave-types', leave_post.type_id::text, null, true, 'leave.read', 'leave', null)
  end;
  return "better_supabase"."ledger_post"(leave_post.tenant, 'leave.' || leave_post.kind,
    jsonb_build_array(
      jsonb_build_object('account', v_account, 'amount', v_amount),
      jsonb_build_object('account', v_counter, 'amount', -v_amount)),
    case when leave_post.request_id is not null then 'leave-requests' end, leave_post.request_id::text,
    nullif(trim(leave_post.note), ''),
    case when leave_post.key is not null then 'leave:' || leave_post.user_id::text || ':' || leave_post.type_id::text || ':' || leave_post.key end,
    null,
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period, 'kind', leave_post.kind));
end;
$$;
revoke execute on function "better_supabase"."leave_post"(uuid, uuid, uuid, text, numeric, integer, uuid, text, text, integer) from public, anon, authenticated;

-- Whether a member already has the leave movement with this key.
create or replace function "better_supabase"."leave_posted"(tenant uuid, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from "better_supabase"."ledger_transactions" r where r."tenant_id" = leave_posted.tenant
    and r."idempotency_key" = 'leave:' || leave_posted.user_id::text || ':' || leave_posted.type_id::text || ':' || leave_posted.key)
$$;
revoke execute on function "better_supabase"."leave_posted"(uuid, uuid, uuid, text) from public, anon, authenticated;

-- A member's balance of one type for one period: the account's balance,
-- minus the requests still waiting for approval.
create or replace function "better_supabase"."leave_available"(tenant uuid, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b."balance"::numeric / 100 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
      where x."tenant_id" = leave_available.tenant and x."code" = 'leave:' || leave_available.type_id::text || ':' || leave_available.user_id::text || ':' || leave_available.period::text), 0)
    - coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_available.tenant and r."user_id" = leave_available.user_id
        and r."type_id" = leave_available.type_id and extract(year from r."starts_on")::integer = leave_available.period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0)
$$;
revoke execute on function "better_supabase"."leave_available"(uuid, uuid, uuid, integer) from public, anon, authenticated;

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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_user is null then
    raise exception 'name user_id' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t."id", 'key', t."key", 'name', t."name", 'unit', t."unit",
      'userId', v_user, 'period', v_period,
      'granted', (coalesce(b.granted, 0)::numeric / 100)::numeric(10, 2)::text,
      'taken', (coalesce(b.taken, 0)::numeric / 100)::numeric(10, 2)::text,
      'pending', w.pending::numeric(10, 2)::text,
      'available', (coalesce(b.total, 0)::numeric / 100 - w.pending)::numeric(10, 2)::text
    ) order by t."name"), '[]'::jsonb) into v_rows
  from "better_supabase"."leave_types" t
  left join lateral (
    select sum(y."amount") filter (where r."kind" <> 'leave.taken') as granted,
      -sum(y."amount") filter (where r."kind" = 'leave.taken') as taken,
      sum(y."amount") as total
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."tenant_id" = leave_balances.tenant and x."code" = 'leave:' || t."id"::text || ':' || v_user::text || ':' || v_period::text
  ) b on true
  cross join lateral (
    select coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_balances.tenant and r."user_id" = v_user
        and r."type_id" = t."id" and extract(year from r."starts_on")::integer = v_period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0) as pending
  ) w
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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") order by y."created_at" desc, y."id" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where x."tenant_id" = leave_ledger_entries.tenant and x."owner_id" = v_user
    and (leave_ledger_entries.period is null or (x."metadata" ->> 'period')::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x."holder_id" = leave_ledger_entries.type_id::text);
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
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;
begin
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
  v_transaction := "better_supabase"."leave_post"(adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y."id", jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") into v_entry, v_row
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where y."transaction_id" = v_transaction and x."owner_id" = adjust_leave_balance.user_id;
  null;
  return v_row;
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
  v_user uuid;
  v_count integer := 0;
begin
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
  for v_user in
    select m."user_id" from "better_supabase"."memberships" m
    where m."organization_id" = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m."user_id" = any (accrue_leave.user_ids))
  loop
    continue when accrue_leave.idempotency_key is not null
      and "better_supabase"."leave_posted"(accrue_leave.tenant, v_user, v_type."id", accrue_leave.idempotency_key);
    perform "better_supabase"."leave_post"(accrue_leave.tenant, v_user, v_type."id", 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from current_date)::integer), null, accrue_leave.note, accrue_leave.idempotency_key);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries on members' accounts it wrote.
create or replace function "better_supabase"."close_leave_year"(tenant uuid, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_row record;
  v_written integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_leave_year.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to close leave periods' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if close_leave_year.period is null then
    raise exception 'name the period to close' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_row in
    select x."owner_id" as user_id, t."id" as type_id, b."balance"::numeric / 100 as balance,
      least(b."balance"::numeric / 100, coalesce(t."carryover_max", b."balance"::numeric / 100)) as carry
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
    join "better_supabase"."leave_types" t on t."id"::text = x."holder_id" and t."tracked"
    where x."tenant_id" = close_leave_year.tenant and x."managed_by" = 'leave' and x."kind" = 'leave'
      and (x."metadata" ->> 'period')::integer = close_leave_year.period and b."balance" > 0
  loop
    if v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':carryover:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'carryover', -v_row.carry, close_leave_year.period,
        null, null, v_key || ':carryover:' || close_leave_year.period::text, close_leave_year.period + 1);
      v_written := v_written + 2;
    end if;
    if v_row.balance - v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':expiry:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry), close_leave_year.period,
        null, null, v_key || ':expiry:' || close_leave_year.period::text);
      v_written := v_written + 1;
    end if;
  end loop;
  return v_written;
end;
$$;
revoke execute on function "better_supabase"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."close_leave_year"(uuid, integer) to authenticated, service_role;

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
drop function if exists "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb);
create or replace function "better_supabase"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null)
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) from public, anon;
grant execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) to authenticated, service_role;

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
  perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
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
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
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
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', r."note", 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at") as item, r."starts_on" as starts, r."created_at" as created
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
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
create policy bsb_tenant_scope_select on "better_supabase"."leave_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
create policy bsb_tenant_scope_update on "better_supabase"."leave_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_select on "better_supabase"."leave_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_update on "better_supabase"."leave_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_requests" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.leave.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb);

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

create or replace function "api"."leave_balances"(tenant uuid, user_id uuid default null, period integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."leave_balances"($1, $2, $3) $$;
revoke execute on function "api"."leave_balances"(uuid, uuid, integer) from public, anon;
grant execute on function "api"."leave_balances"(uuid, uuid, integer) to authenticated, service_role;

create or replace function "api"."leave_ledger_entries"(tenant uuid, user_id uuid default null, period integer default null, type_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."leave_ledger_entries"($1, $2, $3, $4) $$;
revoke execute on function "api"."leave_ledger_entries"(uuid, uuid, integer, uuid) from public, anon;
grant execute on function "api"."leave_ledger_entries"(uuid, uuid, integer, uuid) to authenticated, service_role;

create or replace function "api"."adjust_leave_balance"(tenant uuid, user_id uuid, type_id uuid, amount numeric, period integer default null, kind text default 'adjustment', note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."adjust_leave_balance"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."adjust_leave_balance"(uuid, uuid, uuid, numeric, integer, text, text) from public, anon;
grant execute on function "api"."adjust_leave_balance"(uuid, uuid, uuid, numeric, integer, text, text) to authenticated, service_role;

create or replace function "api"."accrue_leave"(tenant uuid, type_id uuid, amount numeric default null, period integer default null, user_ids uuid[] default null, idempotency_key text default null, note text default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."accrue_leave"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "api"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

create or replace function "api"."close_leave_year"(tenant uuid, period integer)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_leave_year"($1, $2) $$;
revoke execute on function "api"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "api"."close_leave_year"(uuid, integer) to authenticated, service_role;

create or replace function "api"."leave_working_days"(starts_on date, ends_on date)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."leave_working_days"($1, $2) $$;
revoke execute on function "api"."leave_working_days"(date, date) from public, anon;
grant execute on function "api"."leave_working_days"(date, date) to authenticated, service_role;

create or replace function "api"."save_leave_type"(tenant uuid, key text, name text, unit text default 'days', paid boolean default true, tracked boolean default true, allowance numeric default null, carryover_max numeric default null, color text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_leave_type"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."save_leave_type"(uuid, text, text, text, boolean, boolean, numeric, numeric, text) from public, anon;
grant execute on function "api"."save_leave_type"(uuid, text, text, text, boolean, boolean, numeric, numeric, text) to authenticated, service_role;

create or replace function "api"."archive_leave_type"(type_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_leave_type"($1) $$;
revoke execute on function "api"."archive_leave_type"(uuid) from public, anon;
grant execute on function "api"."archive_leave_type"(uuid) to authenticated, service_role;

create or replace function "api"."list_leave_types"(tenant uuid, archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_leave_types"($1, $2) $$;
revoke execute on function "api"."list_leave_types"(uuid, boolean) from public, anon;
grant execute on function "api"."list_leave_types"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."request_leave"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."request_leave"(uuid, uuid, date, date, text, numeric, text) from public, anon;
grant execute on function "api"."request_leave"(uuid, uuid, date, date, text, numeric, text) to authenticated, service_role;

create or replace function "api"."cancel_leave_request"(request_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_leave_request"($1) $$;
revoke execute on function "api"."cancel_leave_request"(uuid) from public, anon;
grant execute on function "api"."cancel_leave_request"(uuid) to authenticated, service_role;

create or replace function "api"."list_leave_requests"(tenant uuid, user_id uuid default null, status text default null, starts date default null, ends date default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_leave_requests"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_leave_requests"(uuid, uuid, text, date, date, boolean, integer) from public, anon;
grant execute on function "api"."list_leave_requests"(uuid, uuid, text, date, date, boolean, integer) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block-data leave
-- @bsb-hash sha256:469ff4c4bc15d1e8ee80aa4c07064294ad84d3ad846f25e7bfca61c713c861e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block leave@3 managed
-- @bsb-hash sha256:039e6474947adb934040bfa85f2cffc7071147e7a8243cdf14f3ff464573bb5c
-- Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.leave_types is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."leave_types" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."leave_types" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."leave_types" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."leave_types" add column if not exists "name" text check (length("name") between 1 and 100);
alter table "better_supabase"."leave_types" add column if not exists "unit" text not null default 'days' check ("unit" in ('days', 'hours'));
alter table "better_supabase"."leave_types" add column if not exists "paid" boolean not null default true;
alter table "better_supabase"."leave_types" add column if not exists "tracked" boolean not null default true;
alter table "better_supabase"."leave_types" add column if not exists "allowance" numeric(8, 2) check ("allowance" is null or "allowance" >= 0);
alter table "better_supabase"."leave_types" add column if not exists "carryover_max" numeric(8, 2) check ("carryover_max" is null or "carryover_max" >= 0);
alter table "better_supabase"."leave_types" add column if not exists "color" text check ("color" is null or "color" ~ '^#[0-9a-fA-F]{6}$');
alter table "better_supabase"."leave_types" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."leave_types" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."leave_types" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "leave_types_tenant_id_key_key" on "better_supabase"."leave_types" ("tenant_id", "key");
create unique index if not exists "leave_types_tenant_id_id_key" on "better_supabase"."leave_types" ("tenant_id", "id");
alter table "better_supabase"."leave_types" enable row level security;
grant select on "better_supabase"."leave_types" to authenticated;
grant all on "better_supabase"."leave_types" to service_role;
drop policy if exists bsb_leave_types_select on "better_supabase"."leave_types";
create policy bsb_leave_types_select on "better_supabase"."leave_types"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));

-- better_supabase.leave_requests is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."leave_requests" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."leave_requests" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."leave_requests" add column if not exists "user_id" uuid;
alter table "better_supabase"."leave_requests" add column if not exists "type_id" uuid;
alter table "better_supabase"."leave_requests" add column if not exists "starts_on" date;
alter table "better_supabase"."leave_requests" add column if not exists "ends_on" date;
alter table "better_supabase"."leave_requests" add column if not exists "partial" text not null default 'full' check ("partial" in ('full', 'morning', 'afternoon', 'hours'));
alter table "better_supabase"."leave_requests" add column if not exists "amount" numeric(8, 2) check ("amount" > 0);
alter table "better_supabase"."leave_requests" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."leave_requests" add column if not exists "approval_id" uuid references "better_supabase"."approval_requests" ("id") on delete set null;
alter table "better_supabase"."leave_requests" add column if not exists "approved_at" timestamptz;
alter table "better_supabase"."leave_requests" add column if not exists "cancelled_at" timestamptz;
alter table "better_supabase"."leave_requests" add column if not exists "cancelled_by" uuid;
alter table "better_supabase"."leave_requests" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."leave_requests" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "leave_requests_user_idx" on "better_supabase"."leave_requests" ("tenant_id", "user_id", "starts_on" desc);
create index if not exists "leave_requests_dates_idx" on "better_supabase"."leave_requests" ("tenant_id", "starts_on", "ends_on");
create index if not exists "leave_requests_approval_idx" on "better_supabase"."leave_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "leave_requests_type_idx" on "better_supabase"."leave_requests" ("tenant_id", "type_id");
alter table "better_supabase"."leave_requests" enable row level security;
grant select on "better_supabase"."leave_requests" to authenticated;
grant all on "better_supabase"."leave_requests" to service_role;
drop policy if exists bsb_leave_requests_select on "better_supabase"."leave_requests";
create policy bsb_leave_requests_select on "better_supabase"."leave_requests"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')));


-- Posts one leave movement to a member's account of a type and period:
-- against the type's taken account for taken leave, the member's account
-- of to_period for a carryover, else the type's pool. Returns the ledger
-- transaction; with a key a second post returns the first.
create or replace function "better_supabase"."leave_post"(tenant uuid, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_account uuid;
  v_counter uuid;
  v_amount bigint := round(leave_post.amount * 100);
begin
  select t."unit" into v_unit from "better_supabase"."leave_types" t where t."id" = leave_post.type_id;
  v_account := "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period));
  v_counter := case
    when leave_post.to_period is not null then
      "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.to_period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.to_period))
    else "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave_pool',
      'leave:' || leave_post.type_id::text || case when leave_post.kind = 'taken' then ':taken' else ':pool' end,
      case when leave_post.kind = 'taken' then 'Leave taken' else 'Leave pool' end, v_unit, 2::smallint,
      'leave-types', leave_post.type_id::text, null, true, 'leave.read', 'leave', null)
  end;
  return "better_supabase"."ledger_post"(leave_post.tenant, 'leave.' || leave_post.kind,
    jsonb_build_array(
      jsonb_build_object('account', v_account, 'amount', v_amount),
      jsonb_build_object('account', v_counter, 'amount', -v_amount)),
    case when leave_post.request_id is not null then 'leave-requests' end, leave_post.request_id::text,
    nullif(trim(leave_post.note), ''),
    case when leave_post.key is not null then 'leave:' || leave_post.user_id::text || ':' || leave_post.type_id::text || ':' || leave_post.key end,
    null,
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period, 'kind', leave_post.kind));
end;
$$;
revoke execute on function "better_supabase"."leave_post"(uuid, uuid, uuid, text, numeric, integer, uuid, text, text, integer) from public, anon, authenticated;

-- Whether a member already has the leave movement with this key.
create or replace function "better_supabase"."leave_posted"(tenant uuid, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from "better_supabase"."ledger_transactions" r where r."tenant_id" = leave_posted.tenant
    and r."idempotency_key" = 'leave:' || leave_posted.user_id::text || ':' || leave_posted.type_id::text || ':' || leave_posted.key)
$$;
revoke execute on function "better_supabase"."leave_posted"(uuid, uuid, uuid, text) from public, anon, authenticated;

-- A member's balance of one type for one period: the account's balance,
-- minus the requests still waiting for approval.
create or replace function "better_supabase"."leave_available"(tenant uuid, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b."balance"::numeric / 100 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
      where x."tenant_id" = leave_available.tenant and x."code" = 'leave:' || leave_available.type_id::text || ':' || leave_available.user_id::text || ':' || leave_available.period::text), 0)
    - coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_available.tenant and r."user_id" = leave_available.user_id
        and r."type_id" = leave_available.type_id and extract(year from r."starts_on")::integer = leave_available.period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0)
$$;
revoke execute on function "better_supabase"."leave_available"(uuid, uuid, uuid, integer) from public, anon, authenticated;

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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_user is null then
    raise exception 'name user_id' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t."id", 'key', t."key", 'name', t."name", 'unit', t."unit",
      'userId', v_user, 'period', v_period,
      'granted', (coalesce(b.granted, 0)::numeric / 100)::numeric(10, 2)::text,
      'taken', (coalesce(b.taken, 0)::numeric / 100)::numeric(10, 2)::text,
      'pending', w.pending::numeric(10, 2)::text,
      'available', (coalesce(b.total, 0)::numeric / 100 - w.pending)::numeric(10, 2)::text
    ) order by t."name"), '[]'::jsonb) into v_rows
  from "better_supabase"."leave_types" t
  left join lateral (
    select sum(y."amount") filter (where r."kind" <> 'leave.taken') as granted,
      -sum(y."amount") filter (where r."kind" = 'leave.taken') as taken,
      sum(y."amount") as total
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."tenant_id" = leave_balances.tenant and x."code" = 'leave:' || t."id"::text || ':' || v_user::text || ':' || v_period::text
  ) b on true
  cross join lateral (
    select coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."tenant_id" = leave_balances.tenant and r."user_id" = v_user
        and r."type_id" = t."id" and extract(year from r."starts_on")::integer = v_period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0) as pending
  ) w
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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") order by y."created_at" desc, y."id" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where x."tenant_id" = leave_ledger_entries.tenant and x."owner_id" = v_user
    and (leave_ledger_entries.period is null or (x."metadata" ->> 'period')::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x."holder_id" = leave_ledger_entries.type_id::text);
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
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;
begin
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
  v_transaction := "better_supabase"."leave_post"(adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y."id", jsonb_build_object('id', y."id", 'organizationId', x."tenant_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") into v_entry, v_row
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where y."transaction_id" = v_transaction and x."owner_id" = adjust_leave_balance.user_id;
  null;
  return v_row;
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
  v_user uuid;
  v_count integer := 0;
begin
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
  for v_user in
    select m."user_id" from "better_supabase"."memberships" m
    where m."organization_id" = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m."user_id" = any (accrue_leave.user_ids))
  loop
    continue when accrue_leave.idempotency_key is not null
      and "better_supabase"."leave_posted"(accrue_leave.tenant, v_user, v_type."id", accrue_leave.idempotency_key);
    perform "better_supabase"."leave_post"(accrue_leave.tenant, v_user, v_type."id", 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from current_date)::integer), null, accrue_leave.note, accrue_leave.idempotency_key);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries on members' accounts it wrote.
create or replace function "better_supabase"."close_leave_year"(tenant uuid, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_row record;
  v_written integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_leave_year.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to close leave periods' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if close_leave_year.period is null then
    raise exception 'name the period to close' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_row in
    select x."owner_id" as user_id, t."id" as type_id, b."balance"::numeric / 100 as balance,
      least(b."balance"::numeric / 100, coalesce(t."carryover_max", b."balance"::numeric / 100)) as carry
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
    join "better_supabase"."leave_types" t on t."id"::text = x."holder_id" and t."tracked"
    where x."tenant_id" = close_leave_year.tenant and x."managed_by" = 'leave' and x."kind" = 'leave'
      and (x."metadata" ->> 'period')::integer = close_leave_year.period and b."balance" > 0
  loop
    if v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':carryover:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'carryover', -v_row.carry, close_leave_year.period,
        null, null, v_key || ':carryover:' || close_leave_year.period::text, close_leave_year.period + 1);
      v_written := v_written + 2;
    end if;
    if v_row.balance - v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':expiry:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry), close_leave_year.period,
        null, null, v_key || ':expiry:' || close_leave_year.period::text);
      v_written := v_written + 1;
    end if;
  end loop;
  return v_written;
end;
$$;
revoke execute on function "better_supabase"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."close_leave_year"(uuid, integer) to authenticated, service_role;

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
  values (save_leave_type.tenant, save_leave_type.key, save_leave_type.name, better_supabase.as_column_type(coalesce(save_leave_type.unit, 'days'), (null::"better_supabase"."leave_types")."unit"), coalesce(save_leave_type.paid, true), coalesce(save_leave_type.tracked, true), save_leave_type.allowance, save_leave_type.carryover_max, save_leave_type.color)
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
drop function if exists "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb);
create or replace function "better_supabase"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null)
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
  values (request_leave.tenant, v_me, v_type."id", request_leave.starts_on, request_leave.ends_on, better_supabase.as_column_type(v_partial, (null::"better_supabase"."leave_requests")."partial"), v_amount, nullif(trim(request_leave.note), ''))
  returning * into v_row;
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) from public, anon;
grant execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) to authenticated, service_role;

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
  perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
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
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
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
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', r."note", 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at") as item, r."starts_on" as starts, r."created_at" as created
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
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
create policy bsb_tenant_scope_select on "better_supabase"."leave_types" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leave.request')) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_types" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
create policy bsb_tenant_scope_update on "better_supabase"."leave_types" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_types" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_select on "better_supabase"."leave_requests" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_requests" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_update on "better_supabase"."leave_requests" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_requests" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block-data leave
-- @bsb-hash sha256:469ff4c4bc15d1e8ee80aa4c07064294ad84d3ad846f25e7bfca61c713c861e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block leave@3 managed
-- @bsb-hash sha256:6cf1bc362ef4271e52b7af268d87faf0adcb3274a22e48afe8834f3aa656d687
-- Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."leave_types" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
  unique ("org_id", "key"),
  unique ("org_id", "id")
);
alter table "better_supabase"."leave_types" enable row level security;
revoke all on "better_supabase"."leave_types" from public, anon, authenticated;
grant select on "better_supabase"."leave_types" to authenticated;
grant all on "better_supabase"."leave_types" to service_role;
drop policy if exists leave_types_read on "better_supabase"."leave_types";
create policy leave_types_read on "better_supabase"."leave_types"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('leave.request')) or "org_id" in (select better_supabase.tenant_ids_with('leave.read')));

create table if not exists "better_supabase"."leave_requests" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
  foreign key ("org_id", "type_id") references "better_supabase"."leave_types" ("org_id", "id") on delete restrict
);
create index if not exists "leave_requests_user_idx" on "better_supabase"."leave_requests" ("org_id", "user_id", "starts_on" desc);
create index if not exists "leave_requests_dates_idx" on "better_supabase"."leave_requests" ("org_id", "starts_on", "ends_on");
create index if not exists "leave_requests_approval_idx" on "better_supabase"."leave_requests" ("approval_id") where "approval_id" is not null;
create index if not exists "leave_requests_type_idx" on "better_supabase"."leave_requests" ("org_id", "type_id");
alter table "better_supabase"."leave_requests" enable row level security;
revoke all on "better_supabase"."leave_requests" from public, anon, authenticated;
grant select on "better_supabase"."leave_requests" to authenticated;
grant all on "better_supabase"."leave_requests" to service_role;
drop policy if exists leave_requests_read on "better_supabase"."leave_requests";
create policy leave_requests_read on "better_supabase"."leave_requests"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('leave.read')));


-- Posts one leave movement to a member's account of a type and period:
-- against the type's taken account for taken leave, the member's account
-- of to_period for a carryover, else the type's pool. Returns the ledger
-- transaction; with a key a second post returns the first.
create or replace function "better_supabase"."leave_post"(tenant uuid, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_account uuid;
  v_counter uuid;
  v_amount bigint := round(leave_post.amount * 100);
begin
  select t."unit" into v_unit from "better_supabase"."leave_types" t where t."id" = leave_post.type_id;
  v_account := "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period));
  v_counter := case
    when leave_post.to_period is not null then
      "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave', 'leave:' || leave_post.type_id::text || ':' || leave_post.user_id::text || ':' || leave_post.to_period::text, 'Leave', v_unit, 2::smallint,
    'leave-types', leave_post.type_id::text, leave_post.user_id, true, 'leave.read', 'leave',
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.to_period))
    else "better_supabase"."ledger_account_for"(leave_post.tenant, 'leave_pool',
      'leave:' || leave_post.type_id::text || case when leave_post.kind = 'taken' then ':taken' else ':pool' end,
      case when leave_post.kind = 'taken' then 'Leave taken' else 'Leave pool' end, v_unit, 2::smallint,
      'leave-types', leave_post.type_id::text, null, true, 'leave.read', 'leave', null)
  end;
  return "better_supabase"."ledger_post"(leave_post.tenant, 'leave.' || leave_post.kind,
    jsonb_build_array(
      jsonb_build_object('account', v_account, 'amount', v_amount),
      jsonb_build_object('account', v_counter, 'amount', -v_amount)),
    case when leave_post.request_id is not null then 'leave-requests' end, leave_post.request_id::text,
    nullif(trim(leave_post.note), ''),
    case when leave_post.key is not null then 'leave:' || leave_post.user_id::text || ':' || leave_post.type_id::text || ':' || leave_post.key end,
    null,
    jsonb_build_object('userId', leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period, 'kind', leave_post.kind));
end;
$$;
revoke execute on function "better_supabase"."leave_post"(uuid, uuid, uuid, text, numeric, integer, uuid, text, text, integer) from public, anon, authenticated;

-- Whether a member already has the leave movement with this key.
create or replace function "better_supabase"."leave_posted"(tenant uuid, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from "better_supabase"."ledger_transactions" r where r."org_id" = leave_posted.tenant
    and r."idempotency_key" = 'leave:' || leave_posted.user_id::text || ':' || leave_posted.type_id::text || ':' || leave_posted.key)
$$;
revoke execute on function "better_supabase"."leave_posted"(uuid, uuid, uuid, text) from public, anon, authenticated;

-- A member's balance of one type for one period: the account's balance,
-- minus the requests still waiting for approval.
create or replace function "better_supabase"."leave_available"(tenant uuid, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b."balance"::numeric / 100 from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
      where x."org_id" = leave_available.tenant and x."code" = 'leave:' || leave_available.type_id::text || ':' || leave_available.user_id::text || ':' || leave_available.period::text), 0)
    - coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."org_id" = leave_available.tenant and r."user_id" = leave_available.user_id
        and r."type_id" = leave_available.type_id and extract(year from r."starts_on")::integer = leave_available.period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0)
$$;
revoke execute on function "better_supabase"."leave_available"(uuid, uuid, uuid, integer) from public, anon, authenticated;

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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_balances.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_user is null then
    raise exception 'name user_id' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t."id", 'key', t."key", 'name', t."name", 'unit', t."unit",
      'userId', v_user, 'period', v_period,
      'granted', (coalesce(b.granted, 0)::numeric / 100)::numeric(10, 2)::text,
      'taken', (coalesce(b.taken, 0)::numeric / 100)::numeric(10, 2)::text,
      'pending', w.pending::numeric(10, 2)::text,
      'available', (coalesce(b.total, 0)::numeric / 100 - w.pending)::numeric(10, 2)::text
    ) order by t."name"), '[]'::jsonb) into v_rows
  from "better_supabase"."leave_types" t
  left join lateral (
    select sum(y."amount") filter (where r."kind" <> 'leave.taken') as granted,
      -sum(y."amount") filter (where r."kind" = 'leave.taken') as taken,
      sum(y."amount") as total
    from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
    where x."org_id" = leave_balances.tenant and x."code" = 'leave:' || t."id"::text || ':' || v_user::text || ':' || v_period::text
  ) b on true
  cross join lateral (
    select coalesce((select sum(r."amount") from "better_supabase"."leave_requests" r
      left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
      where r."org_id" = leave_balances.tenant and r."user_id" = v_user
        and r."type_id" = t."id" and extract(year from r."starts_on")::integer = v_period
        and r."cancelled_at" is null and r."approved_at" is null and p."status" = 'pending'), 0) as pending
  ) w
  where t."org_id" = leave_balances.tenant and t."tracked" and t."archived_at" is null;
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
    or (coalesce(v_user = auth.uid(), false) and coalesce(better_supabase.can('tenant', leave_ledger_entries.tenant, 'leave.request'), false))) then
    raise exception 'not allowed to read this member''s leave balance' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', x."org_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") order by y."created_at" desc, y."id" desc), '[]'::jsonb) into v_rows
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where x."org_id" = leave_ledger_entries.tenant and x."owner_id" = v_user
    and (leave_ledger_entries.period is null or (x."metadata" ->> 'period')::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x."holder_id" = leave_ledger_entries.type_id::text);
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
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', adjust_leave_balance.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to adjust leave balances' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if coalesce(adjust_leave_balance.kind, 'adjustment') not in ('grant', 'adjustment') then
    raise exception 'kind must be grant or adjustment' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if adjust_leave_balance.amount is null or adjust_leave_balance.amount = 0 then
    raise exception 'amount must not be zero' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."memberships" m where m."org_id" = adjust_leave_balance.tenant and m."user_id" = adjust_leave_balance.user_id) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."leave_types" t where t."id" = adjust_leave_balance.type_id and t."org_id" = adjust_leave_balance.tenant) then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  v_transaction := "better_supabase"."leave_post"(adjust_leave_balance.tenant, adjust_leave_balance.user_id, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y."id", jsonb_build_object('id', y."id", 'organizationId', x."org_id", 'userId', x."owner_id",
      'typeId', (x."metadata" ->> 'typeId')::uuid, 'kind', substr(r."kind", 7), 'amount', (y."amount"::numeric / 100)::numeric(10, 2)::text,
      'period', (x."metadata" ->> 'period')::integer,
      'requestId', case when r."reference_type" = 'leave-requests' then r."reference_id"::uuid end,
      'note', r."memo", 'createdAt', y."created_at") into v_entry, v_row
  from "better_supabase"."ledger_entries" y
    join "better_supabase"."ledger_accounts" x on x."id" = y."account_id" and x."managed_by" = 'leave' and x."kind" = 'leave'
    join "better_supabase"."ledger_transactions" r on r."id" = y."transaction_id"
  where y."transaction_id" = v_transaction and x."owner_id" = adjust_leave_balance.user_id;
  null;
  return v_row;
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
  v_user uuid;
  v_count integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', accrue_leave.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to accrue leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."leave_types" t where t."id" = accrue_leave.type_id and t."org_id" = accrue_leave.tenant;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  v_amount := coalesce(accrue_leave.amount, v_type."allowance");
  if v_amount is null or v_amount <= 0 then
    raise exception 'name an amount, or give the type an allowance' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_user in
    select m."user_id" from "better_supabase"."memberships" m
    where m."org_id" = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m."user_id" = any (accrue_leave.user_ids))
  loop
    continue when accrue_leave.idempotency_key is not null
      and "better_supabase"."leave_posted"(accrue_leave.tenant, v_user, v_type."id", accrue_leave.idempotency_key);
    perform "better_supabase"."leave_post"(accrue_leave.tenant, v_user, v_type."id", 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from current_date)::integer), null, accrue_leave.note, accrue_leave.idempotency_key);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."accrue_leave"(uuid, uuid, numeric, integer, uuid[], text, text) to authenticated, service_role;

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries on members' accounts it wrote.
create or replace function "better_supabase"."close_leave_year"(tenant uuid, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_row record;
  v_written integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', close_leave_year.tenant, 'leave.manage'), false)) then
    raise exception 'not allowed to close leave periods' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if close_leave_year.period is null then
    raise exception 'name the period to close' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  for v_row in
    select x."owner_id" as user_id, t."id" as type_id, b."balance"::numeric / 100 as balance,
      least(b."balance"::numeric / 100, coalesce(t."carryover_max", b."balance"::numeric / 100)) as carry
    from "better_supabase"."ledger_accounts" x
    join "better_supabase"."ledger_balances" b on b."account_id" = x."id"
    join "better_supabase"."leave_types" t on t."id"::text = x."holder_id" and t."tracked"
    where x."org_id" = close_leave_year.tenant and x."managed_by" = 'leave' and x."kind" = 'leave'
      and (x."metadata" ->> 'period')::integer = close_leave_year.period and b."balance" > 0
  loop
    if v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':carryover:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'carryover', -v_row.carry, close_leave_year.period,
        null, null, v_key || ':carryover:' || close_leave_year.period::text, close_leave_year.period + 1);
      v_written := v_written + 2;
    end if;
    if v_row.balance - v_row.carry <> 0 and not "better_supabase"."leave_posted"(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':expiry:' || close_leave_year.period::text) then
      perform "better_supabase"."leave_post"(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry), close_leave_year.period,
        null, null, v_key || ':expiry:' || close_leave_year.period::text);
      v_written := v_written + 1;
    end if;
  end loop;
  return v_written;
end;
$$;
revoke execute on function "better_supabase"."close_leave_year"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."close_leave_year"(uuid, integer) to authenticated, service_role;

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
  insert into "better_supabase"."leave_types" ("org_id", "key", "name", "unit", "paid", "tracked", "allowance", "carryover_max", "color")
  values (save_leave_type.tenant, save_leave_type.key, save_leave_type.name, coalesce(save_leave_type.unit, 'days'), coalesce(save_leave_type.paid, true), coalesce(save_leave_type.tracked, true), save_leave_type.allowance, save_leave_type.carryover_max, save_leave_type.color)
  on conflict ("org_id", "key") do update
    set "name" = excluded."name", "unit" = excluded."unit", "paid" = excluded."paid",
      "tracked" = excluded."tracked", "allowance" = excluded."allowance",
      "carryover_max" = excluded."carryover_max", "color" = excluded."color",
      "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'paid', v_row."paid", 'tracked', v_row."tracked", 'allowance', v_row."allowance"::text, 'carryoverMax', v_row."carryover_max"::text, 'color', v_row."color", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leave.manage'), false)) then
    raise exception 'not allowed to manage leave types' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "better_supabase"."leave_types" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'unit', v_row."unit", 'paid', v_row."paid", 'tracked', v_row."tracked", 'allowance', v_row."allowance"::text, 'carryoverMax', v_row."carryover_max"::text, 'color', v_row."color", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'unit', x."unit", 'paid', x."paid", 'tracked', x."tracked", 'allowance', x."allowance"::text, 'carryoverMax', x."carryover_max"::text, 'color', x."color", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."leave_types" x
  where x."org_id" = list_leave_types.tenant
    and (coalesce(list_leave_types.archived, false) or x."archived_at" is null)
$$;
revoke execute on function "better_supabase"."list_leave_types"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_leave_types"(uuid, boolean) to authenticated, service_role;

-- Asks for leave and opens its approval. A day type books working days
-- (half a day for a morning or afternoon); an hours type books hours.
-- Without options.allowNegative the request can't exceed the balance of
-- the period it starts in. fields: the extra columns to set.
drop function if exists "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text, jsonb);
create or replace function "better_supabase"."request_leave"(tenant uuid, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null)
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
    where x."id" = request_leave.type_id and x."org_id" = request_leave.tenant and x."archived_at" is null;
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
    where r."org_id" = request_leave.tenant and r."user_id" = v_me
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
  insert into "better_supabase"."leave_requests" ("org_id", "user_id", "type_id", "starts_on", "ends_on", "partial", "amount", "note")
  values (request_leave.tenant, v_me, v_type."id", request_leave.starts_on, request_leave.ends_on, v_partial, v_amount, nullif(trim(request_leave.note), ''))
  returning * into v_row;
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) from public, anon;
grant execute on function "better_supabase"."request_leave"(uuid, uuid, date, date, text, numeric, text) to authenticated, service_role;

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
  perform "better_supabase"."leave_post"(v_row."org_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
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
  v_manager := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leave.manage'), false);
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
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
    perform "better_supabase"."leave_post"(v_row."org_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."org_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', r."note", 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at") as item, r."starts_on" as starts, r."created_at" as created
    from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."org_id" = list_leave_requests.tenant
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
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_types";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_types";
create policy bsb_tenant_scope_select on "better_supabase"."leave_types" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('leave.request')) or "org_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_types";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_types" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_types";
create policy bsb_tenant_scope_update on "better_supabase"."leave_types" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_types";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_types" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."leave_requests";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_select on "better_supabase"."leave_requests" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('leave.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_insert on "better_supabase"."leave_requests" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_update on "better_supabase"."leave_requests" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."leave_requests";
create policy bsb_tenant_scope_delete on "better_supabase"."leave_requests" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_110_leave.sql
-- better-supabase module: leave
-- @bsb-block-data leave
-- @bsb-hash sha256:469ff4c4bc15d1e8ee80aa4c07064294ad84d3ad846f25e7bfca61c713c861e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leave', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
