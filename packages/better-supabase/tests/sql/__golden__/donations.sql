-- ==== alone: schema supabase/schemas/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block donations@2 managed
-- @bsb-hash sha256:5f64d13b21184cf10e675ef78dd27ef298b1673fa00065f54a3c5be295ecea3a
-- Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Donations: gifts and pledges from donors (registered subjects) to funds
-- and campaigns, each posted gift on the ledger, and numbered tax receipts.

-- A fund or campaign gifts go to; goal is in minor units of currency.
create table if not exists "better_supabase"."donation_funds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'fund' check ("kind" in ('fund', 'campaign')),
  "goal" bigint check ("goal" is null or "goal" > 0),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "starts_on" date,
  "ends_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check ("goal" is null or "currency" is not null),
  check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on")
);
alter table "better_supabase"."donation_funds" enable row level security;
revoke all on "better_supabase"."donation_funds" from public, anon, authenticated;
grant select on "better_supabase"."donation_funds" to authenticated;
grant all on "better_supabase"."donation_funds" to service_role;
drop policy if exists "donation_funds_read" on "better_supabase"."donation_funds";
create policy donation_funds_read on "better_supabase"."donation_funds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A recurring gift: amount every period of frequency, charged through the
-- payments provider when provider is set, recorded by hand otherwise.
create table if not exists "better_supabase"."pledges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "starts_on" date not null,
  "ends_on" date,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'ended')),
  "provider" text,
  "provider_customer" text,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "better_supabase"."donation_funds" ("tenant_id", "id") on delete restrict,
  check ("ends_on" is null or "ends_on" > "starts_on")
);
create index if not exists "pledges_tenant_idx" on "better_supabase"."pledges" ("tenant_id", "status");
create index if not exists "pledges_donor_idx" on "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id");
create index if not exists "pledges_fund_idx" on "better_supabase"."pledges" ("tenant_id", "fund_id") where "fund_id" is not null;
alter table "better_supabase"."pledges" enable row level security;
revoke all on "better_supabase"."pledges" from public, anon, authenticated;
grant select on "better_supabase"."pledges" to authenticated;
grant all on "better_supabase"."pledges" to service_role;
drop policy if exists "pledges_read" on "better_supabase"."pledges";
create policy pledges_read on "better_supabase"."pledges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A tax receipt: one gift, or a donor's posted gifts in a year and currency.
create table if not exists "better_supabase"."donation_receipts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "sequence" bigint not null,
  "number" text not null,
  "kind" text not null check ("kind" in ('gift', 'yearly')),
  "year" integer not null,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null,
  "issued_at" timestamptz not null default now(),
  "voided_at" timestamptz,
  "void_reason" text check ("void_reason" is null or length("void_reason") <= 2000),
  unique ("tenant_id", "number")
);
create index if not exists "donation_receipts_donor_idx" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year");
create unique index if not exists "donation_receipts_yearly_key" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year", "currency")
  where "kind" = 'yearly' and "voided_at" is null;
alter table "better_supabase"."donation_receipts" enable row level security;
revoke all on "better_supabase"."donation_receipts" from public, anon, authenticated;
grant select on "better_supabase"."donation_receipts" to authenticated;
grant all on "better_supabase"."donation_receipts" to service_role;
drop policy if exists "donation_receipts_read" on "better_supabase"."donation_receipts";
create policy donation_receipts_read on "better_supabase"."donation_receipts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

create table if not exists "better_supabase"."donations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "pledge_id" uuid references "better_supabase"."pledges" ("id") on delete set null,
  -- The pledge period this gift pays; unique per pledge.
  "period_start" date,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "received_on" date not null default current_date,
  "method" text check ("method" is null or length("method") <= 40),
  "status" text not null default 'pending' check ("status" in ('pending', 'posted', 'failed', 'refunded')),
  "provider" text,
  "payment_reference" text,
  "transaction_id" uuid,
  "refund_transaction_id" uuid,
  "receipt_id" uuid references "better_supabase"."donation_receipts" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "better_supabase"."donation_funds" ("tenant_id", "id") on delete restrict,
  unique ("pledge_id", "period_start")
);
create index if not exists "donations_tenant_idx" on "better_supabase"."donations" ("tenant_id", "received_on" desc);
create index if not exists "donations_donor_idx" on "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "received_on");
create index if not exists "donations_fund_idx" on "better_supabase"."donations" ("tenant_id", "fund_id") where "fund_id" is not null;
create index if not exists "donations_receipt_idx" on "better_supabase"."donations" ("receipt_id") where "receipt_id" is not null;
create index if not exists "donations_transaction_idx" on "better_supabase"."donations" ("transaction_id") where "transaction_id" is not null;
create index if not exists "donations_refund_idx" on "better_supabase"."donations" ("refund_transaction_id") where "refund_transaction_id" is not null;
create unique index if not exists "donations_payment_key" on "better_supabase"."donations" ("provider", "payment_reference")
  where "payment_reference" is not null;
alter table "better_supabase"."donations" enable row level security;
revoke all on "better_supabase"."donations" from public, anon, authenticated;
grant select on "better_supabase"."donations" to authenticated;
grant all on "better_supabase"."donations" to service_role;
drop policy if exists "donations_read" on "better_supabase"."donations";
create policy donations_read on "better_supabase"."donations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- Creates or updates the fund or campaign with this key.
create or replace function "better_supabase"."save_donation_fund"(tenant uuid, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_donation_fund.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if save_donation_fund.key is null or save_donation_fund.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if nullif(trim(save_donation_fund.name), '') is null then
    raise exception 'a fund needs a name' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(save_donation_fund.kind, 'fund') not in ('fund', 'campaign') then
    raise exception 'kind is fund or campaign' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.goal is not null and (save_donation_fund.goal <= 0 or save_donation_fund.currency is null or save_donation_fund.currency !~ '^[A-Z]{3}$') then
    raise exception 'a goal is more than zero minor units of a three-letter currency' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.starts_on is not null and save_donation_fund.ends_on is not null and save_donation_fund.ends_on < save_donation_fund.starts_on then
    raise exception 'ends_on is on or after starts_on' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  insert into "better_supabase"."donation_funds" ("tenant_id", "key", "name", "kind", "goal", "currency", "starts_on", "ends_on")
  values (save_donation_fund.tenant, save_donation_fund.key, trim(save_donation_fund.name), coalesce(save_donation_fund.kind, 'fund'),
    save_donation_fund.goal, save_donation_fund.currency, save_donation_fund.starts_on, save_donation_fund.ends_on)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "kind" = excluded."kind", "goal" = excluded."goal",
    "currency" = excluded."currency", "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on",
    "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) from public, anon;
grant execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) to authenticated, service_role;

create or replace function "better_supabase"."archive_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donation_funds" x where x."id" = archive_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "better_supabase"."donation_funds" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_donation_fund"(uuid) to authenticated, service_role;

-- Funds and campaigns with what they raised: posted gifts in the goal's
-- currency.
create or replace function "better_supabase"."list_donation_funds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_funds.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'goal', x."goal"::text, 'currency', x."currency", 'raised', case when x."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = x."id" and g."status" = 'posted' and g."currency" = x."currency"), 0)::text end, 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
    from "better_supabase"."donation_funds" x
    where x."tenant_id" = list_donation_funds.tenant
      and (coalesce(list_donation_funds.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_funds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_donation_funds"(uuid, boolean) to authenticated, service_role;

-- Moves a gift along: pending stores the payment, succeeded posts it on
-- the ledger (cash in, fund income out), failed marks a pending gift, and
-- refunded reverses a posted one and voids its gift receipt. Each posting
-- carries a key per gift, so a repeat changes nothing. Internal.
create or replace function "better_supabase"."donation_settle"(gift_id uuid, status text, provider text default null, payment_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_fund "better_supabase"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "better_supabase"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "better_supabase"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "better_supabase"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"));
    update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "better_supabase"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."donation_settle"(uuid, text, text, text) from public, anon, authenticated;

-- Records a gift received outside a payments provider (cash, a check, a
-- bank transfer) and posts it at once. With a pledge and period it pays
-- that installment; a second call for the same period returns the gift.
-- fields: the extra columns to set.
drop function if exists "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date, jsonb);
create or replace function "better_supabase"."record_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_pledge "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if record_gift.donor_type is null or record_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if record_gift.amount is null or record_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.currency is null or record_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = record_gift.fund_id and y."tenant_id" = record_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if record_gift.pledge_id is not null then
    select * into v_pledge from "better_supabase"."pledges" y where y."id" = record_gift.pledge_id and y."tenant_id" = record_gift.tenant;
    if not found or v_pledge."donor_type" <> record_gift.donor_type or v_pledge."donor_id" <> record_gift.donor_id
      or v_pledge."currency" <> record_gift.currency or record_gift.period_start is null then
      raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
    end if;
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "received_on", "method", "note", "created_by")
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge."fund_id"), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = record_gift.pledge_id and x."period_start" = record_gift.period_start;
  end if;
  return "better_supabase"."donation_settle"(v_row."id", 'succeeded');
end;
$$;
revoke execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) from public, anon;
grant execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) to authenticated, service_role;

-- Opens a pending gift a payments provider will charge. With a pledge and
-- period a second call returns the same gift, so a retried charge run never
-- charges a period twice. fields: the extra columns to set.
drop function if exists "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text, jsonb);
create or replace function "better_supabase"."open_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if open_gift.donor_type is null or open_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if open_gift.amount is null or open_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.currency is null or open_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = open_gift.fund_id and y."tenant_id" = open_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from "better_supabase"."pledges" y where y."id" = open_gift.pledge_id and y."tenant_id" = open_gift.tenant
      and y."donor_type" = open_gift.donor_type and y."donor_id" = open_gift.donor_id and y."currency" = open_gift.currency
  )) then
    raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "method", "provider", "note", "created_by")
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = open_gift.pledge_id and x."period_start" = open_gift.period_start;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) from public, anon;
grant execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) to authenticated, service_role;

-- Records what the payments provider reported for a gift: by its id, or
-- (gift_id null) by the provider's payment id. succeeded posts it, failed
-- marks it, refunded reverses it. A webhook calls it with the service role.
create or replace function "better_supabase"."record_gift_payment"(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if record_gift_payment.gift_id is not null then
    select * into v_row from "better_supabase"."donations" x where x."id" = record_gift_payment.gift_id;
  else
    select * into v_row from "better_supabase"."donations" x
      where x."provider" = record_gift_payment.provider and x."payment_reference" = record_gift_payment.payment_id;
  end if;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return "better_supabase"."donation_settle"(v_row."id", record_gift_payment.status, record_gift_payment.provider, record_gift_payment.payment_id);
end;
$$;
revoke execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."get_gift"(gift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = get_gift.gift_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_gift"(uuid) from public, anon;
grant execute on function "better_supabase"."get_gift"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_gifts"(tenant uuid, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_gifts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'pledgeId', q."pledge_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', q."currency", 'receivedOn', q."received_on", 'method', q."method", 'status', q."status", 'provider', q."provider", 'paymentReference', q."payment_reference", 'transactionId', q."transaction_id", 'refundTransactionId', q."refund_transaction_id", 'receiptId', q."receipt_id", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."received_on" desc, q."created_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (list_gifts.donor_type is null or (x."donor_type" = list_gifts.donor_type and x."donor_id" = list_gifts.donor_id))
        and (list_gifts.fund_id is null or x."fund_id" = list_gifts.fund_id)
        and (list_gifts.pledge_id is null or x."pledge_id" = list_gifts.pledge_id)
        and (list_gifts.status is null or x."status" = list_gifts.status)
      order by x."received_on" desc, x."created_at" desc
      limit least(greatest(coalesce(list_gifts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."create_pledge"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_pledge.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if create_pledge.donor_type is null or create_pledge.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if create_pledge.amount is null or create_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.currency is null or create_pledge.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = create_pledge.fund_id and y."tenant_id" = create_pledge.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id", "fund_id", "amount", "currency", "frequency",
    "starts_on", "ends_on", "provider", "provider_customer", "note", "created_by")
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    coalesce(create_pledge.frequency, 'monthly'), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) to authenticated, service_role;

-- Pauses, resumes or ends a pledge, moves its end or changes its amount for
-- installments from now on. Null keeps a value.
create or replace function "better_supabase"."update_pledge"(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."pledges" x where x."id" = update_pledge.pledge_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such pledge you can manage' using errcode = 'P0002', hint = 'DONATION_PLEDGE_NOT_FOUND';
  end if;
  if update_pledge.status is not null and update_pledge.status not in ('active', 'paused', 'ended') then
    raise exception 'status is active, paused or ended' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if v_row."status" = 'ended' and coalesce(update_pledge.status, 'ended') <> 'ended' then
    raise exception 'an ended pledge can''t restart; create a new one' using errcode = '55000', hint = 'DONATION_PLEDGE_ENDED';
  end if;
  if update_pledge.ends_on is not null and update_pledge.ends_on <= v_row."starts_on" then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if update_pledge.amount is not null and update_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  update "better_supabase"."pledges" x set
      "status" = coalesce(update_pledge.status, x."status"),
      "ends_on" = coalesce(update_pledge.ends_on, x."ends_on"),
      "amount" = coalesce(update_pledge.amount, x."amount"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."list_pledges"(tenant uuid, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_pledges.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'amount', q."amount"::text, 'currency', q."currency", 'frequency', q."frequency", 'startsOn', q."starts_on", 'endsOn', q."ends_on", 'status', q."status", 'provider', q."provider", 'providerCustomer', q."provider_customer", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (list_pledges.donor_type is null or (x."donor_type" = list_pledges.donor_type and x."donor_id" = list_pledges.donor_id))
        and (list_pledges.status is null or x."status" = list_pledges.status)
      order by x."created_at" desc, x."id"
      limit least(greatest(coalesce(list_pledges.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) to authenticated, service_role;

-- The installments of active pledges that start on or before through
-- (default today) and have no gift yet, oldest first, up to max_rows. A
-- gift opened but never charged (pending without a payment) stays due, so
-- the next run charges it under the same idempotency key; a declined one
-- doesn't.
create or replace function "better_supabase"."due_pledge_installments"(tenant uuid, through date default null, max_rows integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(due_pledge_installments.through, current_date);
  v_max integer := least(greatest(coalesce(due_pledge_installments.max_rows, 500), 1), 5000);
  v_row "better_supabase"."pledges"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_start date;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', due_pledge_installments.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  <<installments>>
  for v_row in
    select * from "better_supabase"."pledges" x
    where x."tenant_id" = due_pledge_installments.tenant and x."status" = 'active' and x."starts_on" <= v_through
    order by x."starts_on", x."id"
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."donations" g where g."pledge_id" = v_row."id" and g."period_start" = v_start
        and not (g."status" = 'pending' and g."payment_reference" is null)) then
        exit installments when jsonb_array_length(v_items) >= v_max;
        v_items := v_items || jsonb_build_array(jsonb_build_object('periodStart', v_start, 'pledgeId', v_row."id",
          'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id",
          'amount', v_row."amount"::text, 'currency', v_row."currency",
          'provider', v_row."provider", 'providerCustomer', v_row."provider_customer"));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_items;
end;
$$;
revoke execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) to authenticated, service_role;

-- Issues a numbered tax receipt for one posted gift. Numbers come from
-- numbering when it configures donation_receipt, else one more than
-- the organization's highest.
create or replace function "better_supabase"."issue_gift_receipt"(gift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donations" x where x."id" = issue_gift_receipt.gift_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted gift gets a receipt' using errcode = '55000', hint = 'DONATION_STATUS_INVALID';
  end if;
  if v_row."receipt_id" is not null then
    select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = v_row."receipt_id";
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_row."tenant_id", 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_row."tenant_id", 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (v_row."tenant_id", v_row."donor_type", v_row."donor_id", v_seq, v_number, 'gift', extract(year from v_row."received_on")::integer,
    v_row."amount", v_row."currency")
  returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = v_receipt."id", "updated_at" = now() where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_gift_receipt"(uuid) from public, anon;
grant execute on function "better_supabase"."issue_gift_receipt"(uuid) to authenticated, service_role;

-- Issues a donor's yearly tax receipt: their posted gifts received in year
-- in currency. A second call returns the receipt until it is voided.
create or replace function "better_supabase"."issue_yearly_receipt"(tenant uuid, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_yearly_receipt.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    raise exception 'a yearly receipt needs a year and a currency' using errcode = '22023', hint = 'DONATION_RECEIPT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from "better_supabase"."donation_receipts" x
    where x."tenant_id" = issue_yearly_receipt.tenant and x."donor_type" = issue_yearly_receipt.donor_type
      and x."donor_id" = issue_yearly_receipt.donor_id and x."year" = issue_yearly_receipt.year
      and x."currency" = issue_yearly_receipt.currency and x."kind" = 'yearly' and x."voided_at" is null;
  if found then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  select coalesce(sum(g."amount"), 0) into v_amount from "better_supabase"."donations" g
    where g."tenant_id" = issue_yearly_receipt.tenant and g."donor_type" = issue_yearly_receipt.donor_type
      and g."donor_id" = issue_yearly_receipt.donor_id and g."currency" = issue_yearly_receipt.currency
      and g."status" = 'posted' and extract(year from g."received_on")::integer = issue_yearly_receipt.year;
  if v_amount <= 0 then
    raise exception 'the donor has no posted gifts in this year and currency' using errcode = '22023', hint = 'DONATION_RECEIPT_EMPTY';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(issue_yearly_receipt.tenant, 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(issue_yearly_receipt.tenant, 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) from public, anon;
grant execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) to authenticated, service_role;

-- Voids a receipt; its number stays used. A voided gift receipt frees the
-- gift for a new one.
create or replace function "better_supabase"."void_donation_receipt"(receipt_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = void_donation_receipt.receipt_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_receipt."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such receipt you can manage' using errcode = 'P0002', hint = 'DONATION_RECEIPT_NOT_FOUND';
  end if;
  if v_receipt."voided_at" is not null then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = nullif(trim(void_donation_receipt.reason), '')
    where x."id" = v_receipt."id"
    returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = null, "updated_at" = now() where x."receipt_id" = v_receipt."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."void_donation_receipt"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_donation_receipt"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."list_donation_receipts"(tenant uuid, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_receipts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'sequence', q."sequence"::text, 'number', q."number", 'kind', q."kind", 'year', q."year", 'amount', q."amount"::text, 'currency', q."currency", 'issuedAt', q."issued_at", 'voidedAt', q."voided_at", 'voidReason', q."void_reason") order by q."issued_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."donation_receipts" x
      where x."tenant_id" = list_donation_receipts.tenant
        and (list_donation_receipts.donor_type is null or (x."donor_type" = list_donation_receipts.donor_type and x."donor_id" = list_donation_receipts.donor_id))
        and (list_donation_receipts.year is null or x."year" = list_donation_receipts.year)
      order by x."issued_at" desc, x."id"
      limit least(greatest(coalesce(list_donation_receipts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) to authenticated, service_role;

-- A donor's giving in a year (default this one): posted totals per
-- currency, per fund, and the receipts issued for the year.
create or replace function "better_supabase"."yearly_giving_summary"(tenant uuid, donor_type text, donor_id text, year integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_year integer := coalesce(yearly_giving_summary.year, extract(year from current_date)::integer);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', yearly_giving_summary.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'year', v_year,
    'donorType', yearly_giving_summary.donor_type,
    'donorId', yearly_giving_summary.donor_id,
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object('currency', q.currency, 'amount', q.amount::text, 'gifts', q.gifts) order by q.currency), '[]'::jsonb)
      from (
        select g."currency" as currency, sum(g."amount") as amount, count(*) as gifts
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."currency"
      ) q
    ),
    'funds', (
      select coalesce(jsonb_agg(jsonb_build_object('fundId', q.fund, 'name', coalesce(y."name", 'General'), 'currency', q.currency, 'amount', q.amount::text)
        order by coalesce(y."name", ''), q.currency), '[]'::jsonb)
      from (
        select g."fund_id" as fund, g."currency" as currency, sum(g."amount") as amount
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."fund_id", g."currency"
      ) q
      left join "better_supabase"."donation_funds" y on y."id" = q.fund
    ),
    'receipts', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'sequence', x."sequence"::text, 'number', x."number", 'kind', x."kind", 'year', x."year", 'amount', x."amount"::text, 'currency', x."currency", 'issuedAt', x."issued_at", 'voidedAt', x."voided_at", 'voidReason', x."void_reason") order by x."issued_at"), '[]'::jsonb)
      from "better_supabase"."donation_receipts" x
      where x."tenant_id" = yearly_giving_summary.tenant and x."donor_type" = yearly_giving_summary.donor_type
        and x."donor_id" = yearly_giving_summary.donor_id and x."year" = v_year
    )
  );
end;
$$;
revoke execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_select on "better_supabase"."donation_funds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_funds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_update on "better_supabase"."donation_funds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_funds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
create policy bsb_tenant_scope_select on "better_supabase"."pledges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
create policy bsb_tenant_scope_insert on "better_supabase"."pledges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
create policy bsb_tenant_scope_update on "better_supabase"."pledges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
create policy bsb_tenant_scope_delete on "better_supabase"."pledges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_select on "better_supabase"."donation_receipts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_receipts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_update on "better_supabase"."donation_receipts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_receipts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
create policy bsb_tenant_scope_select on "better_supabase"."donations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
create policy bsb_tenant_scope_insert on "better_supabase"."donations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
create policy bsb_tenant_scope_update on "better_supabase"."donations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
create policy bsb_tenant_scope_delete on "better_supabase"."donations" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:766adfa3e7067c6f8172269a3181465a320dd4dc98f6ab433fc4ba3e69980c75
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block donations@2 managed
-- @bsb-hash sha256:1f73b6ee55ca6351e7f7adf2de94aae96c4898a26c8d4d423af0181d38c513fa
-- Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Donations: gifts and pledges from donors (registered subjects) to funds
-- and campaigns, each posted gift on the ledger, and numbered tax receipts.

-- A fund or campaign gifts go to; goal is in minor units of currency.
create table if not exists "better_supabase"."donation_funds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'fund' check ("kind" in ('fund', 'campaign')),
  "goal" bigint check ("goal" is null or "goal" > 0),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "starts_on" date,
  "ends_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check ("goal" is null or "currency" is not null),
  check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on")
);
alter table "better_supabase"."donation_funds" enable row level security;
revoke all on "better_supabase"."donation_funds" from public, anon, authenticated;
grant select on "better_supabase"."donation_funds" to authenticated;
grant all on "better_supabase"."donation_funds" to service_role;
drop policy if exists "donation_funds_read" on "better_supabase"."donation_funds";
create policy donation_funds_read on "better_supabase"."donation_funds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A recurring gift: amount every period of frequency, charged through the
-- payments provider when provider is set, recorded by hand otherwise.
create table if not exists "better_supabase"."pledges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "starts_on" date not null,
  "ends_on" date,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'ended')),
  "provider" text,
  "provider_customer" text,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "better_supabase"."donation_funds" ("tenant_id", "id") on delete restrict,
  check ("ends_on" is null or "ends_on" > "starts_on")
);
create index if not exists "pledges_tenant_idx" on "better_supabase"."pledges" ("tenant_id", "status");
create index if not exists "pledges_donor_idx" on "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id");
create index if not exists "pledges_fund_idx" on "better_supabase"."pledges" ("tenant_id", "fund_id") where "fund_id" is not null;
alter table "better_supabase"."pledges" enable row level security;
revoke all on "better_supabase"."pledges" from public, anon, authenticated;
grant select on "better_supabase"."pledges" to authenticated;
grant all on "better_supabase"."pledges" to service_role;
drop policy if exists "pledges_read" on "better_supabase"."pledges";
create policy pledges_read on "better_supabase"."pledges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A tax receipt: one gift, or a donor's posted gifts in a year and currency.
create table if not exists "better_supabase"."donation_receipts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "sequence" bigint not null,
  "number" text not null,
  "kind" text not null check ("kind" in ('gift', 'yearly')),
  "year" integer not null,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null,
  "issued_at" timestamptz not null default now(),
  "voided_at" timestamptz,
  "void_reason" text check ("void_reason" is null or length("void_reason") <= 2000),
  unique ("tenant_id", "number")
);
create index if not exists "donation_receipts_donor_idx" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year");
create unique index if not exists "donation_receipts_yearly_key" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year", "currency")
  where "kind" = 'yearly' and "voided_at" is null;
alter table "better_supabase"."donation_receipts" enable row level security;
revoke all on "better_supabase"."donation_receipts" from public, anon, authenticated;
grant select on "better_supabase"."donation_receipts" to authenticated;
grant all on "better_supabase"."donation_receipts" to service_role;
drop policy if exists "donation_receipts_read" on "better_supabase"."donation_receipts";
create policy donation_receipts_read on "better_supabase"."donation_receipts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

create table if not exists "better_supabase"."donations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "pledge_id" uuid references "better_supabase"."pledges" ("id") on delete set null,
  -- The pledge period this gift pays; unique per pledge.
  "period_start" date,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "received_on" date not null default current_date,
  "method" text check ("method" is null or length("method") <= 40),
  "status" text not null default 'pending' check ("status" in ('pending', 'posted', 'failed', 'refunded')),
  "provider" text,
  "payment_reference" text,
  "transaction_id" uuid,
  "refund_transaction_id" uuid,
  "receipt_id" uuid references "better_supabase"."donation_receipts" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "better_supabase"."donation_funds" ("tenant_id", "id") on delete restrict,
  unique ("pledge_id", "period_start")
);
create index if not exists "donations_tenant_idx" on "better_supabase"."donations" ("tenant_id", "received_on" desc);
create index if not exists "donations_donor_idx" on "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "received_on");
create index if not exists "donations_fund_idx" on "better_supabase"."donations" ("tenant_id", "fund_id") where "fund_id" is not null;
create index if not exists "donations_receipt_idx" on "better_supabase"."donations" ("receipt_id") where "receipt_id" is not null;
create index if not exists "donations_transaction_idx" on "better_supabase"."donations" ("transaction_id") where "transaction_id" is not null;
create index if not exists "donations_refund_idx" on "better_supabase"."donations" ("refund_transaction_id") where "refund_transaction_id" is not null;
create unique index if not exists "donations_payment_key" on "better_supabase"."donations" ("provider", "payment_reference")
  where "payment_reference" is not null;
alter table "better_supabase"."donations" enable row level security;
revoke all on "better_supabase"."donations" from public, anon, authenticated;
grant select on "better_supabase"."donations" to authenticated;
grant all on "better_supabase"."donations" to service_role;
drop policy if exists "donations_read" on "better_supabase"."donations";
create policy donations_read on "better_supabase"."donations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- Creates or updates the fund or campaign with this key.
create or replace function "better_supabase"."save_donation_fund"(tenant uuid, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_donation_fund.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if save_donation_fund.key is null or save_donation_fund.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if nullif(trim(save_donation_fund.name), '') is null then
    raise exception 'a fund needs a name' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(save_donation_fund.kind, 'fund') not in ('fund', 'campaign') then
    raise exception 'kind is fund or campaign' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.goal is not null and (save_donation_fund.goal <= 0 or save_donation_fund.currency is null or save_donation_fund.currency !~ '^[A-Z]{3}$') then
    raise exception 'a goal is more than zero minor units of a three-letter currency' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.starts_on is not null and save_donation_fund.ends_on is not null and save_donation_fund.ends_on < save_donation_fund.starts_on then
    raise exception 'ends_on is on or after starts_on' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  insert into "better_supabase"."donation_funds" ("tenant_id", "key", "name", "kind", "goal", "currency", "starts_on", "ends_on")
  values (save_donation_fund.tenant, save_donation_fund.key, trim(save_donation_fund.name), coalesce(save_donation_fund.kind, 'fund'),
    save_donation_fund.goal, save_donation_fund.currency, save_donation_fund.starts_on, save_donation_fund.ends_on)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "kind" = excluded."kind", "goal" = excluded."goal",
    "currency" = excluded."currency", "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on",
    "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) from public, anon;
grant execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) to authenticated, service_role;

create or replace function "better_supabase"."archive_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donation_funds" x where x."id" = archive_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "better_supabase"."donation_funds" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_donation_fund"(uuid) to authenticated, service_role;

-- Funds and campaigns with what they raised: posted gifts in the goal's
-- currency.
create or replace function "better_supabase"."list_donation_funds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_funds.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'goal', x."goal"::text, 'currency', x."currency", 'raised', case when x."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = x."id" and g."status" = 'posted' and g."currency" = x."currency"), 0)::text end, 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
    from "better_supabase"."donation_funds" x
    where x."tenant_id" = list_donation_funds.tenant
      and (coalesce(list_donation_funds.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_funds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_donation_funds"(uuid, boolean) to authenticated, service_role;

-- Moves a gift along: pending stores the payment, succeeded posts it on
-- the ledger (cash in, fund income out), failed marks a pending gift, and
-- refunded reverses a posted one and voids its gift receipt. Each posting
-- carries a key per gift, so a repeat changes nothing. Internal.
create or replace function "better_supabase"."donation_settle"(gift_id uuid, status text, provider text default null, payment_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_fund "better_supabase"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "better_supabase"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "better_supabase"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('gift', v_row."id"::text);
  end if;
    perform "better_supabase".emit_event('donation.received', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.received',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'received a gift',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "better_supabase"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('donation.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.failed',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'a gift payment failed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"));
    update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "better_supabase"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'gift', v_row."id"::text);
    perform "better_supabase".emit_event('donation.refunded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status"), 'donations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation.refunded',
    category => 'billing',
    target_type => 'donation',
    record_id => v_row."id"::text,
    summary => 'refunded a gift',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."donation_settle"(uuid, text, text, text) from public, anon, authenticated;

-- Records a gift received outside a payments provider (cash, a check, a
-- bank transfer) and posts it at once. With a pledge and period it pays
-- that installment; a second call for the same period returns the gift.
-- fields: the extra columns to set.
drop function if exists "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date, jsonb);
create or replace function "better_supabase"."record_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_pledge "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if record_gift.donor_type is null or record_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if record_gift.amount is null or record_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.currency is null or record_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = record_gift.fund_id and y."tenant_id" = record_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if record_gift.pledge_id is not null then
    select * into v_pledge from "better_supabase"."pledges" y where y."id" = record_gift.pledge_id and y."tenant_id" = record_gift.tenant;
    if not found or v_pledge."donor_type" <> record_gift.donor_type or v_pledge."donor_id" <> record_gift.donor_id
      or v_pledge."currency" <> record_gift.currency or record_gift.period_start is null then
      raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
    end if;
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "received_on", "method", "note", "created_by")
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge."fund_id"), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = record_gift.pledge_id and x."period_start" = record_gift.period_start;
  end if;
  return "better_supabase"."donation_settle"(v_row."id", 'succeeded');
end;
$$;
revoke execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) from public, anon;
grant execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) to authenticated, service_role;

-- Opens a pending gift a payments provider will charge. With a pledge and
-- period a second call returns the same gift, so a retried charge run never
-- charges a period twice. fields: the extra columns to set.
drop function if exists "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text, jsonb);
create or replace function "better_supabase"."open_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if open_gift.donor_type is null or open_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if open_gift.amount is null or open_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.currency is null or open_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = open_gift.fund_id and y."tenant_id" = open_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from "better_supabase"."pledges" y where y."id" = open_gift.pledge_id and y."tenant_id" = open_gift.tenant
      and y."donor_type" = open_gift.donor_type and y."donor_id" = open_gift.donor_id and y."currency" = open_gift.currency
  )) then
    raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "method", "provider", "note", "created_by")
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = open_gift.pledge_id and x."period_start" = open_gift.period_start;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) from public, anon;
grant execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) to authenticated, service_role;

-- Records what the payments provider reported for a gift: by its id, or
-- (gift_id null) by the provider's payment id. succeeded posts it, failed
-- marks it, refunded reverses it. A webhook calls it with the service role.
create or replace function "better_supabase"."record_gift_payment"(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if record_gift_payment.gift_id is not null then
    select * into v_row from "better_supabase"."donations" x where x."id" = record_gift_payment.gift_id;
  else
    select * into v_row from "better_supabase"."donations" x
      where x."provider" = record_gift_payment.provider and x."payment_reference" = record_gift_payment.payment_id;
  end if;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return "better_supabase"."donation_settle"(v_row."id", record_gift_payment.status, record_gift_payment.provider, record_gift_payment.payment_id);
end;
$$;
revoke execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."get_gift"(gift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = get_gift.gift_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_gift"(uuid) from public, anon;
grant execute on function "better_supabase"."get_gift"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_gifts"(tenant uuid, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_gifts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'pledgeId', q."pledge_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', q."currency", 'receivedOn', q."received_on", 'method', q."method", 'status', q."status", 'provider', q."provider", 'paymentReference', q."payment_reference", 'transactionId', q."transaction_id", 'refundTransactionId', q."refund_transaction_id", 'receiptId', q."receipt_id", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."received_on" desc, q."created_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (list_gifts.donor_type is null or (x."donor_type" = list_gifts.donor_type and x."donor_id" = list_gifts.donor_id))
        and (list_gifts.fund_id is null or x."fund_id" = list_gifts.fund_id)
        and (list_gifts.pledge_id is null or x."pledge_id" = list_gifts.pledge_id)
        and (list_gifts.status is null or x."status" = list_gifts.status)
      order by x."received_on" desc, x."created_at" desc
      limit least(greatest(coalesce(list_gifts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."create_pledge"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_pledge.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if create_pledge.donor_type is null or create_pledge.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if create_pledge.amount is null or create_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.currency is null or create_pledge.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = create_pledge.fund_id and y."tenant_id" = create_pledge.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id", "fund_id", "amount", "currency", "frequency",
    "starts_on", "ends_on", "provider", "provider_customer", "note", "created_by")
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    coalesce(create_pledge.frequency, 'monthly'), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('pledge.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'status', v_row."status"), 'pledges/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'pledge.created',
    category => 'billing',
    target_type => 'pledge',
    record_id => v_row."id"::text,
    summary => 'created a pledge',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) to authenticated, service_role;

-- Pauses, resumes or ends a pledge, moves its end or changes its amount for
-- installments from now on. Null keeps a value.
create or replace function "better_supabase"."update_pledge"(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."pledges" x where x."id" = update_pledge.pledge_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such pledge you can manage' using errcode = 'P0002', hint = 'DONATION_PLEDGE_NOT_FOUND';
  end if;
  if update_pledge.status is not null and update_pledge.status not in ('active', 'paused', 'ended') then
    raise exception 'status is active, paused or ended' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if v_row."status" = 'ended' and coalesce(update_pledge.status, 'ended') <> 'ended' then
    raise exception 'an ended pledge can''t restart; create a new one' using errcode = '55000', hint = 'DONATION_PLEDGE_ENDED';
  end if;
  if update_pledge.ends_on is not null and update_pledge.ends_on <= v_row."starts_on" then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if update_pledge.amount is not null and update_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  update "better_supabase"."pledges" x set
      "status" = coalesce(update_pledge.status, x."status"),
      "ends_on" = coalesce(update_pledge.ends_on, x."ends_on"),
      "amount" = coalesce(update_pledge.amount, x."amount"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('pledge.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'status', v_row."status"), 'pledges/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'pledge.updated',
    category => 'billing',
    target_type => 'pledge',
    record_id => v_row."id"::text,
    summary => 'updated a pledge',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."list_pledges"(tenant uuid, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_pledges.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'amount', q."amount"::text, 'currency', q."currency", 'frequency', q."frequency", 'startsOn', q."starts_on", 'endsOn', q."ends_on", 'status', q."status", 'provider', q."provider", 'providerCustomer', q."provider_customer", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (list_pledges.donor_type is null or (x."donor_type" = list_pledges.donor_type and x."donor_id" = list_pledges.donor_id))
        and (list_pledges.status is null or x."status" = list_pledges.status)
      order by x."created_at" desc, x."id"
      limit least(greatest(coalesce(list_pledges.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) to authenticated, service_role;

-- The installments of active pledges that start on or before through
-- (default today) and have no gift yet, oldest first, up to max_rows. A
-- gift opened but never charged (pending without a payment) stays due, so
-- the next run charges it under the same idempotency key; a declined one
-- doesn't.
create or replace function "better_supabase"."due_pledge_installments"(tenant uuid, through date default null, max_rows integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(due_pledge_installments.through, current_date);
  v_max integer := least(greatest(coalesce(due_pledge_installments.max_rows, 500), 1), 5000);
  v_row "better_supabase"."pledges"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_start date;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', due_pledge_installments.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  <<installments>>
  for v_row in
    select * from "better_supabase"."pledges" x
    where x."tenant_id" = due_pledge_installments.tenant and x."status" = 'active' and x."starts_on" <= v_through
    order by x."starts_on", x."id"
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."donations" g where g."pledge_id" = v_row."id" and g."period_start" = v_start
        and not (g."status" = 'pending' and g."payment_reference" is null)) then
        exit installments when jsonb_array_length(v_items) >= v_max;
        v_items := v_items || jsonb_build_array(jsonb_build_object('periodStart', v_start, 'pledgeId', v_row."id",
          'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id",
          'amount', v_row."amount"::text, 'currency', v_row."currency",
          'provider', v_row."provider", 'providerCustomer', v_row."provider_customer"));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_items;
end;
$$;
revoke execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) to authenticated, service_role;

-- Issues a numbered tax receipt for one posted gift. Numbers come from
-- numbering when it configures donation_receipt, else one more than
-- the organization's highest.
create or replace function "better_supabase"."issue_gift_receipt"(gift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donations" x where x."id" = issue_gift_receipt.gift_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted gift gets a receipt' using errcode = '55000', hint = 'DONATION_STATUS_INVALID';
  end if;
  if v_row."receipt_id" is not null then
    select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = v_row."receipt_id";
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_row."tenant_id", 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_row."tenant_id", 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (v_row."tenant_id", v_row."donor_type", v_row."donor_id", v_seq, v_number, 'gift', extract(year from v_row."received_on")::integer,
    v_row."amount", v_row."currency")
  returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = v_receipt."id", "updated_at" = now() where x."id" = v_row."id";
  perform "better_supabase".emit_event('donation_receipt.issued', jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency"), 'donation-receipts/' || v_receipt."id"::text, (v_receipt."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation_receipt.issued',
    category => 'billing',
    target_type => 'donation_receipt',
    record_id => v_receipt."id"::text,
    target_label => v_receipt."number",
    summary => 'issued a gift receipt',
    tenant => (v_receipt."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency")
  );
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_gift_receipt"(uuid) from public, anon;
grant execute on function "better_supabase"."issue_gift_receipt"(uuid) to authenticated, service_role;

-- Issues a donor's yearly tax receipt: their posted gifts received in year
-- in currency. A second call returns the receipt until it is voided.
create or replace function "better_supabase"."issue_yearly_receipt"(tenant uuid, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_yearly_receipt.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    raise exception 'a yearly receipt needs a year and a currency' using errcode = '22023', hint = 'DONATION_RECEIPT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from "better_supabase"."donation_receipts" x
    where x."tenant_id" = issue_yearly_receipt.tenant and x."donor_type" = issue_yearly_receipt.donor_type
      and x."donor_id" = issue_yearly_receipt.donor_id and x."year" = issue_yearly_receipt.year
      and x."currency" = issue_yearly_receipt.currency and x."kind" = 'yearly' and x."voided_at" is null;
  if found then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  select coalesce(sum(g."amount"), 0) into v_amount from "better_supabase"."donations" g
    where g."tenant_id" = issue_yearly_receipt.tenant and g."donor_type" = issue_yearly_receipt.donor_type
      and g."donor_id" = issue_yearly_receipt.donor_id and g."currency" = issue_yearly_receipt.currency
      and g."status" = 'posted' and extract(year from g."received_on")::integer = issue_yearly_receipt.year;
  if v_amount <= 0 then
    raise exception 'the donor has no posted gifts in this year and currency' using errcode = '22023', hint = 'DONATION_RECEIPT_EMPTY';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(issue_yearly_receipt.tenant, 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(issue_yearly_receipt.tenant, 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  perform "better_supabase".emit_event('donation_receipt.issued', jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency"), 'donation-receipts/' || v_receipt."id"::text, (v_receipt."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation_receipt.issued',
    category => 'billing',
    target_type => 'donation_receipt',
    record_id => v_receipt."id"::text,
    target_label => v_receipt."number",
    summary => 'issued a yearly receipt',
    tenant => (v_receipt."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency")
  );
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) from public, anon;
grant execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) to authenticated, service_role;

-- Voids a receipt; its number stays used. A voided gift receipt frees the
-- gift for a new one.
create or replace function "better_supabase"."void_donation_receipt"(receipt_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = void_donation_receipt.receipt_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_receipt."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such receipt you can manage' using errcode = 'P0002', hint = 'DONATION_RECEIPT_NOT_FOUND';
  end if;
  if v_receipt."voided_at" is not null then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = nullif(trim(void_donation_receipt.reason), '')
    where x."id" = v_receipt."id"
    returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = null, "updated_at" = now() where x."receipt_id" = v_receipt."id";
  perform "better_supabase".emit_event('donation_receipt.voided', jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency"), 'donation-receipts/' || v_receipt."id"::text, (v_receipt."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation_receipt.voided',
    category => 'billing',
    target_type => 'donation_receipt',
    record_id => v_receipt."id"::text,
    target_label => v_receipt."number",
    summary => 'voided a receipt',
    tenant => (v_receipt."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency")
  );
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."void_donation_receipt"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_donation_receipt"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."list_donation_receipts"(tenant uuid, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_receipts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'sequence', q."sequence"::text, 'number', q."number", 'kind', q."kind", 'year', q."year", 'amount', q."amount"::text, 'currency', q."currency", 'issuedAt', q."issued_at", 'voidedAt', q."voided_at", 'voidReason', q."void_reason") order by q."issued_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."donation_receipts" x
      where x."tenant_id" = list_donation_receipts.tenant
        and (list_donation_receipts.donor_type is null or (x."donor_type" = list_donation_receipts.donor_type and x."donor_id" = list_donation_receipts.donor_id))
        and (list_donation_receipts.year is null or x."year" = list_donation_receipts.year)
      order by x."issued_at" desc, x."id"
      limit least(greatest(coalesce(list_donation_receipts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) to authenticated, service_role;

-- A donor's giving in a year (default this one): posted totals per
-- currency, per fund, and the receipts issued for the year.
create or replace function "better_supabase"."yearly_giving_summary"(tenant uuid, donor_type text, donor_id text, year integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_year integer := coalesce(yearly_giving_summary.year, extract(year from current_date)::integer);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', yearly_giving_summary.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'year', v_year,
    'donorType', yearly_giving_summary.donor_type,
    'donorId', yearly_giving_summary.donor_id,
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object('currency', q.currency, 'amount', q.amount::text, 'gifts', q.gifts) order by q.currency), '[]'::jsonb)
      from (
        select g."currency" as currency, sum(g."amount") as amount, count(*) as gifts
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."currency"
      ) q
    ),
    'funds', (
      select coalesce(jsonb_agg(jsonb_build_object('fundId', q.fund, 'name', coalesce(y."name", 'General'), 'currency', q.currency, 'amount', q.amount::text)
        order by coalesce(y."name", ''), q.currency), '[]'::jsonb)
      from (
        select g."fund_id" as fund, g."currency" as currency, sum(g."amount") as amount
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."fund_id", g."currency"
      ) q
      left join "better_supabase"."donation_funds" y on y."id" = q.fund
    ),
    'receipts', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'sequence', x."sequence"::text, 'number', x."number", 'kind', x."kind", 'year', x."year", 'amount', x."amount"::text, 'currency', x."currency", 'issuedAt', x."issued_at", 'voidedAt', x."voided_at", 'voidReason', x."void_reason") order by x."issued_at"), '[]'::jsonb)
      from "better_supabase"."donation_receipts" x
      where x."tenant_id" = yearly_giving_summary.tenant and x."donor_type" = yearly_giving_summary.donor_type
        and x."donor_id" = yearly_giving_summary.donor_id and x."year" = v_year
    )
  );
end;
$$;
revoke execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) to authenticated, service_role;

-- The entry of a posted gift for accounting: bank against donation revenue.
create or replace function "better_supabase"."accounting_gift_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', v."received_on",
    'currency', v."currency",
    'memo', 'Gift',
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', v."amount"::text),
      jsonb_build_object('role', 'revenue', 'credit', v."amount"::text, 'partyId', v."donor_id"))
  )
  from "better_supabase"."donations" v
  where v."id"::text = source_id and v."status" = 'posted' and v."amount" <> 0
$$;
revoke execute on function "better_supabase"."accounting_gift_lines"(text) from public, anon, authenticated;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_select on "better_supabase"."donation_funds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_funds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_update on "better_supabase"."donation_funds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_funds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
create policy bsb_tenant_scope_select on "better_supabase"."pledges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
create policy bsb_tenant_scope_insert on "better_supabase"."pledges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
create policy bsb_tenant_scope_update on "better_supabase"."pledges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
create policy bsb_tenant_scope_delete on "better_supabase"."pledges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_select on "better_supabase"."donation_receipts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_receipts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_update on "better_supabase"."donation_receipts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_receipts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
create policy bsb_tenant_scope_select on "better_supabase"."donations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
create policy bsb_tenant_scope_insert on "better_supabase"."donations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
create policy bsb_tenant_scope_update on "better_supabase"."donations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
create policy bsb_tenant_scope_delete on "better_supabase"."donations" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:16f1acb7c5d7b4939d5b1ede742178ea14dc0129b25739202d47f15536f3710c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.donations', target_type => 'donation', event_prefix => 'donation', deferred => true);
select better_supabase.audit('better_supabase.pledges', target_type => 'pledge', event_prefix => 'pledge', deferred => true);
select better_supabase.audit('better_supabase.donation_funds', target_type => 'donation_fund', event_prefix => 'donation_fund', deferred => true);
select better_supabase.audit('better_supabase.donation_receipts', target_type => 'donation_receipt', event_prefix => 'donation_receipt', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block donations@2 managed
-- @bsb-hash sha256:b50406112629055679b61e02ecdc4c85bf2c5b67256f8428e61b0c00d2973872
-- Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.
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
    drop policy if exists bsb_tenant_scope on "app_private"."donation_funds";
    drop policy if exists bsb_tenant_scope_select on "app_private"."donation_funds";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."donation_funds";
    drop policy if exists bsb_tenant_scope_update on "app_private"."donation_funds";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."donation_funds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."pledges";
    drop policy if exists bsb_tenant_scope_select on "app_private"."pledges";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."pledges";
    drop policy if exists bsb_tenant_scope_update on "app_private"."pledges";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."pledges";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."donation_receipts";
    drop policy if exists bsb_tenant_scope_select on "app_private"."donation_receipts";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."donation_receipts";
    drop policy if exists bsb_tenant_scope_update on "app_private"."donation_receipts";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."donation_receipts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."donations";
    drop policy if exists bsb_tenant_scope_select on "app_private"."donations";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."donations";
    drop policy if exists bsb_tenant_scope_update on "app_private"."donations";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."donations";
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
-- Donations: gifts and pledges from donors (registered subjects) to funds
-- and campaigns, each posted gift on the ledger, and numbered tax receipts.

-- A fund or campaign gifts go to; goal is in minor units of currency.
create table if not exists "app_private"."donation_funds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'fund' check ("kind" in ('fund', 'campaign')),
  "goal" bigint check ("goal" is null or "goal" > 0),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "starts_on" date,
  "ends_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check ("goal" is null or "currency" is not null),
  check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on")
);
alter table "app_private"."donation_funds" enable row level security;
revoke all on "app_private"."donation_funds" from public, anon, authenticated;
grant select on "app_private"."donation_funds" to authenticated;
grant all on "app_private"."donation_funds" to service_role;
drop policy if exists "donation_funds_read" on "app_private"."donation_funds";
create policy donation_funds_read on "app_private"."donation_funds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A recurring gift: amount every period of frequency, charged through the
-- payments provider when provider is set, recorded by hand otherwise.
create table if not exists "app_private"."pledges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "starts_on" date not null,
  "ends_on" date,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'ended')),
  "provider" text,
  "provider_customer" text,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "app_private"."donation_funds" ("tenant_id", "id") on delete restrict,
  check ("ends_on" is null or "ends_on" > "starts_on")
);
create index if not exists "pledges_tenant_idx" on "app_private"."pledges" ("tenant_id", "status");
create index if not exists "pledges_donor_idx" on "app_private"."pledges" ("tenant_id", "donor_type", "donor_id");
create index if not exists "pledges_fund_idx" on "app_private"."pledges" ("tenant_id", "fund_id") where "fund_id" is not null;
alter table "app_private"."pledges" enable row level security;
revoke all on "app_private"."pledges" from public, anon, authenticated;
grant select on "app_private"."pledges" to authenticated;
grant all on "app_private"."pledges" to service_role;
drop policy if exists "pledges_read" on "app_private"."pledges";
create policy pledges_read on "app_private"."pledges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A tax receipt: one gift, or a donor's posted gifts in a year and currency.
create table if not exists "app_private"."donation_receipts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "sequence" bigint not null,
  "number" text not null,
  "kind" text not null check ("kind" in ('gift', 'yearly')),
  "year" integer not null,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null,
  "issued_at" timestamptz not null default now(),
  "voided_at" timestamptz,
  "void_reason" text check ("void_reason" is null or length("void_reason") <= 2000),
  unique ("tenant_id", "number")
);
create index if not exists "donation_receipts_donor_idx" on "app_private"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year");
create unique index if not exists "donation_receipts_yearly_key" on "app_private"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year", "currency")
  where "kind" = 'yearly' and "voided_at" is null;
alter table "app_private"."donation_receipts" enable row level security;
revoke all on "app_private"."donation_receipts" from public, anon, authenticated;
grant select on "app_private"."donation_receipts" to authenticated;
grant all on "app_private"."donation_receipts" to service_role;
drop policy if exists "donation_receipts_read" on "app_private"."donation_receipts";
create policy donation_receipts_read on "app_private"."donation_receipts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

create table if not exists "app_private"."donations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "pledge_id" uuid references "app_private"."pledges" ("id") on delete set null,
  -- The pledge period this gift pays; unique per pledge.
  "period_start" date,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "received_on" date not null default current_date,
  "method" text check ("method" is null or length("method") <= 40),
  "status" text not null default 'pending' check ("status" in ('pending', 'posted', 'failed', 'refunded')),
  "provider" text,
  "payment_reference" text,
  "transaction_id" uuid,
  "refund_transaction_id" uuid,
  "receipt_id" uuid references "app_private"."donation_receipts" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "app_private"."donation_funds" ("tenant_id", "id") on delete restrict,
  unique ("pledge_id", "period_start")
);
create index if not exists "donations_tenant_idx" on "app_private"."donations" ("tenant_id", "received_on" desc);
create index if not exists "donations_donor_idx" on "app_private"."donations" ("tenant_id", "donor_type", "donor_id", "received_on");
create index if not exists "donations_fund_idx" on "app_private"."donations" ("tenant_id", "fund_id") where "fund_id" is not null;
create index if not exists "donations_receipt_idx" on "app_private"."donations" ("receipt_id") where "receipt_id" is not null;
create index if not exists "donations_transaction_idx" on "app_private"."donations" ("transaction_id") where "transaction_id" is not null;
create index if not exists "donations_refund_idx" on "app_private"."donations" ("refund_transaction_id") where "refund_transaction_id" is not null;
create unique index if not exists "donations_payment_key" on "app_private"."donations" ("provider", "payment_reference")
  where "payment_reference" is not null;
alter table "app_private"."donations" enable row level security;
revoke all on "app_private"."donations" from public, anon, authenticated;
grant select on "app_private"."donations" to authenticated;
grant all on "app_private"."donations" to service_role;
drop policy if exists "donations_read" on "app_private"."donations";
create policy donations_read on "app_private"."donations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- Creates or updates the fund or campaign with this key.
create or replace function "app_private"."save_donation_fund"(tenant uuid, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_donation_fund.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if save_donation_fund.key is null or save_donation_fund.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if nullif(trim(save_donation_fund.name), '') is null then
    raise exception 'a fund needs a name' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(save_donation_fund.kind, 'fund') not in ('fund', 'campaign') then
    raise exception 'kind is fund or campaign' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.goal is not null and (save_donation_fund.goal <= 0 or save_donation_fund.currency is null or save_donation_fund.currency !~ '^[A-Z]{3}$') then
    raise exception 'a goal is more than zero minor units of a three-letter currency' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.starts_on is not null and save_donation_fund.ends_on is not null and save_donation_fund.ends_on < save_donation_fund.starts_on then
    raise exception 'ends_on is on or after starts_on' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  insert into "app_private"."donation_funds" ("tenant_id", "key", "name", "kind", "goal", "currency", "starts_on", "ends_on")
  values (save_donation_fund.tenant, save_donation_fund.key, trim(save_donation_fund.name), coalesce(save_donation_fund.kind, 'fund'),
    save_donation_fund.goal, save_donation_fund.currency, save_donation_fund.starts_on, save_donation_fund.ends_on)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "kind" = excluded."kind", "goal" = excluded."goal",
    "currency" = excluded."currency", "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on",
    "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "app_private"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) from public, anon;
grant execute on function "app_private"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) to authenticated, service_role;

create or replace function "app_private"."archive_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."donation_funds" x where x."id" = archive_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "app_private"."donation_funds" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "app_private"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "app_private"."archive_donation_fund"(uuid) to authenticated, service_role;

-- Funds and campaigns with what they raised: posted gifts in the goal's
-- currency.
create or replace function "app_private"."list_donation_funds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_funds.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'goal', x."goal"::text, 'currency', x."currency", 'raised', case when x."currency" is null then null else coalesce((select sum(g."amount") from "app_private"."donations" g where g."fund_id" = x."id" and g."status" = 'posted' and g."currency" = x."currency"), 0)::text end, 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
    from "app_private"."donation_funds" x
    where x."tenant_id" = list_donation_funds.tenant
      and (coalesce(list_donation_funds.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "app_private"."list_donation_funds"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_donation_funds"(uuid, boolean) to authenticated, service_role;

-- Moves a gift along: pending stores the payment, succeeded posts it on
-- the ledger (cash in, fund income out), failed marks a pending gift, and
-- refunded reverses a posted one and voids its gift receipt. Each posting
-- carries a key per gift, so a repeat changes nothing. Internal.
create or replace function "app_private"."donation_settle"(gift_id uuid, status text, provider text default null, payment_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."donations"%rowtype;
  v_fund "app_private"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "app_private"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "app_private"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "app_private"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "app_private"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "app_private"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"));
    update "app_private"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "app_private"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."donation_settle"(uuid, text, text, text) from public, anon, authenticated;

-- Records a gift received outside a payments provider (cash, a check, a
-- bank transfer) and posts it at once. With a pledge and period it pays
-- that installment; a second call for the same period returns the gift.
-- fields: the extra columns to set.
drop function if exists "app_private"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date, jsonb);
create or replace function "app_private"."record_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."donations"%rowtype;
  v_pledge "app_private"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if record_gift.donor_type is null or record_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if record_gift.amount is null or record_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.currency is null or record_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.fund_id is not null and not exists (
    select 1 from "app_private"."donation_funds" y where y."id" = record_gift.fund_id and y."tenant_id" = record_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if record_gift.pledge_id is not null then
    select * into v_pledge from "app_private"."pledges" y where y."id" = record_gift.pledge_id and y."tenant_id" = record_gift.tenant;
    if not found or v_pledge."donor_type" <> record_gift.donor_type or v_pledge."donor_id" <> record_gift.donor_id
      or v_pledge."currency" <> record_gift.currency or record_gift.period_start is null then
      raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
    end if;
  end if;
  insert into "app_private"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "received_on", "method", "note", "created_by")
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge."fund_id"), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "app_private"."donations" x where x."pledge_id" = record_gift.pledge_id and x."period_start" = record_gift.period_start;
  end if;
  return "app_private"."donation_settle"(v_row."id", 'succeeded');
end;
$$;
revoke execute on function "app_private"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) from public, anon;
grant execute on function "app_private"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) to authenticated, service_role;

-- Opens a pending gift a payments provider will charge. With a pledge and
-- period a second call returns the same gift, so a retried charge run never
-- charges a period twice. fields: the extra columns to set.
drop function if exists "app_private"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text, jsonb);
create or replace function "app_private"."open_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."donations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if open_gift.donor_type is null or open_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if open_gift.amount is null or open_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.currency is null or open_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.fund_id is not null and not exists (
    select 1 from "app_private"."donation_funds" y where y."id" = open_gift.fund_id and y."tenant_id" = open_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from "app_private"."pledges" y where y."id" = open_gift.pledge_id and y."tenant_id" = open_gift.tenant
      and y."donor_type" = open_gift.donor_type and y."donor_id" = open_gift.donor_id and y."currency" = open_gift.currency
  )) then
    raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "app_private"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "method", "provider", "note", "created_by")
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "app_private"."donations" x where x."pledge_id" = open_gift.pledge_id and x."period_start" = open_gift.period_start;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) from public, anon;
grant execute on function "app_private"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) to authenticated, service_role;

-- Records what the payments provider reported for a gift: by its id, or
-- (gift_id null) by the provider's payment id. succeeded posts it, failed
-- marks it, refunded reverses it. A webhook calls it with the service role.
create or replace function "app_private"."record_gift_payment"(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."donations"%rowtype;
begin
  if record_gift_payment.gift_id is not null then
    select * into v_row from "app_private"."donations" x where x."id" = record_gift_payment.gift_id;
  else
    select * into v_row from "app_private"."donations" x
      where x."provider" = record_gift_payment.provider and x."payment_reference" = record_gift_payment.payment_id;
  end if;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return "app_private"."donation_settle"(v_row."id", record_gift_payment.status, record_gift_payment.provider, record_gift_payment.payment_id);
end;
$$;
revoke execute on function "app_private"."record_gift_payment"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."record_gift_payment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "app_private"."get_gift"(gift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."donations"%rowtype;
begin
  select * into v_row from "app_private"."donations" x where x."id" = get_gift.gift_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."get_gift"(uuid) from public, anon;
grant execute on function "app_private"."get_gift"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_gifts"(tenant uuid, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_gifts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'pledgeId', q."pledge_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', q."currency", 'receivedOn', q."received_on", 'method', q."method", 'status', q."status", 'provider', q."provider", 'paymentReference', q."payment_reference", 'transactionId', q."transaction_id", 'refundTransactionId', q."refund_transaction_id", 'receiptId', q."receipt_id", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."received_on" desc, q."created_at" desc), '[]'::jsonb)
    from (
      select * from "app_private"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (list_gifts.donor_type is null or (x."donor_type" = list_gifts.donor_type and x."donor_id" = list_gifts.donor_id))
        and (list_gifts.fund_id is null or x."fund_id" = list_gifts.fund_id)
        and (list_gifts.pledge_id is null or x."pledge_id" = list_gifts.pledge_id)
        and (list_gifts.status is null or x."status" = list_gifts.status)
      order by x."received_on" desc, x."created_at" desc
      limit least(greatest(coalesce(list_gifts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) from public, anon;
grant execute on function "app_private"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function "app_private"."create_pledge"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_pledge.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if create_pledge.donor_type is null or create_pledge.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if create_pledge.amount is null or create_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.currency is null or create_pledge.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.fund_id is not null and not exists (
    select 1 from "app_private"."donation_funds" y where y."id" = create_pledge.fund_id and y."tenant_id" = create_pledge.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "app_private"."pledges" ("tenant_id", "donor_type", "donor_id", "fund_id", "amount", "currency", "frequency",
    "starts_on", "ends_on", "provider", "provider_customer", "note", "created_by")
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    coalesce(create_pledge.frequency, 'monthly'), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) from public, anon;
grant execute on function "app_private"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) to authenticated, service_role;

-- Pauses, resumes or ends a pledge, moves its end or changes its amount for
-- installments from now on. Null keeps a value.
create or replace function "app_private"."update_pledge"(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."pledges" x where x."id" = update_pledge.pledge_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such pledge you can manage' using errcode = 'P0002', hint = 'DONATION_PLEDGE_NOT_FOUND';
  end if;
  if update_pledge.status is not null and update_pledge.status not in ('active', 'paused', 'ended') then
    raise exception 'status is active, paused or ended' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if v_row."status" = 'ended' and coalesce(update_pledge.status, 'ended') <> 'ended' then
    raise exception 'an ended pledge can''t restart; create a new one' using errcode = '55000', hint = 'DONATION_PLEDGE_ENDED';
  end if;
  if update_pledge.ends_on is not null and update_pledge.ends_on <= v_row."starts_on" then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if update_pledge.amount is not null and update_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  update "app_private"."pledges" x set
      "status" = coalesce(update_pledge.status, x."status"),
      "ends_on" = coalesce(update_pledge.ends_on, x."ends_on"),
      "amount" = coalesce(update_pledge.amount, x."amount"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_pledge"(uuid, text, date, bigint) from public, anon;
grant execute on function "app_private"."update_pledge"(uuid, text, date, bigint) to authenticated, service_role;

create or replace function "app_private"."list_pledges"(tenant uuid, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_pledges.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'amount', q."amount"::text, 'currency', q."currency", 'frequency', q."frequency", 'startsOn', q."starts_on", 'endsOn', q."ends_on", 'status', q."status", 'provider', q."provider", 'providerCustomer', q."provider_customer", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "app_private"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (list_pledges.donor_type is null or (x."donor_type" = list_pledges.donor_type and x."donor_id" = list_pledges.donor_id))
        and (list_pledges.status is null or x."status" = list_pledges.status)
      order by x."created_at" desc, x."id"
      limit least(greatest(coalesce(list_pledges.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_pledges"(uuid, text, text, text, integer) from public, anon;
grant execute on function "app_private"."list_pledges"(uuid, text, text, text, integer) to authenticated, service_role;

-- The installments of active pledges that start on or before through
-- (default today) and have no gift yet, oldest first, up to max_rows. A
-- gift opened but never charged (pending without a payment) stays due, so
-- the next run charges it under the same idempotency key; a declined one
-- doesn't.
create or replace function "app_private"."due_pledge_installments"(tenant uuid, through date default null, max_rows integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(due_pledge_installments.through, current_date);
  v_max integer := least(greatest(coalesce(due_pledge_installments.max_rows, 500), 1), 5000);
  v_row "app_private"."pledges"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_start date;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', due_pledge_installments.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  <<installments>>
  for v_row in
    select * from "app_private"."pledges" x
    where x."tenant_id" = due_pledge_installments.tenant and x."status" = 'active' and x."starts_on" <= v_through
    order by x."starts_on", x."id"
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "app_private"."donations" g where g."pledge_id" = v_row."id" and g."period_start" = v_start
        and not (g."status" = 'pending' and g."payment_reference" is null)) then
        exit installments when jsonb_array_length(v_items) >= v_max;
        v_items := v_items || jsonb_build_array(jsonb_build_object('periodStart', v_start, 'pledgeId', v_row."id",
          'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id",
          'amount', v_row."amount"::text, 'currency', v_row."currency",
          'provider', v_row."provider", 'providerCustomer', v_row."provider_customer"));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_items;
end;
$$;
revoke execute on function "app_private"."due_pledge_installments"(uuid, date, integer) from public, anon;
grant execute on function "app_private"."due_pledge_installments"(uuid, date, integer) to authenticated, service_role;

-- Issues a numbered tax receipt for one posted gift. Numbers come from
-- numbering when it configures donation_receipt, else one more than
-- the organization's highest.
create or replace function "app_private"."issue_gift_receipt"(gift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."donations"%rowtype;
  v_receipt "app_private"."donation_receipts"%rowtype;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."donations" x where x."id" = issue_gift_receipt.gift_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted gift gets a receipt' using errcode = '55000', hint = 'DONATION_STATUS_INVALID';
  end if;
  if v_row."receipt_id" is not null then
    select * into v_receipt from "app_private"."donation_receipts" x where x."id" = v_row."receipt_id";
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_row."tenant_id", 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_row."tenant_id", 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "app_private"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (v_row."tenant_id", v_row."donor_type", v_row."donor_id", v_seq, v_number, 'gift', extract(year from v_row."received_on")::integer,
    v_row."amount", v_row."currency")
  returning * into v_receipt;
  update "app_private"."donations" x set "receipt_id" = v_receipt."id", "updated_at" = now() where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "app_private"."issue_gift_receipt"(uuid) from public, anon;
grant execute on function "app_private"."issue_gift_receipt"(uuid) to authenticated, service_role;

-- Issues a donor's yearly tax receipt: their posted gifts received in year
-- in currency. A second call returns the receipt until it is voided.
create or replace function "app_private"."issue_yearly_receipt"(tenant uuid, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_receipt "app_private"."donation_receipts"%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_yearly_receipt.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    raise exception 'a yearly receipt needs a year and a currency' using errcode = '22023', hint = 'DONATION_RECEIPT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from "app_private"."donation_receipts" x
    where x."tenant_id" = issue_yearly_receipt.tenant and x."donor_type" = issue_yearly_receipt.donor_type
      and x."donor_id" = issue_yearly_receipt.donor_id and x."year" = issue_yearly_receipt.year
      and x."currency" = issue_yearly_receipt.currency and x."kind" = 'yearly' and x."voided_at" is null;
  if found then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  select coalesce(sum(g."amount"), 0) into v_amount from "app_private"."donations" g
    where g."tenant_id" = issue_yearly_receipt.tenant and g."donor_type" = issue_yearly_receipt.donor_type
      and g."donor_id" = issue_yearly_receipt.donor_id and g."currency" = issue_yearly_receipt.currency
      and g."status" = 'posted' and extract(year from g."received_on")::integer = issue_yearly_receipt.year;
  if v_amount <= 0 then
    raise exception 'the donor has no posted gifts in this year and currency' using errcode = '22023', hint = 'DONATION_RECEIPT_EMPTY';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(issue_yearly_receipt.tenant, 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(issue_yearly_receipt.tenant, 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "app_private"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "app_private"."issue_yearly_receipt"(uuid, text, text, integer, text) from public, anon;
grant execute on function "app_private"."issue_yearly_receipt"(uuid, text, text, integer, text) to authenticated, service_role;

-- Voids a receipt; its number stays used. A voided gift receipt frees the
-- gift for a new one.
create or replace function "app_private"."void_donation_receipt"(receipt_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt "app_private"."donation_receipts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_receipt from "app_private"."donation_receipts" x where x."id" = void_donation_receipt.receipt_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_receipt."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such receipt you can manage' using errcode = 'P0002', hint = 'DONATION_RECEIPT_NOT_FOUND';
  end if;
  if v_receipt."voided_at" is not null then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  update "app_private"."donation_receipts" x set "voided_at" = now(), "void_reason" = nullif(trim(void_donation_receipt.reason), '')
    where x."id" = v_receipt."id"
    returning * into v_receipt;
  update "app_private"."donations" x set "receipt_id" = null, "updated_at" = now() where x."receipt_id" = v_receipt."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "app_private"."void_donation_receipt"(uuid, text) from public, anon;
grant execute on function "app_private"."void_donation_receipt"(uuid, text) to authenticated, service_role;

create or replace function "app_private"."list_donation_receipts"(tenant uuid, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_receipts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'sequence', q."sequence"::text, 'number', q."number", 'kind', q."kind", 'year', q."year", 'amount', q."amount"::text, 'currency', q."currency", 'issuedAt', q."issued_at", 'voidedAt', q."voided_at", 'voidReason', q."void_reason") order by q."issued_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "app_private"."donation_receipts" x
      where x."tenant_id" = list_donation_receipts.tenant
        and (list_donation_receipts.donor_type is null or (x."donor_type" = list_donation_receipts.donor_type and x."donor_id" = list_donation_receipts.donor_id))
        and (list_donation_receipts.year is null or x."year" = list_donation_receipts.year)
      order by x."issued_at" desc, x."id"
      limit least(greatest(coalesce(list_donation_receipts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_donation_receipts"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "app_private"."list_donation_receipts"(uuid, text, text, integer, integer) to authenticated, service_role;

-- A donor's giving in a year (default this one): posted totals per
-- currency, per fund, and the receipts issued for the year.
create or replace function "app_private"."yearly_giving_summary"(tenant uuid, donor_type text, donor_id text, year integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_year integer := coalesce(yearly_giving_summary.year, extract(year from current_date)::integer);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', yearly_giving_summary.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'year', v_year,
    'donorType', yearly_giving_summary.donor_type,
    'donorId', yearly_giving_summary.donor_id,
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object('currency', q.currency, 'amount', q.amount::text, 'gifts', q.gifts) order by q.currency), '[]'::jsonb)
      from (
        select g."currency" as currency, sum(g."amount") as amount, count(*) as gifts
        from "app_private"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."currency"
      ) q
    ),
    'funds', (
      select coalesce(jsonb_agg(jsonb_build_object('fundId', q.fund, 'name', coalesce(y."name", 'General'), 'currency', q.currency, 'amount', q.amount::text)
        order by coalesce(y."name", ''), q.currency), '[]'::jsonb)
      from (
        select g."fund_id" as fund, g."currency" as currency, sum(g."amount") as amount
        from "app_private"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."fund_id", g."currency"
      ) q
      left join "app_private"."donation_funds" y on y."id" = q.fund
    ),
    'receipts', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'sequence', x."sequence"::text, 'number', x."number", 'kind', x."kind", 'year', x."year", 'amount', x."amount"::text, 'currency', x."currency", 'issuedAt', x."issued_at", 'voidedAt', x."voided_at", 'voidReason', x."void_reason") order by x."issued_at"), '[]'::jsonb)
      from "app_private"."donation_receipts" x
      where x."tenant_id" = yearly_giving_summary.tenant and x."donor_type" = yearly_giving_summary.donor_type
        and x."donor_id" = yearly_giving_summary.donor_id and x."year" = v_year
    )
  );
end;
$$;
revoke execute on function "app_private"."yearly_giving_summary"(uuid, text, text, integer) from public, anon;
grant execute on function "app_private"."yearly_giving_summary"(uuid, text, text, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."donation_funds";
drop policy if exists bsb_tenant_scope_select on "app_private"."donation_funds";
create policy bsb_tenant_scope_select on "app_private"."donation_funds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."donation_funds";
create policy bsb_tenant_scope_insert on "app_private"."donation_funds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."donation_funds";
create policy bsb_tenant_scope_update on "app_private"."donation_funds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."donation_funds";
create policy bsb_tenant_scope_delete on "app_private"."donation_funds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."pledges";
drop policy if exists bsb_tenant_scope_select on "app_private"."pledges";
create policy bsb_tenant_scope_select on "app_private"."pledges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."pledges";
create policy bsb_tenant_scope_insert on "app_private"."pledges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."pledges";
create policy bsb_tenant_scope_update on "app_private"."pledges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."pledges";
create policy bsb_tenant_scope_delete on "app_private"."pledges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."donation_receipts";
drop policy if exists bsb_tenant_scope_select on "app_private"."donation_receipts";
create policy bsb_tenant_scope_select on "app_private"."donation_receipts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."donation_receipts";
create policy bsb_tenant_scope_insert on "app_private"."donation_receipts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."donation_receipts";
create policy bsb_tenant_scope_update on "app_private"."donation_receipts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."donation_receipts";
create policy bsb_tenant_scope_delete on "app_private"."donation_receipts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."donations";
drop policy if exists bsb_tenant_scope_select on "app_private"."donations";
create policy bsb_tenant_scope_select on "app_private"."donations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."donations";
create policy bsb_tenant_scope_insert on "app_private"."donations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."donations";
create policy bsb_tenant_scope_update on "app_private"."donations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."donations";
create policy bsb_tenant_scope_delete on "app_private"."donations" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:766adfa3e7067c6f8172269a3181465a320dd4dc98f6ab433fc4ba3e69980c75
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block donations@2 managed
-- @bsb-hash sha256:f8a45d9168c16033ca35541c2eefb947a68b6205c3e234daaa77e0035e29e485
-- Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Donations: gifts and pledges from donors (registered subjects) to funds
-- and campaigns, each posted gift on the ledger, and numbered tax receipts.

-- A fund or campaign gifts go to; goal is in minor units of currency.
create table if not exists "better_supabase"."donation_funds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'fund' check ("kind" in ('fund', 'campaign')),
  "goal" bigint check ("goal" is null or "goal" > 0),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "starts_on" date,
  "ends_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key"),
  unique ("tenant_id", "id"),
  check ("goal" is null or "currency" is not null),
  check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on")
);
alter table "better_supabase"."donation_funds" enable row level security;
revoke all on "better_supabase"."donation_funds" from public, anon, authenticated;
grant select on "better_supabase"."donation_funds" to authenticated;
grant all on "better_supabase"."donation_funds" to service_role;
drop policy if exists "donation_funds_read" on "better_supabase"."donation_funds";
create policy donation_funds_read on "better_supabase"."donation_funds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A recurring gift: amount every period of frequency, charged through the
-- payments provider when provider is set, recorded by hand otherwise.
create table if not exists "better_supabase"."pledges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "starts_on" date not null,
  "ends_on" date,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'ended')),
  "provider" text,
  "provider_customer" text,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "better_supabase"."donation_funds" ("tenant_id", "id") on delete restrict,
  check ("ends_on" is null or "ends_on" > "starts_on")
);
create index if not exists "pledges_tenant_idx" on "better_supabase"."pledges" ("tenant_id", "status");
create index if not exists "pledges_donor_idx" on "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id");
create index if not exists "pledges_fund_idx" on "better_supabase"."pledges" ("tenant_id", "fund_id") where "fund_id" is not null;
alter table "better_supabase"."pledges" enable row level security;
revoke all on "better_supabase"."pledges" from public, anon, authenticated;
grant select on "better_supabase"."pledges" to authenticated;
grant all on "better_supabase"."pledges" to service_role;
drop policy if exists "pledges_read" on "better_supabase"."pledges";
create policy pledges_read on "better_supabase"."pledges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A tax receipt: one gift, or a donor's posted gifts in a year and currency.
create table if not exists "better_supabase"."donation_receipts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "sequence" bigint not null,
  "number" text not null,
  "kind" text not null check ("kind" in ('gift', 'yearly')),
  "year" integer not null,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null,
  "issued_at" timestamptz not null default now(),
  "voided_at" timestamptz,
  "void_reason" text check ("void_reason" is null or length("void_reason") <= 2000),
  unique ("tenant_id", "number")
);
create index if not exists "donation_receipts_donor_idx" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year");
create unique index if not exists "donation_receipts_yearly_key" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year", "currency")
  where "kind" = 'yearly' and "voided_at" is null;
alter table "better_supabase"."donation_receipts" enable row level security;
revoke all on "better_supabase"."donation_receipts" from public, anon, authenticated;
grant select on "better_supabase"."donation_receipts" to authenticated;
grant all on "better_supabase"."donation_receipts" to service_role;
drop policy if exists "donation_receipts_read" on "better_supabase"."donation_receipts";
create policy donation_receipts_read on "better_supabase"."donation_receipts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

create table if not exists "better_supabase"."donations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "pledge_id" uuid references "better_supabase"."pledges" ("id") on delete set null,
  -- The pledge period this gift pays; unique per pledge.
  "period_start" date,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "received_on" date not null default current_date,
  "method" text check ("method" is null or length("method") <= 40),
  "status" text not null default 'pending' check ("status" in ('pending', 'posted', 'failed', 'refunded')),
  "provider" text,
  "payment_reference" text,
  "transaction_id" uuid,
  "refund_transaction_id" uuid,
  "receipt_id" uuid references "better_supabase"."donation_receipts" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "fund_id") references "better_supabase"."donation_funds" ("tenant_id", "id") on delete restrict,
  unique ("pledge_id", "period_start")
);
create index if not exists "donations_tenant_idx" on "better_supabase"."donations" ("tenant_id", "received_on" desc);
create index if not exists "donations_donor_idx" on "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "received_on");
create index if not exists "donations_fund_idx" on "better_supabase"."donations" ("tenant_id", "fund_id") where "fund_id" is not null;
create index if not exists "donations_receipt_idx" on "better_supabase"."donations" ("receipt_id") where "receipt_id" is not null;
create index if not exists "donations_transaction_idx" on "better_supabase"."donations" ("transaction_id") where "transaction_id" is not null;
create index if not exists "donations_refund_idx" on "better_supabase"."donations" ("refund_transaction_id") where "refund_transaction_id" is not null;
create unique index if not exists "donations_payment_key" on "better_supabase"."donations" ("provider", "payment_reference")
  where "payment_reference" is not null;
alter table "better_supabase"."donations" enable row level security;
revoke all on "better_supabase"."donations" from public, anon, authenticated;
grant select on "better_supabase"."donations" to authenticated;
grant all on "better_supabase"."donations" to service_role;
drop policy if exists "donations_read" on "better_supabase"."donations";
create policy donations_read on "better_supabase"."donations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- Creates or updates the fund or campaign with this key.
create or replace function "better_supabase"."save_donation_fund"(tenant uuid, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_donation_fund.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if save_donation_fund.key is null or save_donation_fund.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if nullif(trim(save_donation_fund.name), '') is null then
    raise exception 'a fund needs a name' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(save_donation_fund.kind, 'fund') not in ('fund', 'campaign') then
    raise exception 'kind is fund or campaign' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.goal is not null and (save_donation_fund.goal <= 0 or save_donation_fund.currency is null or save_donation_fund.currency !~ '^[A-Z]{3}$') then
    raise exception 'a goal is more than zero minor units of a three-letter currency' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.starts_on is not null and save_donation_fund.ends_on is not null and save_donation_fund.ends_on < save_donation_fund.starts_on then
    raise exception 'ends_on is on or after starts_on' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  insert into "better_supabase"."donation_funds" ("tenant_id", "key", "name", "kind", "goal", "currency", "starts_on", "ends_on")
  values (save_donation_fund.tenant, save_donation_fund.key, trim(save_donation_fund.name), coalesce(save_donation_fund.kind, 'fund'),
    save_donation_fund.goal, save_donation_fund.currency, save_donation_fund.starts_on, save_donation_fund.ends_on)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "kind" = excluded."kind", "goal" = excluded."goal",
    "currency" = excluded."currency", "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on",
    "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) from public, anon;
grant execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) to authenticated, service_role;

create or replace function "better_supabase"."archive_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donation_funds" x where x."id" = archive_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "better_supabase"."donation_funds" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_donation_fund"(uuid) to authenticated, service_role;

-- Funds and campaigns with what they raised: posted gifts in the goal's
-- currency.
create or replace function "better_supabase"."list_donation_funds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_funds.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'goal', x."goal"::text, 'currency', x."currency", 'raised', case when x."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = x."id" and g."status" = 'posted' and g."currency" = x."currency"), 0)::text end, 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
    from "better_supabase"."donation_funds" x
    where x."tenant_id" = list_donation_funds.tenant
      and (coalesce(list_donation_funds.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_funds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_donation_funds"(uuid, boolean) to authenticated, service_role;

-- Moves a gift along: pending stores the payment, succeeded posts it on
-- the ledger (cash in, fund income out), failed marks a pending gift, and
-- refunded reverses a posted one and voids its gift receipt. Each posting
-- carries a key per gift, so a repeat changes nothing. Internal.
create or replace function "better_supabase"."donation_settle"(gift_id uuid, status text, provider text default null, payment_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_fund "better_supabase"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "better_supabase"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "better_supabase"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "better_supabase"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"));
    update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "better_supabase"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."donation_settle"(uuid, text, text, text) from public, anon, authenticated;

-- Records a gift received outside a payments provider (cash, a check, a
-- bank transfer) and posts it at once. With a pledge and period it pays
-- that installment; a second call for the same period returns the gift.
-- fields: the extra columns to set.
drop function if exists "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date, jsonb);
create or replace function "better_supabase"."record_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_pledge "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if record_gift.donor_type is null or record_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if record_gift.amount is null or record_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.currency is null or record_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = record_gift.fund_id and y."tenant_id" = record_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if record_gift.pledge_id is not null then
    select * into v_pledge from "better_supabase"."pledges" y where y."id" = record_gift.pledge_id and y."tenant_id" = record_gift.tenant;
    if not found or v_pledge."donor_type" <> record_gift.donor_type or v_pledge."donor_id" <> record_gift.donor_id
      or v_pledge."currency" <> record_gift.currency or record_gift.period_start is null then
      raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
    end if;
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "received_on", "method", "note", "created_by")
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge."fund_id"), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = record_gift.pledge_id and x."period_start" = record_gift.period_start;
  end if;
  return "better_supabase"."donation_settle"(v_row."id", 'succeeded');
end;
$$;
revoke execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) from public, anon;
grant execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) to authenticated, service_role;

-- Opens a pending gift a payments provider will charge. With a pledge and
-- period a second call returns the same gift, so a retried charge run never
-- charges a period twice. fields: the extra columns to set.
drop function if exists "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text, jsonb);
create or replace function "better_supabase"."open_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if open_gift.donor_type is null or open_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if open_gift.amount is null or open_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.currency is null or open_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = open_gift.fund_id and y."tenant_id" = open_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from "better_supabase"."pledges" y where y."id" = open_gift.pledge_id and y."tenant_id" = open_gift.tenant
      and y."donor_type" = open_gift.donor_type and y."donor_id" = open_gift.donor_id and y."currency" = open_gift.currency
  )) then
    raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "method", "provider", "note", "created_by")
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = open_gift.pledge_id and x."period_start" = open_gift.period_start;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) from public, anon;
grant execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) to authenticated, service_role;

-- Records what the payments provider reported for a gift: by its id, or
-- (gift_id null) by the provider's payment id. succeeded posts it, failed
-- marks it, refunded reverses it. A webhook calls it with the service role.
create or replace function "better_supabase"."record_gift_payment"(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if record_gift_payment.gift_id is not null then
    select * into v_row from "better_supabase"."donations" x where x."id" = record_gift_payment.gift_id;
  else
    select * into v_row from "better_supabase"."donations" x
      where x."provider" = record_gift_payment.provider and x."payment_reference" = record_gift_payment.payment_id;
  end if;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return "better_supabase"."donation_settle"(v_row."id", record_gift_payment.status, record_gift_payment.provider, record_gift_payment.payment_id);
end;
$$;
revoke execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."get_gift"(gift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = get_gift.gift_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_gift"(uuid) from public, anon;
grant execute on function "better_supabase"."get_gift"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_gifts"(tenant uuid, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_gifts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'pledgeId', q."pledge_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', q."currency", 'receivedOn', q."received_on", 'method', q."method", 'status', q."status", 'provider', q."provider", 'paymentReference', q."payment_reference", 'transactionId', q."transaction_id", 'refundTransactionId', q."refund_transaction_id", 'receiptId', q."receipt_id", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."received_on" desc, q."created_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (list_gifts.donor_type is null or (x."donor_type" = list_gifts.donor_type and x."donor_id" = list_gifts.donor_id))
        and (list_gifts.fund_id is null or x."fund_id" = list_gifts.fund_id)
        and (list_gifts.pledge_id is null or x."pledge_id" = list_gifts.pledge_id)
        and (list_gifts.status is null or x."status" = list_gifts.status)
      order by x."received_on" desc, x."created_at" desc
      limit least(greatest(coalesce(list_gifts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."create_pledge"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_pledge.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if create_pledge.donor_type is null or create_pledge.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if create_pledge.amount is null or create_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.currency is null or create_pledge.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = create_pledge.fund_id and y."tenant_id" = create_pledge.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id", "fund_id", "amount", "currency", "frequency",
    "starts_on", "ends_on", "provider", "provider_customer", "note", "created_by")
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    coalesce(create_pledge.frequency, 'monthly'), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) to authenticated, service_role;

-- Pauses, resumes or ends a pledge, moves its end or changes its amount for
-- installments from now on. Null keeps a value.
create or replace function "better_supabase"."update_pledge"(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."pledges" x where x."id" = update_pledge.pledge_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such pledge you can manage' using errcode = 'P0002', hint = 'DONATION_PLEDGE_NOT_FOUND';
  end if;
  if update_pledge.status is not null and update_pledge.status not in ('active', 'paused', 'ended') then
    raise exception 'status is active, paused or ended' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if v_row."status" = 'ended' and coalesce(update_pledge.status, 'ended') <> 'ended' then
    raise exception 'an ended pledge can''t restart; create a new one' using errcode = '55000', hint = 'DONATION_PLEDGE_ENDED';
  end if;
  if update_pledge.ends_on is not null and update_pledge.ends_on <= v_row."starts_on" then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if update_pledge.amount is not null and update_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  update "better_supabase"."pledges" x set
      "status" = coalesce(update_pledge.status, x."status"),
      "ends_on" = coalesce(update_pledge.ends_on, x."ends_on"),
      "amount" = coalesce(update_pledge.amount, x."amount"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."list_pledges"(tenant uuid, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_pledges.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'amount', q."amount"::text, 'currency', q."currency", 'frequency', q."frequency", 'startsOn', q."starts_on", 'endsOn', q."ends_on", 'status', q."status", 'provider', q."provider", 'providerCustomer', q."provider_customer", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (list_pledges.donor_type is null or (x."donor_type" = list_pledges.donor_type and x."donor_id" = list_pledges.donor_id))
        and (list_pledges.status is null or x."status" = list_pledges.status)
      order by x."created_at" desc, x."id"
      limit least(greatest(coalesce(list_pledges.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) to authenticated, service_role;

-- The installments of active pledges that start on or before through
-- (default today) and have no gift yet, oldest first, up to max_rows. A
-- gift opened but never charged (pending without a payment) stays due, so
-- the next run charges it under the same idempotency key; a declined one
-- doesn't.
create or replace function "better_supabase"."due_pledge_installments"(tenant uuid, through date default null, max_rows integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(due_pledge_installments.through, current_date);
  v_max integer := least(greatest(coalesce(due_pledge_installments.max_rows, 500), 1), 5000);
  v_row "better_supabase"."pledges"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_start date;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', due_pledge_installments.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  <<installments>>
  for v_row in
    select * from "better_supabase"."pledges" x
    where x."tenant_id" = due_pledge_installments.tenant and x."status" = 'active' and x."starts_on" <= v_through
    order by x."starts_on", x."id"
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."donations" g where g."pledge_id" = v_row."id" and g."period_start" = v_start
        and not (g."status" = 'pending' and g."payment_reference" is null)) then
        exit installments when jsonb_array_length(v_items) >= v_max;
        v_items := v_items || jsonb_build_array(jsonb_build_object('periodStart', v_start, 'pledgeId', v_row."id",
          'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id",
          'amount', v_row."amount"::text, 'currency', v_row."currency",
          'provider', v_row."provider", 'providerCustomer', v_row."provider_customer"));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_items;
end;
$$;
revoke execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) to authenticated, service_role;

-- Issues a numbered tax receipt for one posted gift. Numbers come from
-- numbering when it configures donation_receipt, else one more than
-- the organization's highest.
create or replace function "better_supabase"."issue_gift_receipt"(gift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donations" x where x."id" = issue_gift_receipt.gift_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted gift gets a receipt' using errcode = '55000', hint = 'DONATION_STATUS_INVALID';
  end if;
  if v_row."receipt_id" is not null then
    select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = v_row."receipt_id";
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_row."tenant_id", 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_row."tenant_id", 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (v_row."tenant_id", v_row."donor_type", v_row."donor_id", v_seq, v_number, 'gift', extract(year from v_row."received_on")::integer,
    v_row."amount", v_row."currency")
  returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = v_receipt."id", "updated_at" = now() where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_gift_receipt"(uuid) from public, anon;
grant execute on function "better_supabase"."issue_gift_receipt"(uuid) to authenticated, service_role;

-- Issues a donor's yearly tax receipt: their posted gifts received in year
-- in currency. A second call returns the receipt until it is voided.
create or replace function "better_supabase"."issue_yearly_receipt"(tenant uuid, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_yearly_receipt.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    raise exception 'a yearly receipt needs a year and a currency' using errcode = '22023', hint = 'DONATION_RECEIPT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from "better_supabase"."donation_receipts" x
    where x."tenant_id" = issue_yearly_receipt.tenant and x."donor_type" = issue_yearly_receipt.donor_type
      and x."donor_id" = issue_yearly_receipt.donor_id and x."year" = issue_yearly_receipt.year
      and x."currency" = issue_yearly_receipt.currency and x."kind" = 'yearly' and x."voided_at" is null;
  if found then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  select coalesce(sum(g."amount"), 0) into v_amount from "better_supabase"."donations" g
    where g."tenant_id" = issue_yearly_receipt.tenant and g."donor_type" = issue_yearly_receipt.donor_type
      and g."donor_id" = issue_yearly_receipt.donor_id and g."currency" = issue_yearly_receipt.currency
      and g."status" = 'posted' and extract(year from g."received_on")::integer = issue_yearly_receipt.year;
  if v_amount <= 0 then
    raise exception 'the donor has no posted gifts in this year and currency' using errcode = '22023', hint = 'DONATION_RECEIPT_EMPTY';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(issue_yearly_receipt.tenant, 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(issue_yearly_receipt.tenant, 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) from public, anon;
grant execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) to authenticated, service_role;

-- Voids a receipt; its number stays used. A voided gift receipt frees the
-- gift for a new one.
create or replace function "better_supabase"."void_donation_receipt"(receipt_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = void_donation_receipt.receipt_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_receipt."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such receipt you can manage' using errcode = 'P0002', hint = 'DONATION_RECEIPT_NOT_FOUND';
  end if;
  if v_receipt."voided_at" is not null then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = nullif(trim(void_donation_receipt.reason), '')
    where x."id" = v_receipt."id"
    returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = null, "updated_at" = now() where x."receipt_id" = v_receipt."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."void_donation_receipt"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_donation_receipt"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."list_donation_receipts"(tenant uuid, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_receipts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'sequence', q."sequence"::text, 'number', q."number", 'kind', q."kind", 'year', q."year", 'amount', q."amount"::text, 'currency', q."currency", 'issuedAt', q."issued_at", 'voidedAt', q."voided_at", 'voidReason', q."void_reason") order by q."issued_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."donation_receipts" x
      where x."tenant_id" = list_donation_receipts.tenant
        and (list_donation_receipts.donor_type is null or (x."donor_type" = list_donation_receipts.donor_type and x."donor_id" = list_donation_receipts.donor_id))
        and (list_donation_receipts.year is null or x."year" = list_donation_receipts.year)
      order by x."issued_at" desc, x."id"
      limit least(greatest(coalesce(list_donation_receipts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) to authenticated, service_role;

-- A donor's giving in a year (default this one): posted totals per
-- currency, per fund, and the receipts issued for the year.
create or replace function "better_supabase"."yearly_giving_summary"(tenant uuid, donor_type text, donor_id text, year integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_year integer := coalesce(yearly_giving_summary.year, extract(year from current_date)::integer);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', yearly_giving_summary.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'year', v_year,
    'donorType', yearly_giving_summary.donor_type,
    'donorId', yearly_giving_summary.donor_id,
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object('currency', q.currency, 'amount', q.amount::text, 'gifts', q.gifts) order by q.currency), '[]'::jsonb)
      from (
        select g."currency" as currency, sum(g."amount") as amount, count(*) as gifts
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."currency"
      ) q
    ),
    'funds', (
      select coalesce(jsonb_agg(jsonb_build_object('fundId', q.fund, 'name', coalesce(y."name", 'General'), 'currency', q.currency, 'amount', q.amount::text)
        order by coalesce(y."name", ''), q.currency), '[]'::jsonb)
      from (
        select g."fund_id" as fund, g."currency" as currency, sum(g."amount") as amount
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."fund_id", g."currency"
      ) q
      left join "better_supabase"."donation_funds" y on y."id" = q.fund
    ),
    'receipts', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'sequence', x."sequence"::text, 'number', x."number", 'kind', x."kind", 'year', x."year", 'amount', x."amount"::text, 'currency', x."currency", 'issuedAt', x."issued_at", 'voidedAt', x."voided_at", 'voidReason', x."void_reason") order by x."issued_at"), '[]'::jsonb)
      from "better_supabase"."donation_receipts" x
      where x."tenant_id" = yearly_giving_summary.tenant and x."donor_type" = yearly_giving_summary.donor_type
        and x."donor_id" = yearly_giving_summary.donor_id and x."year" = v_year
    )
  );
end;
$$;
revoke execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_select on "better_supabase"."donation_funds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_funds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_update on "better_supabase"."donation_funds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_funds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
create policy bsb_tenant_scope_select on "better_supabase"."pledges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
create policy bsb_tenant_scope_insert on "better_supabase"."pledges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
create policy bsb_tenant_scope_update on "better_supabase"."pledges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
create policy bsb_tenant_scope_delete on "better_supabase"."pledges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_select on "better_supabase"."donation_receipts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_receipts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_update on "better_supabase"."donation_receipts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_receipts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
create policy bsb_tenant_scope_select on "better_supabase"."donations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
create policy bsb_tenant_scope_insert on "better_supabase"."donations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
create policy bsb_tenant_scope_update on "better_supabase"."donations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
create policy bsb_tenant_scope_delete on "better_supabase"."donations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.donations.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date, jsonb);
drop function if exists "api"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text, jsonb);

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

create or replace function "api"."save_donation_fund"(tenant uuid, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_donation_fund"($1, $2, $3, $4, $5, $6, $7, $8) $$;
revoke execute on function "api"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) from public, anon;
grant execute on function "api"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) to authenticated, service_role;

create or replace function "api"."archive_donation_fund"(fund_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_donation_fund"($1) $$;
revoke execute on function "api"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "api"."archive_donation_fund"(uuid) to authenticated, service_role;

create or replace function "api"."list_donation_funds"(tenant uuid, include_archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_donation_funds"($1, $2) $$;
revoke execute on function "api"."list_donation_funds"(uuid, boolean) from public, anon;
grant execute on function "api"."list_donation_funds"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."record_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_gift"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) $$;
revoke execute on function "api"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) from public, anon;
grant execute on function "api"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) to authenticated, service_role;

create or replace function "api"."open_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_gift"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) from public, anon;
grant execute on function "api"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) to authenticated, service_role;

create or replace function "api"."record_gift_payment"(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_gift_payment"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_gift_payment"(uuid, text, text, text) from public, anon;
grant execute on function "api"."record_gift_payment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."get_gift"(gift_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_gift"($1) $$;
revoke execute on function "api"."get_gift"(uuid) from public, anon;
grant execute on function "api"."get_gift"(uuid) to authenticated, service_role;

create or replace function "api"."list_gifts"(tenant uuid, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_gifts"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) from public, anon;
grant execute on function "api"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function "api"."create_pledge"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_pledge"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $$;
revoke execute on function "api"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) from public, anon;
grant execute on function "api"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) to authenticated, service_role;

create or replace function "api"."update_pledge"(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_pledge"($1, $2, $3, $4) $$;
revoke execute on function "api"."update_pledge"(uuid, text, date, bigint) from public, anon;
grant execute on function "api"."update_pledge"(uuid, text, date, bigint) to authenticated, service_role;

create or replace function "api"."list_pledges"(tenant uuid, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_pledges"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_pledges"(uuid, text, text, text, integer) from public, anon;
grant execute on function "api"."list_pledges"(uuid, text, text, text, integer) to authenticated, service_role;

create or replace function "api"."due_pledge_installments"(tenant uuid, through date default null, max_rows integer default 500)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."due_pledge_installments"($1, $2, $3) $$;
revoke execute on function "api"."due_pledge_installments"(uuid, date, integer) from public, anon;
grant execute on function "api"."due_pledge_installments"(uuid, date, integer) to authenticated, service_role;

create or replace function "api"."issue_gift_receipt"(gift_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."issue_gift_receipt"($1) $$;
revoke execute on function "api"."issue_gift_receipt"(uuid) from public, anon;
grant execute on function "api"."issue_gift_receipt"(uuid) to authenticated, service_role;

create or replace function "api"."issue_yearly_receipt"(tenant uuid, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."issue_yearly_receipt"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."issue_yearly_receipt"(uuid, text, text, integer, text) from public, anon;
grant execute on function "api"."issue_yearly_receipt"(uuid, text, text, integer, text) to authenticated, service_role;

create or replace function "api"."void_donation_receipt"(receipt_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."void_donation_receipt"($1, $2) $$;
revoke execute on function "api"."void_donation_receipt"(uuid, text) from public, anon;
grant execute on function "api"."void_donation_receipt"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_donation_receipts"(tenant uuid, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_donation_receipts"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."list_donation_receipts"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "api"."list_donation_receipts"(uuid, text, text, integer, integer) to authenticated, service_role;

create or replace function "api"."yearly_giving_summary"(tenant uuid, donor_type text, donor_id text, year integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."yearly_giving_summary"($1, $2, $3, $4) $$;
revoke execute on function "api"."yearly_giving_summary"(uuid, text, text, integer) from public, anon;
grant execute on function "api"."yearly_giving_summary"(uuid, text, text, integer) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:766adfa3e7067c6f8172269a3181465a320dd4dc98f6ab433fc4ba3e69980c75
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block donations@2 managed
-- @bsb-hash sha256:ab174b6ea2043327799041db43219e22d24d6602ca377530e43552c2d03b4626
-- Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Donations: gifts and pledges from donors (registered subjects) to funds
-- and campaigns, each posted gift on the ledger, and numbered tax receipts.

-- A fund or campaign gifts go to; goal is in minor units of currency.
-- better_supabase.donation_funds is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."donation_funds" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."donation_funds" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."donation_funds" add column if not exists "key" text check ("key" ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."donation_funds" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."donation_funds" add column if not exists "kind" text not null default 'fund' check ("kind" in ('fund', 'campaign'));
alter table "better_supabase"."donation_funds" add column if not exists "goal" bigint check ("goal" is null or "goal" > 0);
alter table "better_supabase"."donation_funds" add column if not exists "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."donation_funds" add column if not exists "starts_on" date;
alter table "better_supabase"."donation_funds" add column if not exists "ends_on" date;
alter table "better_supabase"."donation_funds" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."donation_funds" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."donation_funds" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "donation_funds_tenant_id_key_key" on "better_supabase"."donation_funds" ("tenant_id", "key");
create unique index if not exists "donation_funds_tenant_id_id_key" on "better_supabase"."donation_funds" ("tenant_id", "id");
alter table "better_supabase"."donation_funds" enable row level security;
grant select on "better_supabase"."donation_funds" to authenticated;
grant all on "better_supabase"."donation_funds" to service_role;
drop policy if exists bsb_donation_funds_select on "better_supabase"."donation_funds";
create policy bsb_donation_funds_select on "better_supabase"."donation_funds"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A recurring gift: amount every period of frequency, charged through the
-- payments provider when provider is set, recorded by hand otherwise.
-- better_supabase.pledges is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."pledges" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."pledges" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."pledges" add column if not exists "donor_type" text;
alter table "better_supabase"."pledges" add column if not exists "donor_id" text;
alter table "better_supabase"."pledges" add column if not exists "fund_id" uuid;
alter table "better_supabase"."pledges" add column if not exists "amount" bigint check ("amount" > 0);
alter table "better_supabase"."pledges" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."pledges" add column if not exists "frequency" text not null default 'monthly' check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly'));
alter table "better_supabase"."pledges" add column if not exists "starts_on" date;
alter table "better_supabase"."pledges" add column if not exists "ends_on" date;
alter table "better_supabase"."pledges" add column if not exists "status" text not null default 'active' check ("status" in ('active', 'paused', 'ended'));
alter table "better_supabase"."pledges" add column if not exists "provider" text;
alter table "better_supabase"."pledges" add column if not exists "provider_customer" text;
alter table "better_supabase"."pledges" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."pledges" add column if not exists "created_by" uuid;
alter table "better_supabase"."pledges" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."pledges" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "pledges_tenant_idx" on "better_supabase"."pledges" ("tenant_id", "status");
create index if not exists "pledges_donor_idx" on "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id");
create index if not exists "pledges_fund_idx" on "better_supabase"."pledges" ("tenant_id", "fund_id") where "fund_id" is not null;
alter table "better_supabase"."pledges" enable row level security;
grant select on "better_supabase"."pledges" to authenticated;
grant all on "better_supabase"."pledges" to service_role;
drop policy if exists bsb_pledges_select on "better_supabase"."pledges";
create policy bsb_pledges_select on "better_supabase"."pledges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A tax receipt: one gift, or a donor's posted gifts in a year and currency.
-- better_supabase.donation_receipts is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."donation_receipts" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."donation_receipts" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."donation_receipts" add column if not exists "donor_type" text;
alter table "better_supabase"."donation_receipts" add column if not exists "donor_id" text;
alter table "better_supabase"."donation_receipts" add column if not exists "sequence" bigint;
alter table "better_supabase"."donation_receipts" add column if not exists "number" text;
alter table "better_supabase"."donation_receipts" add column if not exists "kind" text check ("kind" in ('gift', 'yearly'));
alter table "better_supabase"."donation_receipts" add column if not exists "year" integer;
alter table "better_supabase"."donation_receipts" add column if not exists "amount" bigint check ("amount" > 0);
alter table "better_supabase"."donation_receipts" add column if not exists "currency" char(3);
alter table "better_supabase"."donation_receipts" add column if not exists "issued_at" timestamptz not null default now();
alter table "better_supabase"."donation_receipts" add column if not exists "voided_at" timestamptz;
alter table "better_supabase"."donation_receipts" add column if not exists "void_reason" text check ("void_reason" is null or length("void_reason") <= 2000);
create index if not exists "donation_receipts_donor_idx" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year");
create unique index if not exists "donation_receipts_yearly_key" on "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "year", "currency")
  where "kind" = 'yearly' and "voided_at" is null;
alter table "better_supabase"."donation_receipts" enable row level security;
grant select on "better_supabase"."donation_receipts" to authenticated;
grant all on "better_supabase"."donation_receipts" to service_role;
drop policy if exists bsb_donation_receipts_select on "better_supabase"."donation_receipts";
create policy bsb_donation_receipts_select on "better_supabase"."donation_receipts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- better_supabase.donations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."donations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."donations" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."donations" add column if not exists "donor_type" text;
alter table "better_supabase"."donations" add column if not exists "donor_id" text;
alter table "better_supabase"."donations" add column if not exists "fund_id" uuid;
alter table "better_supabase"."donations" add column if not exists "pledge_id" uuid references "better_supabase"."pledges" ("id") on delete set null;
alter table "better_supabase"."donations" add column if not exists "period_start" date;
alter table "better_supabase"."donations" add column if not exists "amount" bigint check ("amount" > 0);
alter table "better_supabase"."donations" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."donations" add column if not exists "received_on" date not null default current_date;
alter table "better_supabase"."donations" add column if not exists "method" text check ("method" is null or length("method") <= 40);
alter table "better_supabase"."donations" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'posted', 'failed', 'refunded'));
alter table "better_supabase"."donations" add column if not exists "provider" text;
alter table "better_supabase"."donations" add column if not exists "payment_reference" text;
alter table "better_supabase"."donations" add column if not exists "transaction_id" uuid;
alter table "better_supabase"."donations" add column if not exists "refund_transaction_id" uuid;
alter table "better_supabase"."donations" add column if not exists "receipt_id" uuid references "better_supabase"."donation_receipts" ("id") on delete set null;
alter table "better_supabase"."donations" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."donations" add column if not exists "created_by" uuid;
alter table "better_supabase"."donations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."donations" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "donations_pledge_id_period_start_key" on "better_supabase"."donations" ("pledge_id", "period_start");
create index if not exists "donations_tenant_idx" on "better_supabase"."donations" ("tenant_id", "received_on" desc);
create index if not exists "donations_donor_idx" on "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "received_on");
create index if not exists "donations_fund_idx" on "better_supabase"."donations" ("tenant_id", "fund_id") where "fund_id" is not null;
create index if not exists "donations_receipt_idx" on "better_supabase"."donations" ("receipt_id") where "receipt_id" is not null;
create index if not exists "donations_transaction_idx" on "better_supabase"."donations" ("transaction_id") where "transaction_id" is not null;
create index if not exists "donations_refund_idx" on "better_supabase"."donations" ("refund_transaction_id") where "refund_transaction_id" is not null;
create unique index if not exists "donations_payment_key" on "better_supabase"."donations" ("provider", "payment_reference")
  where "payment_reference" is not null;
alter table "better_supabase"."donations" enable row level security;
grant select on "better_supabase"."donations" to authenticated;
grant all on "better_supabase"."donations" to service_role;
drop policy if exists bsb_donations_select on "better_supabase"."donations";
create policy bsb_donations_select on "better_supabase"."donations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- Creates or updates the fund or campaign with this key.
create or replace function "better_supabase"."save_donation_fund"(tenant uuid, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_donation_fund.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if save_donation_fund.key is null or save_donation_fund.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if nullif(trim(save_donation_fund.name), '') is null then
    raise exception 'a fund needs a name' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(save_donation_fund.kind, 'fund') not in ('fund', 'campaign') then
    raise exception 'kind is fund or campaign' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.goal is not null and (save_donation_fund.goal <= 0 or save_donation_fund.currency is null or save_donation_fund.currency !~ '^[A-Z]{3}$') then
    raise exception 'a goal is more than zero minor units of a three-letter currency' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.starts_on is not null and save_donation_fund.ends_on is not null and save_donation_fund.ends_on < save_donation_fund.starts_on then
    raise exception 'ends_on is on or after starts_on' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  insert into "better_supabase"."donation_funds" ("tenant_id", "key", "name", "kind", "goal", "currency", "starts_on", "ends_on")
  values (save_donation_fund.tenant, save_donation_fund.key, trim(save_donation_fund.name), better_supabase.as_column_type(coalesce(save_donation_fund.kind, 'fund'), (null::"better_supabase"."donation_funds")."kind"),
    save_donation_fund.goal, save_donation_fund.currency, save_donation_fund.starts_on, save_donation_fund.ends_on)
  on conflict ("tenant_id", "key") do update set
    "name" = excluded."name", "kind" = excluded."kind", "goal" = excluded."goal",
    "currency" = excluded."currency", "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on",
    "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) from public, anon;
grant execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) to authenticated, service_role;

create or replace function "better_supabase"."archive_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donation_funds" x where x."id" = archive_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "better_supabase"."donation_funds" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_donation_fund"(uuid) to authenticated, service_role;

-- Funds and campaigns with what they raised: posted gifts in the goal's
-- currency.
create or replace function "better_supabase"."list_donation_funds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_funds.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'goal', x."goal"::text, 'currency', x."currency", 'raised', case when x."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = x."id" and g."status" = 'posted' and g."currency" = x."currency"), 0)::text end, 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
    from "better_supabase"."donation_funds" x
    where x."tenant_id" = list_donation_funds.tenant
      and (coalesce(list_donation_funds.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_funds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_donation_funds"(uuid, boolean) to authenticated, service_role;

-- Moves a gift along: pending stores the payment, succeeded posts it on
-- the ledger (cash in, fund income out), failed marks a pending gift, and
-- refunded reverses a posted one and voids its gift receipt. Each posting
-- carries a key per gift, so a repeat changes nothing. Internal.
create or replace function "better_supabase"."donation_settle"(gift_id uuid, status text, provider text default null, payment_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_fund "better_supabase"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "better_supabase"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "better_supabase"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "better_supabase"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"));
    update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "better_supabase"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."donation_settle"(uuid, text, text, text) from public, anon, authenticated;

-- Records a gift received outside a payments provider (cash, a check, a
-- bank transfer) and posts it at once. With a pledge and period it pays
-- that installment; a second call for the same period returns the gift.
-- fields: the extra columns to set.
drop function if exists "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date, jsonb);
create or replace function "better_supabase"."record_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_pledge "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if record_gift.donor_type is null or record_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if record_gift.amount is null or record_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.currency is null or record_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = record_gift.fund_id and y."tenant_id" = record_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if record_gift.pledge_id is not null then
    select * into v_pledge from "better_supabase"."pledges" y where y."id" = record_gift.pledge_id and y."tenant_id" = record_gift.tenant;
    if not found or v_pledge."donor_type" <> record_gift.donor_type or v_pledge."donor_id" <> record_gift.donor_id
      or v_pledge."currency" <> record_gift.currency or record_gift.period_start is null then
      raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
    end if;
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "received_on", "method", "note", "created_by")
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge."fund_id"), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = record_gift.pledge_id and x."period_start" = record_gift.period_start;
  end if;
  return "better_supabase"."donation_settle"(v_row."id", 'succeeded');
end;
$$;
revoke execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) from public, anon;
grant execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) to authenticated, service_role;

-- Opens a pending gift a payments provider will charge. With a pledge and
-- period a second call returns the same gift, so a retried charge run never
-- charges a period twice. fields: the extra columns to set.
drop function if exists "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text, jsonb);
create or replace function "better_supabase"."open_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if open_gift.donor_type is null or open_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if open_gift.amount is null or open_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.currency is null or open_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = open_gift.fund_id and y."tenant_id" = open_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from "better_supabase"."pledges" y where y."id" = open_gift.pledge_id and y."tenant_id" = open_gift.tenant
      and y."donor_type" = open_gift.donor_type and y."donor_id" = open_gift.donor_id and y."currency" = open_gift.currency
  )) then
    raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."donations" ("tenant_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "method", "provider", "note", "created_by")
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = open_gift.pledge_id and x."period_start" = open_gift.period_start;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) from public, anon;
grant execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) to authenticated, service_role;

-- Records what the payments provider reported for a gift: by its id, or
-- (gift_id null) by the provider's payment id. succeeded posts it, failed
-- marks it, refunded reverses it. A webhook calls it with the service role.
create or replace function "better_supabase"."record_gift_payment"(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if record_gift_payment.gift_id is not null then
    select * into v_row from "better_supabase"."donations" x where x."id" = record_gift_payment.gift_id;
  else
    select * into v_row from "better_supabase"."donations" x
      where x."provider" = record_gift_payment.provider and x."payment_reference" = record_gift_payment.payment_id;
  end if;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return "better_supabase"."donation_settle"(v_row."id", record_gift_payment.status, record_gift_payment.provider, record_gift_payment.payment_id);
end;
$$;
revoke execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."get_gift"(gift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = get_gift.gift_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_gift"(uuid) from public, anon;
grant execute on function "better_supabase"."get_gift"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_gifts"(tenant uuid, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_gifts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'pledgeId', q."pledge_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', q."currency", 'receivedOn', q."received_on", 'method', q."method", 'status', q."status", 'provider', q."provider", 'paymentReference', q."payment_reference", 'transactionId', q."transaction_id", 'refundTransactionId', q."refund_transaction_id", 'receiptId', q."receipt_id", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."received_on" desc, q."created_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."donations" x
      where x."tenant_id" = list_gifts.tenant
        and (list_gifts.donor_type is null or (x."donor_type" = list_gifts.donor_type and x."donor_id" = list_gifts.donor_id))
        and (list_gifts.fund_id is null or x."fund_id" = list_gifts.fund_id)
        and (list_gifts.pledge_id is null or x."pledge_id" = list_gifts.pledge_id)
        and (list_gifts.status is null or x."status"::text = list_gifts.status)
      order by x."received_on" desc, x."created_at" desc
      limit least(greatest(coalesce(list_gifts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."create_pledge"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_pledge.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if create_pledge.donor_type is null or create_pledge.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if create_pledge.amount is null or create_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.currency is null or create_pledge.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = create_pledge.fund_id and y."tenant_id" = create_pledge.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."pledges" ("tenant_id", "donor_type", "donor_id", "fund_id", "amount", "currency", "frequency",
    "starts_on", "ends_on", "provider", "provider_customer", "note", "created_by")
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    better_supabase.as_column_type(coalesce(create_pledge.frequency, 'monthly'), (null::"better_supabase"."pledges")."frequency"), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) to authenticated, service_role;

-- Pauses, resumes or ends a pledge, moves its end or changes its amount for
-- installments from now on. Null keeps a value.
create or replace function "better_supabase"."update_pledge"(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."pledges" x where x."id" = update_pledge.pledge_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such pledge you can manage' using errcode = 'P0002', hint = 'DONATION_PLEDGE_NOT_FOUND';
  end if;
  if update_pledge.status is not null and update_pledge.status not in ('active', 'paused', 'ended') then
    raise exception 'status is active, paused or ended' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if v_row."status" = 'ended' and coalesce(update_pledge.status, 'ended') <> 'ended' then
    raise exception 'an ended pledge can''t restart; create a new one' using errcode = '55000', hint = 'DONATION_PLEDGE_ENDED';
  end if;
  if update_pledge.ends_on is not null and update_pledge.ends_on <= v_row."starts_on" then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if update_pledge.amount is not null and update_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  update "better_supabase"."pledges" x set
      "status" = better_supabase.as_column_type(coalesce(update_pledge.status, x."status"::text), (null::"better_supabase"."pledges")."status"),
      "ends_on" = coalesce(update_pledge.ends_on, x."ends_on"),
      "amount" = coalesce(update_pledge.amount, x."amount"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."list_pledges"(tenant uuid, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_pledges.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'amount', q."amount"::text, 'currency', q."currency", 'frequency', q."frequency", 'startsOn', q."starts_on", 'endsOn', q."ends_on", 'status', q."status", 'provider', q."provider", 'providerCustomer', q."provider_customer", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."pledges" x
      where x."tenant_id" = list_pledges.tenant
        and (list_pledges.donor_type is null or (x."donor_type" = list_pledges.donor_type and x."donor_id" = list_pledges.donor_id))
        and (list_pledges.status is null or x."status"::text = list_pledges.status)
      order by x."created_at" desc, x."id"
      limit least(greatest(coalesce(list_pledges.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) to authenticated, service_role;

-- The installments of active pledges that start on or before through
-- (default today) and have no gift yet, oldest first, up to max_rows. A
-- gift opened but never charged (pending without a payment) stays due, so
-- the next run charges it under the same idempotency key; a declined one
-- doesn't.
create or replace function "better_supabase"."due_pledge_installments"(tenant uuid, through date default null, max_rows integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(due_pledge_installments.through, current_date);
  v_max integer := least(greatest(coalesce(due_pledge_installments.max_rows, 500), 1), 5000);
  v_row "better_supabase"."pledges"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_start date;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', due_pledge_installments.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  <<installments>>
  for v_row in
    select * from "better_supabase"."pledges" x
    where x."tenant_id" = due_pledge_installments.tenant and x."status" = 'active' and x."starts_on" <= v_through
    order by x."starts_on", x."id"
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."donations" g where g."pledge_id" = v_row."id" and g."period_start" = v_start
        and not (g."status" = 'pending' and g."payment_reference" is null)) then
        exit installments when jsonb_array_length(v_items) >= v_max;
        v_items := v_items || jsonb_build_array(jsonb_build_object('periodStart', v_start, 'pledgeId', v_row."id",
          'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id",
          'amount', v_row."amount"::text, 'currency', v_row."currency",
          'provider', v_row."provider", 'providerCustomer', v_row."provider_customer"));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_items;
end;
$$;
revoke execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) to authenticated, service_role;

-- Issues a numbered tax receipt for one posted gift. Numbers come from
-- numbering when it configures donation_receipt, else one more than
-- the organization's highest.
create or replace function "better_supabase"."issue_gift_receipt"(gift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donations" x where x."id" = issue_gift_receipt.gift_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted gift gets a receipt' using errcode = '55000', hint = 'DONATION_STATUS_INVALID';
  end if;
  if v_row."receipt_id" is not null then
    select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = v_row."receipt_id";
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_row."tenant_id", 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_row."tenant_id", 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (v_row."tenant_id", v_row."donor_type", v_row."donor_id", v_seq, v_number, 'gift', extract(year from v_row."received_on")::integer,
    v_row."amount", v_row."currency")
  returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = v_receipt."id", "updated_at" = now() where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_gift_receipt"(uuid) from public, anon;
grant execute on function "better_supabase"."issue_gift_receipt"(uuid) to authenticated, service_role;

-- Issues a donor's yearly tax receipt: their posted gifts received in year
-- in currency. A second call returns the receipt until it is voided.
create or replace function "better_supabase"."issue_yearly_receipt"(tenant uuid, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_yearly_receipt.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    raise exception 'a yearly receipt needs a year and a currency' using errcode = '22023', hint = 'DONATION_RECEIPT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from "better_supabase"."donation_receipts" x
    where x."tenant_id" = issue_yearly_receipt.tenant and x."donor_type" = issue_yearly_receipt.donor_type
      and x."donor_id" = issue_yearly_receipt.donor_id and x."year" = issue_yearly_receipt.year
      and x."currency" = issue_yearly_receipt.currency and x."kind" = 'yearly' and x."voided_at" is null;
  if found then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  select coalesce(sum(g."amount"), 0) into v_amount from "better_supabase"."donations" g
    where g."tenant_id" = issue_yearly_receipt.tenant and g."donor_type" = issue_yearly_receipt.donor_type
      and g."donor_id" = issue_yearly_receipt.donor_id and g."currency" = issue_yearly_receipt.currency
      and g."status" = 'posted' and extract(year from g."received_on")::integer = issue_yearly_receipt.year;
  if v_amount <= 0 then
    raise exception 'the donor has no posted gifts in this year and currency' using errcode = '22023', hint = 'DONATION_RECEIPT_EMPTY';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(issue_yearly_receipt.tenant, 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(issue_yearly_receipt.tenant, 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) from public, anon;
grant execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) to authenticated, service_role;

-- Voids a receipt; its number stays used. A voided gift receipt frees the
-- gift for a new one.
create or replace function "better_supabase"."void_donation_receipt"(receipt_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = void_donation_receipt.receipt_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_receipt."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such receipt you can manage' using errcode = 'P0002', hint = 'DONATION_RECEIPT_NOT_FOUND';
  end if;
  if v_receipt."voided_at" is not null then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = nullif(trim(void_donation_receipt.reason), '')
    where x."id" = v_receipt."id"
    returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = null, "updated_at" = now() where x."receipt_id" = v_receipt."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."void_donation_receipt"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_donation_receipt"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."list_donation_receipts"(tenant uuid, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_receipts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'sequence', q."sequence"::text, 'number', q."number", 'kind', q."kind", 'year', q."year", 'amount', q."amount"::text, 'currency', q."currency", 'issuedAt', q."issued_at", 'voidedAt', q."voided_at", 'voidReason', q."void_reason") order by q."issued_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."donation_receipts" x
      where x."tenant_id" = list_donation_receipts.tenant
        and (list_donation_receipts.donor_type is null or (x."donor_type" = list_donation_receipts.donor_type and x."donor_id" = list_donation_receipts.donor_id))
        and (list_donation_receipts.year is null or x."year" = list_donation_receipts.year)
      order by x."issued_at" desc, x."id"
      limit least(greatest(coalesce(list_donation_receipts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) to authenticated, service_role;

-- A donor's giving in a year (default this one): posted totals per
-- currency, per fund, and the receipts issued for the year.
create or replace function "better_supabase"."yearly_giving_summary"(tenant uuid, donor_type text, donor_id text, year integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_year integer := coalesce(yearly_giving_summary.year, extract(year from current_date)::integer);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', yearly_giving_summary.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'year', v_year,
    'donorType', yearly_giving_summary.donor_type,
    'donorId', yearly_giving_summary.donor_id,
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object('currency', q.currency, 'amount', q.amount::text, 'gifts', q.gifts) order by q.currency), '[]'::jsonb)
      from (
        select g."currency" as currency, sum(g."amount") as amount, count(*) as gifts
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."currency"
      ) q
    ),
    'funds', (
      select coalesce(jsonb_agg(jsonb_build_object('fundId', q.fund, 'name', coalesce(y."name", 'General'), 'currency', q.currency, 'amount', q.amount::text)
        order by coalesce(y."name", ''), q.currency), '[]'::jsonb)
      from (
        select g."fund_id" as fund, g."currency" as currency, sum(g."amount") as amount
        from "better_supabase"."donations" g
        where g."tenant_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."fund_id", g."currency"
      ) q
      left join "better_supabase"."donation_funds" y on y."id" = q.fund
    ),
    'receipts', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'sequence', x."sequence"::text, 'number', x."number", 'kind', x."kind", 'year', x."year", 'amount', x."amount"::text, 'currency', x."currency", 'issuedAt', x."issued_at", 'voidedAt', x."voided_at", 'voidReason', x."void_reason") order by x."issued_at"), '[]'::jsonb)
      from "better_supabase"."donation_receipts" x
      where x."tenant_id" = yearly_giving_summary.tenant and x."donor_type" = yearly_giving_summary.donor_type
        and x."donor_id" = yearly_giving_summary.donor_id and x."year" = v_year
    )
  );
end;
$$;
revoke execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_select on "better_supabase"."donation_funds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_funds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_update on "better_supabase"."donation_funds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_funds" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
create policy bsb_tenant_scope_select on "better_supabase"."pledges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
create policy bsb_tenant_scope_insert on "better_supabase"."pledges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
create policy bsb_tenant_scope_update on "better_supabase"."pledges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
create policy bsb_tenant_scope_delete on "better_supabase"."pledges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_select on "better_supabase"."donation_receipts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_receipts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_update on "better_supabase"."donation_receipts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_receipts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
create policy bsb_tenant_scope_select on "better_supabase"."donations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
create policy bsb_tenant_scope_insert on "better_supabase"."donations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
create policy bsb_tenant_scope_update on "better_supabase"."donations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
create policy bsb_tenant_scope_delete on "better_supabase"."donations" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:766adfa3e7067c6f8172269a3181465a320dd4dc98f6ab433fc4ba3e69980c75
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block donations@2 managed
-- @bsb-hash sha256:5373ce379ff82b7c6631d7958a99476f916b8c3210b7064b58cf8858b0dcbba1
-- Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Donations: gifts and pledges from donors (registered subjects) to funds
-- and campaigns, each posted gift on the ledger, and numbered tax receipts.

-- A fund or campaign gifts go to; goal is in minor units of currency.
create table if not exists "better_supabase"."donation_funds" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "kind" text not null default 'fund' check ("kind" in ('fund', 'campaign')),
  "goal" bigint check ("goal" is null or "goal" > 0),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "starts_on" date,
  "ends_on" date,
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "key"),
  unique ("org_id", "id"),
  check ("goal" is null or "currency" is not null),
  check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on")
);
alter table "better_supabase"."donation_funds" enable row level security;
revoke all on "better_supabase"."donation_funds" from public, anon, authenticated;
grant select on "better_supabase"."donation_funds" to authenticated;
grant all on "better_supabase"."donation_funds" to service_role;
drop policy if exists "donation_funds_read" on "better_supabase"."donation_funds";
create policy donation_funds_read on "better_supabase"."donation_funds"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A recurring gift: amount every period of frequency, charged through the
-- payments provider when provider is set, recorded by hand otherwise.
create table if not exists "better_supabase"."pledges" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "starts_on" date not null,
  "ends_on" date,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'ended')),
  "provider" text,
  "provider_customer" text,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("org_id", "fund_id") references "better_supabase"."donation_funds" ("org_id", "id") on delete restrict,
  check ("ends_on" is null or "ends_on" > "starts_on")
);
create index if not exists "pledges_tenant_idx" on "better_supabase"."pledges" ("org_id", "status");
create index if not exists "pledges_donor_idx" on "better_supabase"."pledges" ("org_id", "donor_type", "donor_id");
create index if not exists "pledges_fund_idx" on "better_supabase"."pledges" ("org_id", "fund_id") where "fund_id" is not null;
alter table "better_supabase"."pledges" enable row level security;
revoke all on "better_supabase"."pledges" from public, anon, authenticated;
grant select on "better_supabase"."pledges" to authenticated;
grant all on "better_supabase"."pledges" to service_role;
drop policy if exists "pledges_read" on "better_supabase"."pledges";
create policy pledges_read on "better_supabase"."pledges"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- A tax receipt: one gift, or a donor's posted gifts in a year and currency.
create table if not exists "better_supabase"."donation_receipts" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "sequence" bigint not null,
  "number" text not null,
  "kind" text not null check ("kind" in ('gift', 'yearly')),
  "year" integer not null,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null,
  "issued_at" timestamptz not null default now(),
  "voided_at" timestamptz,
  "void_reason" text check ("void_reason" is null or length("void_reason") <= 2000),
  unique ("org_id", "number")
);
create index if not exists "donation_receipts_donor_idx" on "better_supabase"."donation_receipts" ("org_id", "donor_type", "donor_id", "year");
create unique index if not exists "donation_receipts_yearly_key" on "better_supabase"."donation_receipts" ("org_id", "donor_type", "donor_id", "year", "currency")
  where "kind" = 'yearly' and "voided_at" is null;
alter table "better_supabase"."donation_receipts" enable row level security;
revoke all on "better_supabase"."donation_receipts" from public, anon, authenticated;
grant select on "better_supabase"."donation_receipts" to authenticated;
grant all on "better_supabase"."donation_receipts" to service_role;
drop policy if exists "donation_receipts_read" on "better_supabase"."donation_receipts";
create policy donation_receipts_read on "better_supabase"."donation_receipts"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('donations.read')));

create table if not exists "better_supabase"."donations" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "donor_type" text not null,
  "donor_id" text not null,
  "fund_id" uuid,
  "pledge_id" uuid references "better_supabase"."pledges" ("id") on delete set null,
  -- The pledge period this gift pays; unique per pledge.
  "period_start" date,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "received_on" date not null default current_date,
  "method" text check ("method" is null or length("method") <= 40),
  "status" text not null default 'pending' check ("status" in ('pending', 'posted', 'failed', 'refunded')),
  "provider" text,
  "payment_reference" text,
  "transaction_id" uuid,
  "refund_transaction_id" uuid,
  "receipt_id" uuid references "better_supabase"."donation_receipts" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  foreign key ("org_id", "fund_id") references "better_supabase"."donation_funds" ("org_id", "id") on delete restrict,
  unique ("pledge_id", "period_start")
);
create index if not exists "donations_tenant_idx" on "better_supabase"."donations" ("org_id", "received_on" desc);
create index if not exists "donations_donor_idx" on "better_supabase"."donations" ("org_id", "donor_type", "donor_id", "received_on");
create index if not exists "donations_fund_idx" on "better_supabase"."donations" ("org_id", "fund_id") where "fund_id" is not null;
create index if not exists "donations_receipt_idx" on "better_supabase"."donations" ("receipt_id") where "receipt_id" is not null;
create index if not exists "donations_transaction_idx" on "better_supabase"."donations" ("transaction_id") where "transaction_id" is not null;
create index if not exists "donations_refund_idx" on "better_supabase"."donations" ("refund_transaction_id") where "refund_transaction_id" is not null;
create unique index if not exists "donations_payment_key" on "better_supabase"."donations" ("provider", "payment_reference")
  where "payment_reference" is not null;
alter table "better_supabase"."donations" enable row level security;
revoke all on "better_supabase"."donations" from public, anon, authenticated;
grant select on "better_supabase"."donations" to authenticated;
grant all on "better_supabase"."donations" to service_role;
drop policy if exists "donations_read" on "better_supabase"."donations";
create policy donations_read on "better_supabase"."donations"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('donations.read')));

-- Creates or updates the fund or campaign with this key.
create or replace function "better_supabase"."save_donation_fund"(tenant uuid, key text, name text, kind text default 'fund', goal bigint default null, currency text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_donation_fund.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if save_donation_fund.key is null or save_donation_fund.key !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a key is lowercase letters, digits and underscores' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if nullif(trim(save_donation_fund.name), '') is null then
    raise exception 'a fund needs a name' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(save_donation_fund.kind, 'fund') not in ('fund', 'campaign') then
    raise exception 'kind is fund or campaign' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.goal is not null and (save_donation_fund.goal <= 0 or save_donation_fund.currency is null or save_donation_fund.currency !~ '^[A-Z]{3}$') then
    raise exception 'a goal is more than zero minor units of a three-letter currency' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if save_donation_fund.starts_on is not null and save_donation_fund.ends_on is not null and save_donation_fund.ends_on < save_donation_fund.starts_on then
    raise exception 'ends_on is on or after starts_on' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  insert into "better_supabase"."donation_funds" ("org_id", "key", "name", "kind", "goal", "currency", "starts_on", "ends_on")
  values (save_donation_fund.tenant, save_donation_fund.key, trim(save_donation_fund.name), coalesce(save_donation_fund.kind, 'fund'),
    save_donation_fund.goal, save_donation_fund.currency, save_donation_fund.starts_on, save_donation_fund.ends_on)
  on conflict ("org_id", "key") do update set
    "name" = excluded."name", "kind" = excluded."kind", "goal" = excluded."goal",
    "currency" = excluded."currency", "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on",
    "archived_at" = null, "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) from public, anon;
grant execute on function "better_supabase"."save_donation_fund"(uuid, text, text, text, bigint, text, date, date) to authenticated, service_role;

create or replace function "better_supabase"."archive_donation_fund"(fund_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donation_funds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donation_funds" x where x."id" = archive_donation_fund.fund_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'donations.manage'), false)) then
    raise exception 'no such fund you can manage' using errcode = 'P0002', hint = 'DONATION_FUND_NOT_FOUND';
  end if;
  update "better_supabase"."donation_funds" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'goal', v_row."goal"::text, 'currency', v_row."currency", 'raised', case when v_row."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = v_row."id" and g."status" = 'posted' and g."currency" = v_row."currency"), 0)::text end, 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_donation_fund"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_donation_fund"(uuid) to authenticated, service_role;

-- Funds and campaigns with what they raised: posted gifts in the goal's
-- currency.
create or replace function "better_supabase"."list_donation_funds"(tenant uuid, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_funds.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'goal', x."goal"::text, 'currency', x."currency", 'raised', case when x."currency" is null then null else coalesce((select sum(g."amount") from "better_supabase"."donations" g where g."fund_id" = x."id" and g."status" = 'posted' and g."currency" = x."currency"), 0)::text end, 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
    from "better_supabase"."donation_funds" x
    where x."org_id" = list_donation_funds.tenant
      and (coalesce(list_donation_funds.include_archived, false) or x."archived_at" is null)
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_funds"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_donation_funds"(uuid, boolean) to authenticated, service_role;

-- Moves a gift along: pending stores the payment, succeeded posts it on
-- the ledger (cash in, fund income out), failed marks a pending gift, and
-- refunded reverses a posted one and voids its gift receipt. Each posting
-- carries a key per gift, so a repeat changes nothing. Internal.
create or replace function "better_supabase"."donation_settle"(gift_id uuid, status text, provider text default null, payment_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_fund "better_supabase"."donation_funds"%rowtype;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = donation_settle.gift_id for update;
  if not found then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if donation_settle.status not in ('pending', 'succeeded', 'failed', 'refunded') then
    raise exception 'status is pending, succeeded, failed or refunded' using errcode = '22023', hint = 'DONATION_STATUS_INVALID';
  end if;
  if donation_settle.payment_id is not null and v_row."payment_reference" is null then
    update "better_supabase"."donations" x set "provider" = coalesce(donation_settle.provider, x."provider"),
        "payment_reference" = donation_settle.payment_id, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  end if;
  select * into v_fund from "better_supabase"."donation_funds" y where y."id" = v_row."fund_id";
  if donation_settle.status = 'succeeded' and v_row."status" in ('pending', 'failed') then
    v_tx := "better_supabase"."ledger_post"(v_row."org_id", 'donation.gift',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount")),
      'donations', v_row."id"::text, 'Gift', 'donation:' || v_row."id"::text || ':posted', v_row."received_on"::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('donationId', v_row."id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id")));
    update "better_supabase"."donations" x set "status" = 'posted', "transaction_id" = v_tx, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  elsif donation_settle.status = 'failed' and v_row."status" = 'pending' then
    update "better_supabase"."donations" x set "status" = 'failed', "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  elsif donation_settle.status = 'refunded' and v_row."status" = 'posted' then
    v_tx := "better_supabase"."ledger_post"(v_row."org_id", 'donation.refund',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'gift_cash', 'donations.cash:' || v_row."currency",
      'Donations received ' || v_row."currency", v_row."currency"::text, 0::smallint, null, null, null, true, 'donations.read', 'donations', null), 'amount', -v_row."amount"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'gift_income',
      'donations.fund:' || coalesce(v_fund."key", 'general') || ':' || v_row."currency",
      'Donations: ' || coalesce(v_fund."name", 'General'), v_row."currency"::text, 0::smallint,
      case when v_fund."id" is null then null else 'donation_fund' end, v_fund."id"::text, null, true, 'donations.read', 'donations', null), 'amount', v_row."amount")),
      'donations', v_row."id"::text, 'Gift refunded', 'donation:' || v_row."id"::text || ':refunded', null,
      jsonb_build_object('donationId', v_row."id"));
    update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = 'the gift was refunded'
      where x."id" = v_row."receipt_id" and x."kind" = 'gift' and x."voided_at" is null;
    update "better_supabase"."donations" x set "status" = 'refunded', "refund_transaction_id" = v_tx, "receipt_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."donation_settle"(uuid, text, text, text) from public, anon, authenticated;

-- Records a gift received outside a payments provider (cash, a check, a
-- bank transfer) and posts it at once. With a pledge and period it pays
-- that installment; a second call for the same period returns the gift.
-- fields: the extra columns to set.
drop function if exists "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date, jsonb);
create or replace function "better_supabase"."record_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, received_on date default null, method text default null, note text default null, pledge_id uuid default null, period_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
  v_pledge "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', record_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if record_gift.donor_type is null or record_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if record_gift.amount is null or record_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.currency is null or record_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if record_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = record_gift.fund_id and y."org_id" = record_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if record_gift.pledge_id is not null then
    select * into v_pledge from "better_supabase"."pledges" y where y."id" = record_gift.pledge_id and y."org_id" = record_gift.tenant;
    if not found or v_pledge."donor_type" <> record_gift.donor_type or v_pledge."donor_id" <> record_gift.donor_id
      or v_pledge."currency" <> record_gift.currency or record_gift.period_start is null then
      raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
    end if;
  end if;
  insert into "better_supabase"."donations" ("org_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "received_on", "method", "note", "created_by")
  values (record_gift.tenant, record_gift.donor_type, record_gift.donor_id, coalesce(record_gift.fund_id, v_pledge."fund_id"), record_gift.pledge_id,
    case when record_gift.pledge_id is null then null else record_gift.period_start end, record_gift.amount, record_gift.currency,
    coalesce(record_gift.received_on, current_date), nullif(trim(record_gift.method), ''), nullif(trim(record_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = record_gift.pledge_id and x."period_start" = record_gift.period_start;
  end if;
  return "better_supabase"."donation_settle"(v_row."id", 'succeeded');
end;
$$;
revoke execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) from public, anon;
grant execute on function "better_supabase"."record_gift"(uuid, text, text, bigint, text, uuid, date, text, text, uuid, date) to authenticated, service_role;

-- Opens a pending gift a payments provider will charge. With a pledge and
-- period a second call returns the same gift, so a retried charge run never
-- charges a period twice. fields: the extra columns to set.
drop function if exists "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text, jsonb);
create or replace function "better_supabase"."open_gift"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, fund_id uuid default null, pledge_id uuid default null, period_start date default null, provider text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', open_gift.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if open_gift.donor_type is null or open_gift.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if open_gift.amount is null or open_gift.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.currency is null or open_gift.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if open_gift.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = open_gift.fund_id and y."org_id" = open_gift.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if open_gift.pledge_id is not null and (open_gift.period_start is null or not exists (
    select 1 from "better_supabase"."pledges" y where y."id" = open_gift.pledge_id and y."org_id" = open_gift.tenant
      and y."donor_type" = open_gift.donor_type and y."donor_id" = open_gift.donor_id and y."currency" = open_gift.currency
  )) then
    raise exception 'the pledge is unknown, another donor''s or in another currency, or the period is missing' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."donations" ("org_id", "donor_type", "donor_id", "fund_id", "pledge_id", "period_start", "amount",
    "currency", "method", "provider", "note", "created_by")
  values (open_gift.tenant, open_gift.donor_type, open_gift.donor_id, open_gift.fund_id, open_gift.pledge_id,
    case when open_gift.pledge_id is null then null else open_gift.period_start end, open_gift.amount, open_gift.currency,
    'card', open_gift.provider, nullif(trim(open_gift.note), ''), auth.uid())
  on conflict ("pledge_id", "period_start") do nothing
  returning * into v_row;
  if v_row."id" is null then
    select * into v_row from "better_supabase"."donations" x where x."pledge_id" = open_gift.pledge_id and x."period_start" = open_gift.period_start;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) from public, anon;
grant execute on function "better_supabase"."open_gift"(uuid, text, text, bigint, text, uuid, uuid, date, text, text) to authenticated, service_role;

-- Records what the payments provider reported for a gift: by its id, or
-- (gift_id null) by the provider's payment id. succeeded posts it, failed
-- marks it, refunded reverses it. A webhook calls it with the service role.
create or replace function "better_supabase"."record_gift_payment"(gift_id uuid, provider text, payment_id text, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  if record_gift_payment.gift_id is not null then
    select * into v_row from "better_supabase"."donations" x where x."id" = record_gift_payment.gift_id;
  else
    select * into v_row from "better_supabase"."donations" x
      where x."provider" = record_gift_payment.provider and x."payment_reference" = record_gift_payment.payment_id;
  end if;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return "better_supabase"."donation_settle"(v_row."id", record_gift_payment.status, record_gift_payment.provider, record_gift_payment.payment_id);
end;
$$;
revoke execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_gift_payment"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."get_gift"(gift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
begin
  select * into v_row from "better_supabase"."donations" x where x."id" = get_gift.gift_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'donations.read'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'pledgeId', v_row."pledge_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'receivedOn', v_row."received_on", 'method', v_row."method", 'status', v_row."status", 'provider', v_row."provider", 'paymentReference', v_row."payment_reference", 'transactionId', v_row."transaction_id", 'refundTransactionId', v_row."refund_transaction_id", 'receiptId', v_row."receipt_id", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_gift"(uuid) from public, anon;
grant execute on function "better_supabase"."get_gift"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_gifts"(tenant uuid, donor_type text default null, donor_id text default null, fund_id uuid default null, pledge_id uuid default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_gifts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'pledgeId', q."pledge_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', q."currency", 'receivedOn', q."received_on", 'method', q."method", 'status', q."status", 'provider', q."provider", 'paymentReference', q."payment_reference", 'transactionId', q."transaction_id", 'refundTransactionId', q."refund_transaction_id", 'receiptId', q."receipt_id", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."received_on" desc, q."created_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."donations" x
      where x."org_id" = list_gifts.tenant
        and (list_gifts.donor_type is null or (x."donor_type" = list_gifts.donor_type and x."donor_id" = list_gifts.donor_id))
        and (list_gifts.fund_id is null or x."fund_id" = list_gifts.fund_id)
        and (list_gifts.pledge_id is null or x."pledge_id" = list_gifts.pledge_id)
        and (list_gifts.status is null or x."status" = list_gifts.status)
      order by x."received_on" desc, x."created_at" desc
      limit least(greatest(coalesce(list_gifts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) from public, anon;
grant execute on function "better_supabase"."list_gifts"(uuid, text, text, uuid, uuid, text, integer) to authenticated, service_role;

create or replace function "better_supabase"."create_pledge"(tenant uuid, donor_type text, donor_id text, amount bigint, currency text, frequency text default 'monthly', fund_id uuid default null, starts_on date default null, ends_on date default null, provider text default null, provider_customer text default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_pledge.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if create_pledge.donor_type is null or create_pledge.donor_id is null or not false then
    raise exception 'the donor is unknown or not in this organization' using errcode = '22023', hint = 'DONATION_DONOR_INVALID';
  end if;
  if create_pledge.amount is null or create_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.currency is null or create_pledge.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  if create_pledge.fund_id is not null and not exists (
    select 1 from "better_supabase"."donation_funds" y where y."id" = create_pledge.fund_id and y."org_id" = create_pledge.tenant and y."archived_at" is null
  ) then
    raise exception 'the fund is unknown, archived or not in this organization' using errcode = '22023', hint = 'DONATION_FUND_INVALID';
  end if;
  if coalesce(create_pledge.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if create_pledge.ends_on is not null and create_pledge.ends_on <= coalesce(create_pledge.starts_on, current_date) then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  insert into "better_supabase"."pledges" ("org_id", "donor_type", "donor_id", "fund_id", "amount", "currency", "frequency",
    "starts_on", "ends_on", "provider", "provider_customer", "note", "created_by")
  values (create_pledge.tenant, create_pledge.donor_type, create_pledge.donor_id, create_pledge.fund_id, create_pledge.amount, create_pledge.currency,
    coalesce(create_pledge.frequency, 'monthly'), coalesce(create_pledge.starts_on, current_date), create_pledge.ends_on,
    nullif(trim(create_pledge.provider), ''), nullif(trim(create_pledge.provider_customer), ''), nullif(trim(create_pledge.note), ''), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_pledge"(uuid, text, text, bigint, text, text, uuid, date, date, text, text, text) to authenticated, service_role;

-- Pauses, resumes or ends a pledge, moves its end or changes its amount for
-- installments from now on. Null keeps a value.
create or replace function "better_supabase"."update_pledge"(pledge_id uuid, status text default null, ends_on date default null, amount bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."pledges"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."pledges" x where x."id" = update_pledge.pledge_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'donations.manage'), false)) then
    raise exception 'no such pledge you can manage' using errcode = 'P0002', hint = 'DONATION_PLEDGE_NOT_FOUND';
  end if;
  if update_pledge.status is not null and update_pledge.status not in ('active', 'paused', 'ended') then
    raise exception 'status is active, paused or ended' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if v_row."status" = 'ended' and coalesce(update_pledge.status, 'ended') <> 'ended' then
    raise exception 'an ended pledge can''t restart; create a new one' using errcode = '55000', hint = 'DONATION_PLEDGE_ENDED';
  end if;
  if update_pledge.ends_on is not null and update_pledge.ends_on <= v_row."starts_on" then
    raise exception 'ends_on is after starts_on' using errcode = '22023', hint = 'DONATION_PLEDGE_INVALID';
  end if;
  if update_pledge.amount is not null and update_pledge.amount <= 0 then
    raise exception 'an amount is more than zero minor units' using errcode = '22023', hint = 'DONATION_AMOUNT_INVALID';
  end if;
  update "better_supabase"."pledges" x set
      "status" = coalesce(update_pledge.status, x."status"),
      "ends_on" = coalesce(update_pledge.ends_on, x."ends_on"),
      "amount" = coalesce(update_pledge.amount, x."amount"),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id", 'amount', v_row."amount"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'status', v_row."status", 'provider', v_row."provider", 'providerCustomer', v_row."provider_customer", 'note', v_row."note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) from public, anon;
grant execute on function "better_supabase"."update_pledge"(uuid, text, date, bigint) to authenticated, service_role;

create or replace function "better_supabase"."list_pledges"(tenant uuid, donor_type text default null, donor_id text default null, status text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_pledges.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'fundId', q."fund_id", 'amount', q."amount"::text, 'currency', q."currency", 'frequency', q."frequency", 'startsOn', q."starts_on", 'endsOn', q."ends_on", 'status', q."status", 'provider', q."provider", 'providerCustomer', q."provider_customer", 'note', q."note", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."pledges" x
      where x."org_id" = list_pledges.tenant
        and (list_pledges.donor_type is null or (x."donor_type" = list_pledges.donor_type and x."donor_id" = list_pledges.donor_id))
        and (list_pledges.status is null or x."status" = list_pledges.status)
      order by x."created_at" desc, x."id"
      limit least(greatest(coalesce(list_pledges.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_pledges"(uuid, text, text, text, integer) to authenticated, service_role;

-- The installments of active pledges that start on or before through
-- (default today) and have no gift yet, oldest first, up to max_rows. A
-- gift opened but never charged (pending without a payment) stays due, so
-- the next run charges it under the same idempotency key; a declined one
-- doesn't.
create or replace function "better_supabase"."due_pledge_installments"(tenant uuid, through date default null, max_rows integer default 500)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(due_pledge_installments.through, current_date);
  v_max integer := least(greatest(coalesce(due_pledge_installments.max_rows, 500), 1), 5000);
  v_row "better_supabase"."pledges"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_n integer;
  v_start date;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', due_pledge_installments.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  <<installments>>
  for v_row in
    select * from "better_supabase"."pledges" x
    where x."org_id" = due_pledge_installments.tenant and x."status" = 'active' and x."starts_on" <= v_through
    order by x."starts_on", x."id"
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."donations" g where g."pledge_id" = v_row."id" and g."period_start" = v_start
        and not (g."status" = 'pending' and g."payment_reference" is null)) then
        exit installments when jsonb_array_length(v_items) >= v_max;
        v_items := v_items || jsonb_build_array(jsonb_build_object('periodStart', v_start, 'pledgeId', v_row."id",
          'donorType', v_row."donor_type", 'donorId', v_row."donor_id", 'fundId', v_row."fund_id",
          'amount', v_row."amount"::text, 'currency', v_row."currency",
          'provider', v_row."provider", 'providerCustomer', v_row."provider_customer"));
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_items;
end;
$$;
revoke execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."due_pledge_installments"(uuid, date, integer) to authenticated, service_role;

-- Issues a numbered tax receipt for one posted gift. Numbers come from
-- numbering when it configures donation_receipt, else one more than
-- the organization's highest.
create or replace function "better_supabase"."issue_gift_receipt"(gift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."donations"%rowtype;
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donations" x where x."id" = issue_gift_receipt.gift_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted gift gets a receipt' using errcode = '55000', hint = 'DONATION_STATUS_INVALID';
  end if;
  if v_row."receipt_id" is not null then
    select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = v_row."receipt_id";
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."org_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_row."org_id", 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_row."org_id", 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("org_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (v_row."org_id", v_row."donor_type", v_row."donor_id", v_seq, v_number, 'gift', extract(year from v_row."received_on")::integer,
    v_row."amount", v_row."currency")
  returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = v_receipt."id", "updated_at" = now() where x."id" = v_row."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."org_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_gift_receipt"(uuid) from public, anon;
grant execute on function "better_supabase"."issue_gift_receipt"(uuid) to authenticated, service_role;

-- Issues a donor's yearly tax receipt: their posted gifts received in year
-- in currency. A second call returns the receipt until it is voided.
create or replace function "better_supabase"."issue_yearly_receipt"(tenant uuid, donor_type text, donor_id text, year integer, currency text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_yearly_receipt.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    raise exception 'a yearly receipt needs a year and a currency' using errcode = '22023', hint = 'DONATION_RECEIPT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from "better_supabase"."donation_receipts" x
    where x."org_id" = issue_yearly_receipt.tenant and x."donor_type" = issue_yearly_receipt.donor_type
      and x."donor_id" = issue_yearly_receipt.donor_id and x."year" = issue_yearly_receipt.year
      and x."currency" = issue_yearly_receipt.currency and x."kind" = 'yearly' and x."voided_at" is null;
  if found then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."org_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  select coalesce(sum(g."amount"), 0) into v_amount from "better_supabase"."donations" g
    where g."org_id" = issue_yearly_receipt.tenant and g."donor_type" = issue_yearly_receipt.donor_type
      and g."donor_id" = issue_yearly_receipt.donor_id and g."currency" = issue_yearly_receipt.currency
      and g."status" = 'posted' and extract(year from g."received_on")::integer = issue_yearly_receipt.year;
  if v_amount <= 0 then
    raise exception 'the donor has no posted gifts in this year and currency' using errcode = '22023', hint = 'DONATION_RECEIPT_EMPTY';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(issue_yearly_receipt.tenant, 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(issue_yearly_receipt.tenant, 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("org_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."org_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) from public, anon;
grant execute on function "better_supabase"."issue_yearly_receipt"(uuid, text, text, integer, text) to authenticated, service_role;

-- Voids a receipt; its number stays used. A voided gift receipt frees the
-- gift for a new one.
create or replace function "better_supabase"."void_donation_receipt"(receipt_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = void_donation_receipt.receipt_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_receipt."org_id", 'donations.manage'), false)) then
    raise exception 'no such receipt you can manage' using errcode = 'P0002', hint = 'DONATION_RECEIPT_NOT_FOUND';
  end if;
  if v_receipt."voided_at" is not null then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."org_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  update "better_supabase"."donation_receipts" x set "voided_at" = now(), "void_reason" = nullif(trim(void_donation_receipt.reason), '')
    where x."id" = v_receipt."id"
    returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = null, "updated_at" = now() where x."receipt_id" = v_receipt."id";
  null;
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."org_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$$;
revoke execute on function "better_supabase"."void_donation_receipt"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_donation_receipt"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."list_donation_receipts"(tenant uuid, donor_type text default null, donor_id text default null, year integer default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_donation_receipts.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'donorType', q."donor_type", 'donorId', q."donor_id", 'sequence', q."sequence"::text, 'number', q."number", 'kind', q."kind", 'year', q."year", 'amount', q."amount"::text, 'currency', q."currency", 'issuedAt', q."issued_at", 'voidedAt', q."voided_at", 'voidReason', q."void_reason") order by q."issued_at" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."donation_receipts" x
      where x."org_id" = list_donation_receipts.tenant
        and (list_donation_receipts.donor_type is null or (x."donor_type" = list_donation_receipts.donor_type and x."donor_id" = list_donation_receipts.donor_id))
        and (list_donation_receipts.year is null or x."year" = list_donation_receipts.year)
      order by x."issued_at" desc, x."id"
      limit least(greatest(coalesce(list_donation_receipts.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) from public, anon;
grant execute on function "better_supabase"."list_donation_receipts"(uuid, text, text, integer, integer) to authenticated, service_role;

-- A donor's giving in a year (default this one): posted totals per
-- currency, per fund, and the receipts issued for the year.
create or replace function "better_supabase"."yearly_giving_summary"(tenant uuid, donor_type text, donor_id text, year integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_year integer := coalesce(yearly_giving_summary.year, extract(year from current_date)::integer);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', yearly_giving_summary.tenant, 'donations.read'), false)) then
    raise exception 'not allowed to read donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'year', v_year,
    'donorType', yearly_giving_summary.donor_type,
    'donorId', yearly_giving_summary.donor_id,
    'totals', (
      select coalesce(jsonb_agg(jsonb_build_object('currency', q.currency, 'amount', q.amount::text, 'gifts', q.gifts) order by q.currency), '[]'::jsonb)
      from (
        select g."currency" as currency, sum(g."amount") as amount, count(*) as gifts
        from "better_supabase"."donations" g
        where g."org_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."currency"
      ) q
    ),
    'funds', (
      select coalesce(jsonb_agg(jsonb_build_object('fundId', q.fund, 'name', coalesce(y."name", 'General'), 'currency', q.currency, 'amount', q.amount::text)
        order by coalesce(y."name", ''), q.currency), '[]'::jsonb)
      from (
        select g."fund_id" as fund, g."currency" as currency, sum(g."amount") as amount
        from "better_supabase"."donations" g
        where g."org_id" = yearly_giving_summary.tenant and g."donor_type" = yearly_giving_summary.donor_type
          and g."donor_id" = yearly_giving_summary.donor_id and g."status" = 'posted'
          and extract(year from g."received_on")::integer = v_year
        group by g."fund_id", g."currency"
      ) q
      left join "better_supabase"."donation_funds" y on y."id" = q.fund
    ),
    'receipts', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'donorType', x."donor_type", 'donorId', x."donor_id", 'sequence', x."sequence"::text, 'number', x."number", 'kind', x."kind", 'year', x."year", 'amount', x."amount"::text, 'currency', x."currency", 'issuedAt', x."issued_at", 'voidedAt', x."voided_at", 'voidReason', x."void_reason") order by x."issued_at"), '[]'::jsonb)
      from "better_supabase"."donation_receipts" x
      where x."org_id" = yearly_giving_summary.tenant and x."donor_type" = yearly_giving_summary.donor_type
        and x."donor_id" = yearly_giving_summary.donor_id and x."year" = v_year
    )
  );
end;
$$;
revoke execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."yearly_giving_summary"(uuid, text, text, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_funds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_select on "better_supabase"."donation_funds" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_funds" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_update on "better_supabase"."donation_funds" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_funds";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_funds" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."pledges";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."pledges";
create policy bsb_tenant_scope_select on "better_supabase"."pledges" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."pledges";
create policy bsb_tenant_scope_insert on "better_supabase"."pledges" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."pledges";
create policy bsb_tenant_scope_update on "better_supabase"."pledges" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."pledges";
create policy bsb_tenant_scope_delete on "better_supabase"."pledges" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donation_receipts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_select on "better_supabase"."donation_receipts" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_insert on "better_supabase"."donation_receipts" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_update on "better_supabase"."donation_receipts" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donation_receipts";
create policy bsb_tenant_scope_delete on "better_supabase"."donation_receipts" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."donations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."donations";
create policy bsb_tenant_scope_select on "better_supabase"."donations" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('donations.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."donations";
create policy bsb_tenant_scope_insert on "better_supabase"."donations" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."donations";
create policy bsb_tenant_scope_update on "better_supabase"."donations" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."donations";
create policy bsb_tenant_scope_delete on "better_supabase"."donations" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_122_donations.sql
-- better-supabase module: donations
-- @bsb-block-data donations
-- @bsb-hash sha256:766adfa3e7067c6f8172269a3181465a320dd4dc98f6ab433fc4ba3e69980c75
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('donations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
