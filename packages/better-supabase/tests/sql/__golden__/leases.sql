-- ==== alone: schema supabase/schemas/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block leases@3 managed
-- @bsb-hash sha256:8cfe4b5d7104dedaabf9485dfa27b3c639be23359a8a6d81e253bbda57c45acf
-- Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals and terminations. Maintenance requests are a tasks instance on the unit.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, and deposits held through ledger holds.

create table "better_supabase"."leases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "unit_id" uuid not null references "better_supabase"."assets" ("id") on delete restrict,
  -- The party renting the unit: a registered subject such as a contact.
  "party_type" text not null,
  "party_id" text not null,
  "title" text not null constraint bsb_leases_title_check check (length("title") >= 1 and length("title") <= 200),
  "status" text not null default 'draft' constraint bsb_leases_status_check check ("status" in ('draft', 'active', 'ended', 'terminated')),
  "starts_on" date not null,
  -- Null runs the lease until it is terminated.
  "ends_on" date,
  -- Minor units of currency per period (ADR 0037).
  "rent" bigint not null constraint bsb_leases_rent_check check ("rent" > 0),
  "currency" char(3) not null constraint bsb_leases_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' constraint bsb_leases_frequency_check check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "deposit" bigint not null default 0 constraint bsb_leases_deposit_check check ("deposit" >= 0),
  -- The ledger hold that keeps the deposit aside while the lease runs.
  "deposit_hold_id" uuid,
  "renewed_at" timestamptz,
  "terminated_on" date,
  "termination_reason" text constraint bsb_leases_termination_reason_check check ("termination_reason" is null or length("termination_reason") <= 2000),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_leases_check check ("ends_on" is null or "ends_on" > "starts_on")
);
create index "leases_tenant_idx" on "better_supabase"."leases" ("tenant_id", "status", "starts_on" desc);
create index "leases_unit_idx" on "better_supabase"."leases" ("unit_id");
create index "leases_party_idx" on "better_supabase"."leases" ("tenant_id", "party_type", "party_id");
create index "leases_deposit_hold_idx" on "better_supabase"."leases" ("deposit_hold_id") where "deposit_hold_id" is not null;
alter table "better_supabase"."leases" enable row level security;
revoke all on "better_supabase"."leases" from public, anon, authenticated;
grant select on "better_supabase"."leases" to authenticated;
grant all on "better_supabase"."leases" to service_role;
create policy bsb_leases_read on "better_supabase"."leases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));

-- One row per rent period posted to the ledger, so each period posts once.
create table "better_supabase"."lease_charges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "lease_id" uuid not null references "better_supabase"."leases" ("id") on delete restrict,
  "period_start" date not null,
  "period_end" date not null,
  "amount" bigint not null constraint bsb_lease_charges_amount_check check ("amount" > 0),
  "currency" char(3) not null,
  "transaction_id" uuid not null,
  "created_at" timestamptz not null default now(),
  unique ("lease_id", "period_start"),
  constraint bsb_lease_charges_check check ("period_end" > "period_start")
);
create index "lease_charges_tenant_idx" on "better_supabase"."lease_charges" ("tenant_id", "period_start" desc);
create index "lease_charges_transaction_idx" on "better_supabase"."lease_charges" ("transaction_id");
alter table "better_supabase"."lease_charges" enable row level security;
revoke all on "better_supabase"."lease_charges" from public, anon, authenticated;
grant select on "better_supabase"."lease_charges" to authenticated;
grant all on "better_supabase"."lease_charges" to service_role;
create policy bsb_lease_charges_read on "better_supabase"."lease_charges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));


-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
-- fields: the extra columns to set.

create or replace function "better_supabase"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_unit text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_lease.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  select u."name" into v_unit from "better_supabase"."assets" u
    where u."id" = create_lease.unit_id and u."tenant_id" = create_lease.tenant and u."retired_at" is null;
  if not found then
    raise exception 'the unit is unknown, retired or not in this organization' using errcode = '22023', hint = 'LEASE_UNIT_INVALID';
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not false then
    raise exception 'the party is unknown or not in this organization' using errcode = '22023', hint = 'LEASE_PARTY_INVALID';
  end if;
  if create_lease.starts_on is null then
    raise exception 'a lease needs starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    raise exception 'ends_on must be after starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    raise exception 'a deposit is zero or more minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  insert into "better_supabase"."leases" ("tenant_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
    "rent", "currency", "frequency", "deposit", "metadata", "created_by")
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, coalesce(create_lease.frequency, 'monthly'), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) to authenticated, service_role;

-- Starts a draft lease. Fails while another active lease of the unit
-- overlaps it. A deposit is received on the lease's deposit account and
-- held there until the lease ends.
create or replace function "better_supabase"."activate_lease"(lease_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "better_supabase"."leases" x
    where x."unit_id" = v_row."unit_id" and x."id" <> v_row."id" and x."status" = 'active'
      and daterange(x."starts_on", x."ends_on") && daterange(v_row."starts_on", v_row."ends_on")
  ) then
    raise exception 'another active lease of this unit overlaps these dates' using errcode = '23P01', hint = 'LEASE_OVERLAP';
  end if;
  if v_row."deposit" > 0 then
    v_account := "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id"));
    perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row."deposit"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."deposit")),
      'leases', v_row."id"::text, 'Deposit received', 'leases.deposit:' || v_row."id"::text, null,
      jsonb_build_object('leaseId', v_row."id"));
    v_hold := "better_supabase"."ledger_hold"(v_account, v_row."deposit", 'leases', v_row."id"::text, null);
  end if;
  update "better_supabase"."leases" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."activate_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."activate_lease"(uuid) to authenticated, service_role;

-- Extends an active lease with a fixed end to a later ends_on, at a new
-- rent when one is given. Periods posted from then on use the new rent.
create or replace function "better_supabase"."renew_lease"(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = renew_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active lease can be renewed' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_row."ends_on" is null then
    raise exception 'this lease has no end; it runs until it is terminated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if renew_lease.ends_on is null or renew_lease.ends_on <= v_row."ends_on" then
    raise exception 'a renewal ends after the current end' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if renew_lease.rent is not null and renew_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  update "better_supabase"."leases" x set "ends_on" = renew_lease.ends_on, "rent" = coalesce(renew_lease.rent, x."rent"),
      "renewed_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."renew_lease"(uuid, date, bigint) from public, anon;
grant execute on function "better_supabase"."renew_lease"(uuid, date, bigint) to authenticated, service_role;

-- Ends a lease on terminates_on (default today): ended on or after its end,
-- terminated before. No rent posts for periods from that day. The deposit
-- hold is captured for deposit_deduction (into rent income) and the rest
-- goes back to the party. A draft is terminated without touching the ledger.
create or replace function "better_supabase"."terminate_lease"(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = terminate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'active') then
    raise exception 'this lease has already ended' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_on < v_row."starts_on" and v_row."status" = 'active' then
    raise exception 'a lease can''t end before it starts' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" >= v_on) then
    raise exception 'rent is already posted for a period from this date; pick a later date' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  v_held := coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0);
  if v_deduction < 0 or v_deduction > v_held then
    raise exception 'a deduction is zero or more and at most the deposit held' using errcode = '22023', hint = 'LEASE_DEPOSIT_INVALID';
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform "better_supabase"."ledger_capture"(v_row."deposit_hold_id", "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform "better_supabase"."ledger_release"(v_row."deposit_hold_id");
    end if;
    if v_held - v_deduction > 0 then
      perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', v_held - v_deduction)),
        'leases', v_row."id"::text, 'Deposit refunded', 'leases.deposit_refund:' || v_row."id"::text, null,
        jsonb_build_object('leaseId', v_row."id"));
    end if;
  end if;
  update "better_supabase"."leases" x set
      "status" = case when x."status" = 'active' and x."ends_on" is not null and v_on >= x."ends_on" then 'ended' else 'terminated' end,
      "terminated_on" = v_on, "termination_reason" = nullif(trim(terminate_lease.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) to authenticated, service_role;

create or replace function "better_supabase"."get_lease"(lease_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = get_lease.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."get_lease"(uuid) to authenticated, service_role;

-- Leases, latest start first. filters is { status, unitId, partyType, partyId
-- (each a value or a list), sort, direction, facet, count, limit, after, offset,
-- paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_leases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_leases.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'unitId') then
      raise exception 'facet is one of status, unitId' using errcode = '22023', hint = 'LEASE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'unitId' then (x."unit_id")::text end) as v
      from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."ends_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."ends_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_leases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_leases"(uuid, jsonb) to authenticated, service_role;

-- Posts the rent of every period of an active lease that starts on or
-- before through (default today), up to max_rows charges. Each period posts
-- once: the charge row is unique per lease and period, and its ledger
-- transaction carries the key lease:<id>:rent:<period start>. Without a
-- tenant it runs for every organization and needs the service role, so a
-- scheduled job can call it.
create or replace function "better_supabase"."post_due_rent"(tenant uuid default null, through date default null, max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "better_supabase"."leases"%rowtype;
  v_charge "better_supabase"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "better_supabase"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."tenant_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "better_supabase"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        
        null;
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."post_due_rent"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."post_due_rent"(uuid, date, integer) to authenticated, service_role;

-- Records a rent payment: it moves amount from the lease's receivable to
-- rent received. With a reference a second call returns the first payment.
create or replace function "better_supabase"."record_rent_payment"(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."tenant_id" = v_row."tenant_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    
    null;
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) to authenticated, service_role;

create or replace function "better_supabase"."list_lease_charges"(lease_id uuid, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = list_lease_charges.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'leaseId', q."lease_id", 'periodStart', q."period_start", 'periodEnd', q."period_end", 'amount', q."amount"::text, 'currency', q."currency", 'transactionId', q."transaction_id", 'createdAt', q."created_at") order by q."period_start" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id"
      order by y."period_start" desc
      limit least(greatest(coalesce(list_lease_charges.page_size, 200), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_lease_charges"(uuid, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."leases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."leases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."leases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."leases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."lease_charges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."lease_charges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."lease_charges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."lease_charges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:916537b0ac15a44d934f0953f1905d46b0489cbc62ee42af0d92f389f7ae4b1d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block leases@3 managed
-- @bsb-hash sha256:f6649fba204d618e65b5c1ce5ef24b12f95d90eafc81f267041b7a8d6d49a7d6
-- Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals and terminations. Maintenance requests are a tasks instance on the unit.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, and deposits held through ledger holds.

create table "better_supabase"."leases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "unit_id" uuid not null references "better_supabase"."assets" ("id") on delete restrict,
  -- The party renting the unit: a registered subject such as a contact.
  "party_type" text not null,
  "party_id" text not null,
  "title" text not null constraint bsb_leases_title_check check (length("title") >= 1 and length("title") <= 200),
  "status" text not null default 'draft' constraint bsb_leases_status_check check ("status" in ('draft', 'active', 'ended', 'terminated')),
  "starts_on" date not null,
  -- Null runs the lease until it is terminated.
  "ends_on" date,
  -- Minor units of currency per period (ADR 0037).
  "rent" bigint not null constraint bsb_leases_rent_check check ("rent" > 0),
  "currency" char(3) not null constraint bsb_leases_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' constraint bsb_leases_frequency_check check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "deposit" bigint not null default 0 constraint bsb_leases_deposit_check check ("deposit" >= 0),
  -- The ledger hold that keeps the deposit aside while the lease runs.
  "deposit_hold_id" uuid,
  "renewed_at" timestamptz,
  "terminated_on" date,
  "termination_reason" text constraint bsb_leases_termination_reason_check check ("termination_reason" is null or length("termination_reason") <= 2000),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_leases_check check ("ends_on" is null or "ends_on" > "starts_on")
);
create index "leases_tenant_idx" on "better_supabase"."leases" ("tenant_id", "status", "starts_on" desc);
create index "leases_unit_idx" on "better_supabase"."leases" ("unit_id");
create index "leases_party_idx" on "better_supabase"."leases" ("tenant_id", "party_type", "party_id");
create index "leases_deposit_hold_idx" on "better_supabase"."leases" ("deposit_hold_id") where "deposit_hold_id" is not null;
alter table "better_supabase"."leases" enable row level security;
revoke all on "better_supabase"."leases" from public, anon, authenticated;
grant select on "better_supabase"."leases" to authenticated;
grant all on "better_supabase"."leases" to service_role;
create policy bsb_leases_read on "better_supabase"."leases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));

-- One row per rent period posted to the ledger, so each period posts once.
create table "better_supabase"."lease_charges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "lease_id" uuid not null references "better_supabase"."leases" ("id") on delete restrict,
  "period_start" date not null,
  "period_end" date not null,
  "amount" bigint not null constraint bsb_lease_charges_amount_check check ("amount" > 0),
  "currency" char(3) not null,
  "transaction_id" uuid not null,
  "created_at" timestamptz not null default now(),
  unique ("lease_id", "period_start"),
  constraint bsb_lease_charges_check check ("period_end" > "period_start")
);
create index "lease_charges_tenant_idx" on "better_supabase"."lease_charges" ("tenant_id", "period_start" desc);
create index "lease_charges_transaction_idx" on "better_supabase"."lease_charges" ("transaction_id");
alter table "better_supabase"."lease_charges" enable row level security;
revoke all on "better_supabase"."lease_charges" from public, anon, authenticated;
grant select on "better_supabase"."lease_charges" to authenticated;
grant all on "better_supabase"."lease_charges" to service_role;
create policy bsb_lease_charges_read on "better_supabase"."lease_charges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));


-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
-- fields: the extra columns to set.

create or replace function "better_supabase"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_unit text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_lease.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  select u."name" into v_unit from "better_supabase"."assets" u
    where u."id" = create_lease.unit_id and u."tenant_id" = create_lease.tenant and u."retired_at" is null;
  if not found then
    raise exception 'the unit is unknown, retired or not in this organization' using errcode = '22023', hint = 'LEASE_UNIT_INVALID';
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not false then
    raise exception 'the party is unknown or not in this organization' using errcode = '22023', hint = 'LEASE_PARTY_INVALID';
  end if;
  if create_lease.starts_on is null then
    raise exception 'a lease needs starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    raise exception 'ends_on must be after starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    raise exception 'a deposit is zero or more minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  insert into "better_supabase"."leases" ("tenant_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
    "rent", "currency", "frequency", "deposit", "metadata", "created_by")
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, coalesce(create_lease.frequency, 'monthly'), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('lease.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.created',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'created a lease',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) to authenticated, service_role;

-- Starts a draft lease. Fails while another active lease of the unit
-- overlaps it. A deposit is received on the lease's deposit account and
-- held there until the lease ends.
create or replace function "better_supabase"."activate_lease"(lease_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "better_supabase"."leases" x
    where x."unit_id" = v_row."unit_id" and x."id" <> v_row."id" and x."status" = 'active'
      and daterange(x."starts_on", x."ends_on") && daterange(v_row."starts_on", v_row."ends_on")
  ) then
    raise exception 'another active lease of this unit overlaps these dates' using errcode = '23P01', hint = 'LEASE_OVERLAP';
  end if;
  if v_row."deposit" > 0 then
    v_account := "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id"));
    perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row."deposit"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."deposit")),
      'leases', v_row."id"::text, 'Deposit received', 'leases.deposit:' || v_row."id"::text, null,
      jsonb_build_object('leaseId', v_row."id"));
    v_hold := "better_supabase"."ledger_hold"(v_account, v_row."deposit", 'leases', v_row."id"::text, null);
  end if;
  update "better_supabase"."leases" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('lease.activated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.activated',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'activated a lease',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."activate_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."activate_lease"(uuid) to authenticated, service_role;

-- Extends an active lease with a fixed end to a later ends_on, at a new
-- rent when one is given. Periods posted from then on use the new rent.
create or replace function "better_supabase"."renew_lease"(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = renew_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active lease can be renewed' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_row."ends_on" is null then
    raise exception 'this lease has no end; it runs until it is terminated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if renew_lease.ends_on is null or renew_lease.ends_on <= v_row."ends_on" then
    raise exception 'a renewal ends after the current end' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if renew_lease.rent is not null and renew_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  update "better_supabase"."leases" x set "ends_on" = renew_lease.ends_on, "rent" = coalesce(renew_lease.rent, x."rent"),
      "renewed_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('lease.renewed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.renewed',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'renewed a lease',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."renew_lease"(uuid, date, bigint) from public, anon;
grant execute on function "better_supabase"."renew_lease"(uuid, date, bigint) to authenticated, service_role;

-- Ends a lease on terminates_on (default today): ended on or after its end,
-- terminated before. No rent posts for periods from that day. The deposit
-- hold is captured for deposit_deduction (into rent income) and the rest
-- goes back to the party. A draft is terminated without touching the ledger.
create or replace function "better_supabase"."terminate_lease"(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = terminate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'active') then
    raise exception 'this lease has already ended' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_on < v_row."starts_on" and v_row."status" = 'active' then
    raise exception 'a lease can''t end before it starts' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" >= v_on) then
    raise exception 'rent is already posted for a period from this date; pick a later date' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  v_held := coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0);
  if v_deduction < 0 or v_deduction > v_held then
    raise exception 'a deduction is zero or more and at most the deposit held' using errcode = '22023', hint = 'LEASE_DEPOSIT_INVALID';
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform "better_supabase"."ledger_capture"(v_row."deposit_hold_id", "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform "better_supabase"."ledger_release"(v_row."deposit_hold_id");
    end if;
    if v_held - v_deduction > 0 then
      perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', v_held - v_deduction)),
        'leases', v_row."id"::text, 'Deposit refunded', 'leases.deposit_refund:' || v_row."id"::text, null,
        jsonb_build_object('leaseId', v_row."id"));
    end if;
  end if;
  update "better_supabase"."leases" x set
      "status" = case when x."status" = 'active' and x."ends_on" is not null and v_on >= x."ends_on" then 'ended' else 'terminated' end,
      "terminated_on" = v_on, "termination_reason" = nullif(trim(terminate_lease.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('lease.terminated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.terminated',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'ended a lease',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) to authenticated, service_role;

create or replace function "better_supabase"."get_lease"(lease_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = get_lease.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."get_lease"(uuid) to authenticated, service_role;

-- Leases, latest start first. filters is { status, unitId, partyType, partyId
-- (each a value or a list), sort, direction, facet, count, limit, after, offset,
-- paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_leases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_leases.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'unitId') then
      raise exception 'facet is one of status, unitId' using errcode = '22023', hint = 'LEASE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'unitId' then (x."unit_id")::text end) as v
      from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."ends_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."ends_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_leases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_leases"(uuid, jsonb) to authenticated, service_role;

-- Posts the rent of every period of an active lease that starts on or
-- before through (default today), up to max_rows charges. Each period posts
-- once: the charge row is unique per lease and period, and its ledger
-- transaction carries the key lease:<id>:rent:<period start>. Without a
-- tenant it runs for every organization and needs the service role, so a
-- scheduled job can call it.
create or replace function "better_supabase"."post_due_rent"(tenant uuid default null, through date default null, max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "better_supabase"."leases"%rowtype;
  v_charge "better_supabase"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "better_supabase"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."tenant_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "better_supabase"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('lease_rent', v_charge."id"::text);
  end if;
        perform "better_supabase".emit_event('lease.charged', jsonb_build_object('organizationId', v_charge."tenant_id", 'id', v_charge."id", 'leaseId', v_charge."lease_id", 'periodStart', v_charge."period_start", 'periodEnd', v_charge."period_end", 'amount', v_charge."amount"::text, 'currency', v_charge."currency", 'transactionId', v_charge."transaction_id"), 'lease-charges/' || v_charge."id"::text, (v_charge."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.charged',
    category => 'billing',
    target_type => 'lease_charge',
    record_id => v_charge."id"::text,
    summary => 'posted rent from ' || v_charge."period_start"::text,
    tenant => (v_charge."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_charge."tenant_id", 'id', v_charge."id", 'leaseId', v_charge."lease_id", 'periodStart', v_charge."period_start", 'periodEnd', v_charge."period_end", 'amount', v_charge."amount"::text, 'currency', v_charge."currency", 'transactionId', v_charge."transaction_id")
  );
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."post_due_rent"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."post_due_rent"(uuid, date, integer) to authenticated, service_role;

-- Records a rent payment: it moves amount from the lease's receivable to
-- rent received. With a reference a second call returns the first payment.
create or replace function "better_supabase"."record_rent_payment"(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."tenant_id" = v_row."tenant_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('lease_payment', v_tx::text);
  end if;
    perform "better_supabase".emit_event('lease.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'transactionId', v_tx, 'amount', record_rent_payment.amount::text, 'currency', v_row."currency"), 'leases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leases');
  perform better_supabase.audit_event(
    event_type => 'lease.paid',
    category => 'billing',
    target_type => 'lease',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'recorded a rent payment',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'transactionId', v_tx, 'amount', record_rent_payment.amount::text, 'currency', v_row."currency")
  );
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) to authenticated, service_role;

create or replace function "better_supabase"."list_lease_charges"(lease_id uuid, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = list_lease_charges.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'leaseId', q."lease_id", 'periodStart', q."period_start", 'periodEnd', q."period_end", 'amount', q."amount"::text, 'currency', q."currency", 'transactionId', q."transaction_id", 'createdAt', q."created_at") order by q."period_start" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id"
      order by y."period_start" desc
      limit least(greatest(coalesce(list_lease_charges.page_size, 200), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_lease_charges"(uuid, integer) to authenticated, service_role;

-- The entry of a posted rent charge for accounting: the tenant's receivable
-- against rent revenue.
create or replace function "better_supabase"."accounting_lease_rent_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', y."period_start",
    'currency', y."currency",
    'memo', left('Rent from ' || y."period_start"::text || ': ' || coalesce(v."title", ''), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'receivable', 'debit', y."amount"::text, 'partyId', v."party_id"),
      jsonb_build_object('role', 'revenue', 'credit', y."amount"::text))
  )
  from "better_supabase"."lease_charges" y join "better_supabase"."leases" v on v."id" = y."lease_id"
  where y."id"::text = source_id and y."amount" <> 0
$$;
revoke execute on function "better_supabase"."accounting_lease_rent_lines"(text) from public, anon, authenticated;

-- The entry of a rent payment for accounting: bank against the tenant's
-- receivable.
create or replace function "better_supabase"."accounting_lease_payment_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', v."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', v."currency",
    'reference', y."metadata" ->> 'reference',
    'memo', left('Rent payment: ' || coalesce(v."title", ''), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', v."party_id"))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."leases" v on v."id"::text = y."reference_id"
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    where e."transaction_id" = y."id" and e."amount" > 0
  ) p
  where y."id"::text = source_id and y."reference_type" = 'leases' and y."kind" = 'lease.payment'
    and p.amount <> 0
$$;
revoke execute on function "better_supabase"."accounting_lease_payment_lines"(text) from public, anon, authenticated;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."leases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."leases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."leases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."leases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."lease_charges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."lease_charges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."lease_charges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."lease_charges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.leases deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"lease","event_prefix":"lease"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:916537b0ac15a44d934f0953f1905d46b0489cbc62ee42af0d92f389f7ae4b1d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block leases@3 managed
-- @bsb-hash sha256:f355c4497fe85bcbe9764e0d7cb1c0c0506c01a9275bae3a035a1021ca9abfb6
-- Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals and terminations. Maintenance requests are a tasks instance on the unit.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, and deposits held through ledger holds.

create table "app_private"."leases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "unit_id" uuid not null references "better_supabase"."assets" ("id") on delete restrict,
  -- The party renting the unit: a registered subject such as a contact.
  "party_type" text not null,
  "party_id" text not null,
  "title" text not null constraint bsb_leases_title_check check (length("title") >= 1 and length("title") <= 200),
  "status" text not null default 'draft' constraint bsb_leases_status_check check ("status" in ('draft', 'active', 'ended', 'terminated')),
  "starts_on" date not null,
  -- Null runs the lease until it is terminated.
  "ends_on" date,
  -- Minor units of currency per period (ADR 0037).
  "rent" bigint not null constraint bsb_leases_rent_check check ("rent" > 0),
  "currency" char(3) not null constraint bsb_leases_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' constraint bsb_leases_frequency_check check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "deposit" bigint not null default 0 constraint bsb_leases_deposit_check check ("deposit" >= 0),
  -- The ledger hold that keeps the deposit aside while the lease runs.
  "deposit_hold_id" uuid,
  "renewed_at" timestamptz,
  "terminated_on" date,
  "termination_reason" text constraint bsb_leases_termination_reason_check check ("termination_reason" is null or length("termination_reason") <= 2000),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_leases_check check ("ends_on" is null or "ends_on" > "starts_on")
);
create index "leases_tenant_idx" on "app_private"."leases" ("tenant_id", "status", "starts_on" desc);
create index "leases_unit_idx" on "app_private"."leases" ("unit_id");
create index "leases_party_idx" on "app_private"."leases" ("tenant_id", "party_type", "party_id");
create index "leases_deposit_hold_idx" on "app_private"."leases" ("deposit_hold_id") where "deposit_hold_id" is not null;
alter table "app_private"."leases" enable row level security;
revoke all on "app_private"."leases" from public, anon, authenticated;
grant select on "app_private"."leases" to authenticated;
grant all on "app_private"."leases" to service_role;
create policy bsb_leases_read on "app_private"."leases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));

-- One row per rent period posted to the ledger, so each period posts once.
create table "app_private"."lease_charges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "lease_id" uuid not null references "app_private"."leases" ("id") on delete restrict,
  "period_start" date not null,
  "period_end" date not null,
  "amount" bigint not null constraint bsb_lease_charges_amount_check check ("amount" > 0),
  "currency" char(3) not null,
  "transaction_id" uuid not null,
  "created_at" timestamptz not null default now(),
  unique ("lease_id", "period_start"),
  constraint bsb_lease_charges_check check ("period_end" > "period_start")
);
create index "lease_charges_tenant_idx" on "app_private"."lease_charges" ("tenant_id", "period_start" desc);
create index "lease_charges_transaction_idx" on "app_private"."lease_charges" ("transaction_id");
alter table "app_private"."lease_charges" enable row level security;
revoke all on "app_private"."lease_charges" from public, anon, authenticated;
grant select on "app_private"."lease_charges" to authenticated;
grant all on "app_private"."lease_charges" to service_role;
create policy bsb_lease_charges_read on "app_private"."lease_charges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));


-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
-- fields: the extra columns to set.

create or replace function "app_private"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."leases"%rowtype;
  v_unit text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_lease.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  select u."name" into v_unit from "better_supabase"."assets" u
    where u."id" = create_lease.unit_id and u."tenant_id" = create_lease.tenant and u."retired_at" is null;
  if not found then
    raise exception 'the unit is unknown, retired or not in this organization' using errcode = '22023', hint = 'LEASE_UNIT_INVALID';
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not false then
    raise exception 'the party is unknown or not in this organization' using errcode = '22023', hint = 'LEASE_PARTY_INVALID';
  end if;
  if create_lease.starts_on is null then
    raise exception 'a lease needs starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    raise exception 'ends_on must be after starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    raise exception 'a deposit is zero or more minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  insert into "app_private"."leases" ("tenant_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
    "rent", "currency", "frequency", "deposit", "metadata", "created_by")
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, coalesce(create_lease.frequency, 'monthly'), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) from public, anon;
grant execute on function "app_private"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) to authenticated, service_role;

-- Starts a draft lease. Fails while another active lease of the unit
-- overlaps it. A deposit is received on the lease's deposit account and
-- held there until the lease ends.
create or replace function "app_private"."activate_lease"(lease_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."leases"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."leases" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "app_private"."leases" x
    where x."unit_id" = v_row."unit_id" and x."id" <> v_row."id" and x."status" = 'active'
      and daterange(x."starts_on", x."ends_on") && daterange(v_row."starts_on", v_row."ends_on")
  ) then
    raise exception 'another active lease of this unit overlaps these dates' using errcode = '23P01', hint = 'LEASE_OVERLAP';
  end if;
  if v_row."deposit" > 0 then
    v_account := "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id"));
    perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row."deposit"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."deposit")),
      'leases', v_row."id"::text, 'Deposit received', 'leases.deposit:' || v_row."id"::text, null,
      jsonb_build_object('leaseId', v_row."id"));
    v_hold := "better_supabase"."ledger_hold"(v_account, v_row."deposit", 'leases', v_row."id"::text, null);
  end if;
  update "app_private"."leases" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."activate_lease"(uuid) from public, anon;
grant execute on function "app_private"."activate_lease"(uuid) to authenticated, service_role;

-- Extends an active lease with a fixed end to a later ends_on, at a new
-- rent when one is given. Periods posted from then on use the new rent.
create or replace function "app_private"."renew_lease"(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."leases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."leases" x where x."id" = renew_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active lease can be renewed' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_row."ends_on" is null then
    raise exception 'this lease has no end; it runs until it is terminated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if renew_lease.ends_on is null or renew_lease.ends_on <= v_row."ends_on" then
    raise exception 'a renewal ends after the current end' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if renew_lease.rent is not null and renew_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  update "app_private"."leases" x set "ends_on" = renew_lease.ends_on, "rent" = coalesce(renew_lease.rent, x."rent"),
      "renewed_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."renew_lease"(uuid, date, bigint) from public, anon;
grant execute on function "app_private"."renew_lease"(uuid, date, bigint) to authenticated, service_role;

-- Ends a lease on terminates_on (default today): ended on or after its end,
-- terminated before. No rent posts for periods from that day. The deposit
-- hold is captured for deposit_deduction (into rent income) and the rest
-- goes back to the party. A draft is terminated without touching the ledger.
create or replace function "app_private"."terminate_lease"(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."leases"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."leases" x where x."id" = terminate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'active') then
    raise exception 'this lease has already ended' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_on < v_row."starts_on" and v_row."status" = 'active' then
    raise exception 'a lease can''t end before it starts' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if exists (select 1 from "app_private"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" >= v_on) then
    raise exception 'rent is already posted for a period from this date; pick a later date' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  v_held := coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0);
  if v_deduction < 0 or v_deduction > v_held then
    raise exception 'a deduction is zero or more and at most the deposit held' using errcode = '22023', hint = 'LEASE_DEPOSIT_INVALID';
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform "better_supabase"."ledger_capture"(v_row."deposit_hold_id", "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform "better_supabase"."ledger_release"(v_row."deposit_hold_id");
    end if;
    if v_held - v_deduction > 0 then
      perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', v_held - v_deduction)),
        'leases', v_row."id"::text, 'Deposit refunded', 'leases.deposit_refund:' || v_row."id"::text, null,
        jsonb_build_object('leaseId', v_row."id"));
    end if;
  end if;
  update "app_private"."leases" x set
      "status" = case when x."status" = 'active' and x."ends_on" is not null and v_on >= x."ends_on" then 'ended' else 'terminated' end,
      "terminated_on" = v_on, "termination_reason" = nullif(trim(terminate_lease.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."terminate_lease"(uuid, date, text, bigint) from public, anon;
grant execute on function "app_private"."terminate_lease"(uuid, date, text, bigint) to authenticated, service_role;

create or replace function "app_private"."get_lease"(lease_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."leases"%rowtype;
begin
  select * into v_row from "app_private"."leases" x where x."id" = get_lease.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."get_lease"(uuid) from public, anon;
grant execute on function "app_private"."get_lease"(uuid) to authenticated, service_role;

-- Leases, latest start first. filters is { status, unitId, partyType, partyId
-- (each a value or a list), sort, direction, facet, count, limit, after, offset,
-- paged, total, totalCap } (ADR 0749).
create or replace function "app_private"."list_leases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_leases.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'unitId') then
      raise exception 'facet is one of status, unitId' using errcode = '22023', hint = 'LEASE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'unitId' then (x."unit_id")::text end) as v
      from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."ends_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."ends_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "app_private"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "app_private"."list_leases"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_leases"(uuid, jsonb) to authenticated, service_role;

-- Posts the rent of every period of an active lease that starts on or
-- before through (default today), up to max_rows charges. Each period posts
-- once: the charge row is unique per lease and period, and its ledger
-- transaction carries the key lease:<id>:rent:<period start>. Without a
-- tenant it runs for every organization and needs the service role, so a
-- scheduled job can call it.
create or replace function "app_private"."post_due_rent"(tenant uuid default null, through date default null, max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "app_private"."leases"%rowtype;
  v_charge "app_private"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "app_private"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."tenant_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "app_private"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "app_private"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        
        null;
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."post_due_rent"(uuid, date, integer) from public, anon;
grant execute on function "app_private"."post_due_rent"(uuid, date, integer) to authenticated, service_role;

-- Records a rent payment: it moves amount from the lease's receivable to
-- rent received. With a reference a second call returns the first payment.
create or replace function "app_private"."record_rent_payment"(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "app_private"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."tenant_id" = v_row."tenant_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    
    null;
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$$;
revoke execute on function "app_private"."record_rent_payment"(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function "app_private"."record_rent_payment"(uuid, bigint, timestamptz, text) to authenticated, service_role;

create or replace function "app_private"."list_lease_charges"(lease_id uuid, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."leases"%rowtype;
begin
  select * into v_row from "app_private"."leases" x where x."id" = list_lease_charges.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'leaseId', q."lease_id", 'periodStart', q."period_start", 'periodEnd', q."period_end", 'amount', q."amount"::text, 'currency', q."currency", 'transactionId', q."transaction_id", 'createdAt', q."created_at") order by q."period_start" desc), '[]'::jsonb)
    from (
      select * from "app_private"."lease_charges" y where y."lease_id" = v_row."id"
      order by y."period_start" desc
      limit least(greatest(coalesce(list_lease_charges.page_size, 200), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "app_private"."list_lease_charges"(uuid, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."leases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."leases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."leases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."leases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."lease_charges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."lease_charges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."lease_charges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."lease_charges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:916537b0ac15a44d934f0953f1905d46b0489cbc62ee42af0d92f389f7ae4b1d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block leases@3 managed
-- @bsb-hash sha256:550c6862adbeb28d0752f7b3ef1e210c3d641430a4a6ac3a47f6cab0f9c22fea
-- Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals and terminations. Maintenance requests are a tasks instance on the unit.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, and deposits held through ledger holds.

create table "better_supabase"."leases" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "unit_id" uuid not null references "better_supabase"."assets" ("id") on delete restrict,
  -- The party renting the unit: a registered subject such as a contact.
  "party_type" text not null,
  "party_id" text not null,
  "title" text not null constraint bsb_leases_title_check check (length("title") >= 1 and length("title") <= 200),
  "status" text not null default 'draft' constraint bsb_leases_status_check check ("status" in ('draft', 'active', 'ended', 'terminated')),
  "starts_on" date not null,
  -- Null runs the lease until it is terminated.
  "ends_on" date,
  -- Minor units of currency per period (ADR 0037).
  "rent" bigint not null constraint bsb_leases_rent_check check ("rent" > 0),
  "currency" char(3) not null constraint bsb_leases_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' constraint bsb_leases_frequency_check check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "deposit" bigint not null default 0 constraint bsb_leases_deposit_check check ("deposit" >= 0),
  -- The ledger hold that keeps the deposit aside while the lease runs.
  "deposit_hold_id" uuid,
  "renewed_at" timestamptz,
  "terminated_on" date,
  "termination_reason" text constraint bsb_leases_termination_reason_check check ("termination_reason" is null or length("termination_reason") <= 2000),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_leases_check check ("ends_on" is null or "ends_on" > "starts_on")
);
create index "leases_tenant_idx" on "better_supabase"."leases" ("tenant_id", "status", "starts_on" desc);
create index "leases_unit_idx" on "better_supabase"."leases" ("unit_id");
create index "leases_party_idx" on "better_supabase"."leases" ("tenant_id", "party_type", "party_id");
create index "leases_deposit_hold_idx" on "better_supabase"."leases" ("deposit_hold_id") where "deposit_hold_id" is not null;
alter table "better_supabase"."leases" enable row level security;
revoke all on "better_supabase"."leases" from public, anon, authenticated;
grant select on "better_supabase"."leases" to authenticated;
grant all on "better_supabase"."leases" to service_role;
create policy bsb_leases_read on "better_supabase"."leases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));

-- One row per rent period posted to the ledger, so each period posts once.
create table "better_supabase"."lease_charges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "lease_id" uuid not null references "better_supabase"."leases" ("id") on delete restrict,
  "period_start" date not null,
  "period_end" date not null,
  "amount" bigint not null constraint bsb_lease_charges_amount_check check ("amount" > 0),
  "currency" char(3) not null,
  "transaction_id" uuid not null,
  "created_at" timestamptz not null default now(),
  unique ("lease_id", "period_start"),
  constraint bsb_lease_charges_check check ("period_end" > "period_start")
);
create index "lease_charges_tenant_idx" on "better_supabase"."lease_charges" ("tenant_id", "period_start" desc);
create index "lease_charges_transaction_idx" on "better_supabase"."lease_charges" ("transaction_id");
alter table "better_supabase"."lease_charges" enable row level security;
revoke all on "better_supabase"."lease_charges" from public, anon, authenticated;
grant select on "better_supabase"."lease_charges" to authenticated;
grant all on "better_supabase"."lease_charges" to service_role;
create policy bsb_lease_charges_read on "better_supabase"."lease_charges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));


-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
-- fields: the extra columns to set.

create or replace function "better_supabase"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_unit text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_lease.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  select u."name" into v_unit from "better_supabase"."assets" u
    where u."id" = create_lease.unit_id and u."tenant_id" = create_lease.tenant and u."retired_at" is null;
  if not found then
    raise exception 'the unit is unknown, retired or not in this organization' using errcode = '22023', hint = 'LEASE_UNIT_INVALID';
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not false then
    raise exception 'the party is unknown or not in this organization' using errcode = '22023', hint = 'LEASE_PARTY_INVALID';
  end if;
  if create_lease.starts_on is null then
    raise exception 'a lease needs starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    raise exception 'ends_on must be after starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    raise exception 'a deposit is zero or more minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  insert into "better_supabase"."leases" ("tenant_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
    "rent", "currency", "frequency", "deposit", "metadata", "created_by")
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, coalesce(create_lease.frequency, 'monthly'), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) to authenticated, service_role;

-- Starts a draft lease. Fails while another active lease of the unit
-- overlaps it. A deposit is received on the lease's deposit account and
-- held there until the lease ends.
create or replace function "better_supabase"."activate_lease"(lease_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "better_supabase"."leases" x
    where x."unit_id" = v_row."unit_id" and x."id" <> v_row."id" and x."status" = 'active'
      and daterange(x."starts_on", x."ends_on") && daterange(v_row."starts_on", v_row."ends_on")
  ) then
    raise exception 'another active lease of this unit overlaps these dates' using errcode = '23P01', hint = 'LEASE_OVERLAP';
  end if;
  if v_row."deposit" > 0 then
    v_account := "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id"));
    perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row."deposit"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."deposit")),
      'leases', v_row."id"::text, 'Deposit received', 'leases.deposit:' || v_row."id"::text, null,
      jsonb_build_object('leaseId', v_row."id"));
    v_hold := "better_supabase"."ledger_hold"(v_account, v_row."deposit", 'leases', v_row."id"::text, null);
  end if;
  update "better_supabase"."leases" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."activate_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."activate_lease"(uuid) to authenticated, service_role;

-- Extends an active lease with a fixed end to a later ends_on, at a new
-- rent when one is given. Periods posted from then on use the new rent.
create or replace function "better_supabase"."renew_lease"(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = renew_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active lease can be renewed' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_row."ends_on" is null then
    raise exception 'this lease has no end; it runs until it is terminated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if renew_lease.ends_on is null or renew_lease.ends_on <= v_row."ends_on" then
    raise exception 'a renewal ends after the current end' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if renew_lease.rent is not null and renew_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  update "better_supabase"."leases" x set "ends_on" = renew_lease.ends_on, "rent" = coalesce(renew_lease.rent, x."rent"),
      "renewed_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."renew_lease"(uuid, date, bigint) from public, anon;
grant execute on function "better_supabase"."renew_lease"(uuid, date, bigint) to authenticated, service_role;

-- Ends a lease on terminates_on (default today): ended on or after its end,
-- terminated before. No rent posts for periods from that day. The deposit
-- hold is captured for deposit_deduction (into rent income) and the rest
-- goes back to the party. A draft is terminated without touching the ledger.
create or replace function "better_supabase"."terminate_lease"(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = terminate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'active') then
    raise exception 'this lease has already ended' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_on < v_row."starts_on" and v_row."status" = 'active' then
    raise exception 'a lease can''t end before it starts' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" >= v_on) then
    raise exception 'rent is already posted for a period from this date; pick a later date' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  v_held := coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0);
  if v_deduction < 0 or v_deduction > v_held then
    raise exception 'a deduction is zero or more and at most the deposit held' using errcode = '22023', hint = 'LEASE_DEPOSIT_INVALID';
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform "better_supabase"."ledger_capture"(v_row."deposit_hold_id", "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform "better_supabase"."ledger_release"(v_row."deposit_hold_id");
    end if;
    if v_held - v_deduction > 0 then
      perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', v_held - v_deduction)),
        'leases', v_row."id"::text, 'Deposit refunded', 'leases.deposit_refund:' || v_row."id"::text, null,
        jsonb_build_object('leaseId', v_row."id"));
    end if;
  end if;
  update "better_supabase"."leases" x set
      "status" = case when x."status" = 'active' and x."ends_on" is not null and v_on >= x."ends_on" then 'ended' else 'terminated' end,
      "terminated_on" = v_on, "termination_reason" = nullif(trim(terminate_lease.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) to authenticated, service_role;

create or replace function "better_supabase"."get_lease"(lease_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = get_lease.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."get_lease"(uuid) to authenticated, service_role;

-- Leases, latest start first. filters is { status, unitId, partyType, partyId
-- (each a value or a list), sort, direction, facet, count, limit, after, offset,
-- paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_leases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_leases.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'unitId') then
      raise exception 'facet is one of status, unitId' using errcode = '22023', hint = 'LEASE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'unitId' then (x."unit_id")::text end) as v
      from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."ends_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."ends_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_leases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_leases"(uuid, jsonb) to authenticated, service_role;

-- Posts the rent of every period of an active lease that starts on or
-- before through (default today), up to max_rows charges. Each period posts
-- once: the charge row is unique per lease and period, and its ledger
-- transaction carries the key lease:<id>:rent:<period start>. Without a
-- tenant it runs for every organization and needs the service role, so a
-- scheduled job can call it.
create or replace function "better_supabase"."post_due_rent"(tenant uuid default null, through date default null, max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "better_supabase"."leases"%rowtype;
  v_charge "better_supabase"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "better_supabase"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."tenant_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "better_supabase"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        
        null;
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."post_due_rent"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."post_due_rent"(uuid, date, integer) to authenticated, service_role;

-- Records a rent payment: it moves amount from the lease's receivable to
-- rent received. With a reference a second call returns the first payment.
create or replace function "better_supabase"."record_rent_payment"(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."tenant_id" = v_row."tenant_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    
    null;
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) to authenticated, service_role;

create or replace function "better_supabase"."list_lease_charges"(lease_id uuid, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = list_lease_charges.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'leaseId', q."lease_id", 'periodStart', q."period_start", 'periodEnd', q."period_end", 'amount', q."amount"::text, 'currency', q."currency", 'transactionId', q."transaction_id", 'createdAt', q."created_at") order by q."period_start" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id"
      order by y."period_start" desc
      limit least(greatest(coalesce(list_lease_charges.page_size, 200), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_lease_charges"(uuid, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."leases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."leases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."leases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."leases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."lease_charges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."lease_charges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."lease_charges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."lease_charges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.leases.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_lease"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) $$;
revoke execute on function "api"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) from public, anon;
grant execute on function "api"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) to authenticated, service_role;

create or replace function "api"."activate_lease"(lease_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."activate_lease"($1) $$;
revoke execute on function "api"."activate_lease"(uuid) from public, anon;
grant execute on function "api"."activate_lease"(uuid) to authenticated, service_role;

create or replace function "api"."renew_lease"(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."renew_lease"($1, $2, $3) $$;
revoke execute on function "api"."renew_lease"(uuid, date, bigint) from public, anon;
grant execute on function "api"."renew_lease"(uuid, date, bigint) to authenticated, service_role;

create or replace function "api"."terminate_lease"(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."terminate_lease"($1, $2, $3, $4) $$;
revoke execute on function "api"."terminate_lease"(uuid, date, text, bigint) from public, anon;
grant execute on function "api"."terminate_lease"(uuid, date, text, bigint) to authenticated, service_role;

create or replace function "api"."get_lease"(lease_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_lease"($1) $$;
revoke execute on function "api"."get_lease"(uuid) from public, anon;
grant execute on function "api"."get_lease"(uuid) to authenticated, service_role;

create or replace function "api"."list_leases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_leases"($1, $2) $$;
revoke execute on function "api"."list_leases"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_leases"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."post_due_rent"(tenant uuid default null, through date default null, max_rows integer default 500)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."post_due_rent"($1, $2, $3) $$;
revoke execute on function "api"."post_due_rent"(uuid, date, integer) from public, anon;
grant execute on function "api"."post_due_rent"(uuid, date, integer) to authenticated, service_role;

create or replace function "api"."record_rent_payment"(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_rent_payment"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_rent_payment"(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function "api"."record_rent_payment"(uuid, bigint, timestamptz, text) to authenticated, service_role;

create or replace function "api"."list_lease_charges"(lease_id uuid, page_size integer default 200)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_lease_charges"($1, $2) $$;
revoke execute on function "api"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "api"."list_lease_charges"(uuid, integer) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:916537b0ac15a44d934f0953f1905d46b0489cbc62ee42af0d92f389f7ae4b1d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block leases@3 managed
-- @bsb-hash sha256:6dc49ed2cbd6d6022aec03045b8c0c1add2889bbf4e018a97b6d05807f126219
-- Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals and terminations. Maintenance requests are a tasks instance on the unit.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, and deposits held through ledger holds.

-- better_supabase.leases is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."leases" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."leases" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."leases" add column if not exists "unit_id" uuid references "better_supabase"."assets" ("id") on delete restrict;
alter table "better_supabase"."leases" add column if not exists "party_type" text;
alter table "better_supabase"."leases" add column if not exists "party_id" text;
alter table "better_supabase"."leases" add column if not exists "title" text constraint bsb_leases_title_check check (length("title") >= 1 and length("title") <= 200);
alter table "better_supabase"."leases" add column if not exists "status" text not null default 'draft' constraint bsb_leases_status_check check ("status" in ('draft', 'active', 'ended', 'terminated'));
alter table "better_supabase"."leases" add column if not exists "starts_on" date;
alter table "better_supabase"."leases" add column if not exists "ends_on" date;
alter table "better_supabase"."leases" add column if not exists "rent" bigint constraint bsb_leases_rent_check check ("rent" > 0);
alter table "better_supabase"."leases" add column if not exists "currency" char(3) constraint bsb_leases_currency_check check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."leases" add column if not exists "frequency" text not null default 'monthly' constraint bsb_leases_frequency_check check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly'));
alter table "better_supabase"."leases" add column if not exists "deposit" bigint not null default 0 constraint bsb_leases_deposit_check check ("deposit" >= 0);
alter table "better_supabase"."leases" add column if not exists "deposit_hold_id" uuid;
alter table "better_supabase"."leases" add column if not exists "renewed_at" timestamptz;
alter table "better_supabase"."leases" add column if not exists "terminated_on" date;
alter table "better_supabase"."leases" add column if not exists "termination_reason" text constraint bsb_leases_termination_reason_check check ("termination_reason" is null or length("termination_reason") <= 2000);
alter table "better_supabase"."leases" add column if not exists "metadata" jsonb not null default '{}'::jsonb;
alter table "better_supabase"."leases" add column if not exists "created_by" uuid;
alter table "better_supabase"."leases" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."leases" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "leases_tenant_idx" on "better_supabase"."leases" ("tenant_id", "status", "starts_on" desc);
create index if not exists "leases_unit_idx" on "better_supabase"."leases" ("unit_id");
create index if not exists "leases_party_idx" on "better_supabase"."leases" ("tenant_id", "party_type", "party_id");
create index if not exists "leases_deposit_hold_idx" on "better_supabase"."leases" ("deposit_hold_id") where "deposit_hold_id" is not null;
alter table "better_supabase"."leases" enable row level security;
grant select on "better_supabase"."leases" to authenticated;
grant all on "better_supabase"."leases" to service_role;
create policy bsb_leases_select on "better_supabase"."leases"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));

-- One row per rent period posted to the ledger, so each period posts once.
-- better_supabase.lease_charges is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."lease_charges" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."lease_charges" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."lease_charges" add column if not exists "lease_id" uuid references "better_supabase"."leases" ("id") on delete restrict;
alter table "better_supabase"."lease_charges" add column if not exists "period_start" date;
alter table "better_supabase"."lease_charges" add column if not exists "period_end" date;
alter table "better_supabase"."lease_charges" add column if not exists "amount" bigint constraint bsb_lease_charges_amount_check check ("amount" > 0);
alter table "better_supabase"."lease_charges" add column if not exists "currency" char(3);
alter table "better_supabase"."lease_charges" add column if not exists "transaction_id" uuid;
alter table "better_supabase"."lease_charges" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "lease_charges_lease_id_period_start_key" on "better_supabase"."lease_charges" ("lease_id", "period_start");
create index if not exists "lease_charges_tenant_idx" on "better_supabase"."lease_charges" ("tenant_id", "period_start" desc);
create index if not exists "lease_charges_transaction_idx" on "better_supabase"."lease_charges" ("transaction_id");
alter table "better_supabase"."lease_charges" enable row level security;
grant select on "better_supabase"."lease_charges" to authenticated;
grant all on "better_supabase"."lease_charges" to service_role;
create policy bsb_lease_charges_select on "better_supabase"."lease_charges"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));


-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
-- fields: the extra columns to set.

create or replace function "better_supabase"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_unit text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_lease.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  select u."name" into v_unit from "better_supabase"."assets" u
    where u."id" = create_lease.unit_id and u."tenant_id" = create_lease.tenant and u."retired_at" is null;
  if not found then
    raise exception 'the unit is unknown, retired or not in this organization' using errcode = '22023', hint = 'LEASE_UNIT_INVALID';
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not false then
    raise exception 'the party is unknown or not in this organization' using errcode = '22023', hint = 'LEASE_PARTY_INVALID';
  end if;
  if create_lease.starts_on is null then
    raise exception 'a lease needs starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    raise exception 'ends_on must be after starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    raise exception 'a deposit is zero or more minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  insert into "better_supabase"."leases" ("tenant_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
    "rent", "currency", "frequency", "deposit", "metadata", "created_by")
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, better_supabase.as_column_type(coalesce(create_lease.frequency, 'monthly'), (null::"better_supabase"."leases")."frequency"), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) to authenticated, service_role;

-- Starts a draft lease. Fails while another active lease of the unit
-- overlaps it. A deposit is received on the lease's deposit account and
-- held there until the lease ends.
create or replace function "better_supabase"."activate_lease"(lease_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "better_supabase"."leases" x
    where x."unit_id" = v_row."unit_id" and x."id" <> v_row."id" and x."status" = 'active'
      and daterange(x."starts_on", x."ends_on") && daterange(v_row."starts_on", v_row."ends_on")
  ) then
    raise exception 'another active lease of this unit overlaps these dates' using errcode = '23P01', hint = 'LEASE_OVERLAP';
  end if;
  if v_row."deposit" > 0 then
    v_account := "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id"));
    perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row."deposit"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."deposit")),
      'leases', v_row."id"::text, 'Deposit received', 'leases.deposit:' || v_row."id"::text, null,
      jsonb_build_object('leaseId', v_row."id"));
    v_hold := "better_supabase"."ledger_hold"(v_account, v_row."deposit", 'leases', v_row."id"::text, null);
  end if;
  update "better_supabase"."leases" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."activate_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."activate_lease"(uuid) to authenticated, service_role;

-- Extends an active lease with a fixed end to a later ends_on, at a new
-- rent when one is given. Periods posted from then on use the new rent.
create or replace function "better_supabase"."renew_lease"(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = renew_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active lease can be renewed' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_row."ends_on" is null then
    raise exception 'this lease has no end; it runs until it is terminated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if renew_lease.ends_on is null or renew_lease.ends_on <= v_row."ends_on" then
    raise exception 'a renewal ends after the current end' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if renew_lease.rent is not null and renew_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  update "better_supabase"."leases" x set "ends_on" = renew_lease.ends_on, "rent" = coalesce(renew_lease.rent, x."rent"),
      "renewed_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."renew_lease"(uuid, date, bigint) from public, anon;
grant execute on function "better_supabase"."renew_lease"(uuid, date, bigint) to authenticated, service_role;

-- Ends a lease on terminates_on (default today): ended on or after its end,
-- terminated before. No rent posts for periods from that day. The deposit
-- hold is captured for deposit_deduction (into rent income) and the rest
-- goes back to the party. A draft is terminated without touching the ledger.
create or replace function "better_supabase"."terminate_lease"(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = terminate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'active') then
    raise exception 'this lease has already ended' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_on < v_row."starts_on" and v_row."status" = 'active' then
    raise exception 'a lease can''t end before it starts' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" >= v_on) then
    raise exception 'rent is already posted for a period from this date; pick a later date' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  v_held := coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0);
  if v_deduction < 0 or v_deduction > v_held then
    raise exception 'a deduction is zero or more and at most the deposit held' using errcode = '22023', hint = 'LEASE_DEPOSIT_INVALID';
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform "better_supabase"."ledger_capture"(v_row."deposit_hold_id", "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform "better_supabase"."ledger_release"(v_row."deposit_hold_id");
    end if;
    if v_held - v_deduction > 0 then
      perform "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', v_held - v_deduction)),
        'leases', v_row."id"::text, 'Deposit refunded', 'leases.deposit_refund:' || v_row."id"::text, null,
        jsonb_build_object('leaseId', v_row."id"));
    end if;
  end if;
  update "better_supabase"."leases" x set
      "status" = better_supabase.as_column_type(case when x."status" = 'active' and x."ends_on" is not null and v_on >= x."ends_on" then 'ended' else 'terminated' end, (null::"better_supabase"."leases")."status"),
      "terminated_on" = v_on, "termination_reason" = nullif(trim(terminate_lease.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) to authenticated, service_role;

create or replace function "better_supabase"."get_lease"(lease_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = get_lease.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."get_lease"(uuid) to authenticated, service_role;

-- Leases, latest start first. filters is { status, unitId, partyType, partyId
-- (each a value or a list), sort, direction, facet, count, limit, after, offset,
-- paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_leases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_leases.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'unitId') then
      raise exception 'facet is one of status, unitId' using errcode = '22023', hint = 'LEASE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text when 'unitId' then (x."unit_id")::text end) as v
      from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."ends_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."ends_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = x."tenant_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."leases" x
      where x."tenant_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_leases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_leases"(uuid, jsonb) to authenticated, service_role;

-- Posts the rent of every period of an active lease that starts on or
-- before through (default today), up to max_rows charges. Each period posts
-- once: the charge row is unique per lease and period, and its ledger
-- transaction carries the key lease:<id>:rent:<period start>. Without a
-- tenant it runs for every organization and needs the service role, so a
-- scheduled job can call it.
create or replace function "better_supabase"."post_due_rent"(tenant uuid default null, through date default null, max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "better_supabase"."leases"%rowtype;
  v_charge "better_supabase"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "better_supabase"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."tenant_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "better_supabase"."lease_charges" ("tenant_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."tenant_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        
        null;
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."post_due_rent"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."post_due_rent"(uuid, date, integer) to authenticated, service_role;

-- Records a rent payment: it moves amount from the lease's receivable to
-- rent received. With a reference a second call returns the first payment.
create or replace function "better_supabase"."record_rent_payment"(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."tenant_id" = v_row."tenant_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    
    null;
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) to authenticated, service_role;

create or replace function "better_supabase"."list_lease_charges"(lease_id uuid, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = list_lease_charges.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'leaseId', q."lease_id", 'periodStart', q."period_start", 'periodEnd', q."period_end", 'amount', q."amount"::text, 'currency', q."currency", 'transactionId', q."transaction_id", 'createdAt', q."created_at") order by q."period_start" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id"
      order by y."period_start" desc
      limit least(greatest(coalesce(list_lease_charges.page_size, 200), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_lease_charges"(uuid, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."leases" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."leases" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."leases" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."leases" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."lease_charges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."lease_charges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."lease_charges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."lease_charges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:916537b0ac15a44d934f0953f1905d46b0489cbc62ee42af0d92f389f7ae4b1d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block leases@3 managed
-- @bsb-hash sha256:76148e80c31424dc461db9c1cde8e089260b2b0fcb79655301fb7b677a542852
-- Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals and terminations. Maintenance requests are a tasks instance on the unit.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, and deposits held through ledger holds.

create table "better_supabase"."leases" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "unit_id" uuid not null references "better_supabase"."assets" ("id") on delete restrict,
  -- The party renting the unit: a registered subject such as a contact.
  "party_type" text not null,
  "party_id" text not null,
  "title" text not null constraint bsb_leases_title_check check (length("title") >= 1 and length("title") <= 200),
  "status" text not null default 'draft' constraint bsb_leases_status_check check ("status" in ('draft', 'active', 'ended', 'terminated')),
  "starts_on" date not null,
  -- Null runs the lease until it is terminated.
  "ends_on" date,
  -- Minor units of currency per period (ADR 0037).
  "rent" bigint not null constraint bsb_leases_rent_check check ("rent" > 0),
  "currency" char(3) not null constraint bsb_leases_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' constraint bsb_leases_frequency_check check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "deposit" bigint not null default 0 constraint bsb_leases_deposit_check check ("deposit" >= 0),
  -- The ledger hold that keeps the deposit aside while the lease runs.
  "deposit_hold_id" uuid,
  "renewed_at" timestamptz,
  "terminated_on" date,
  "termination_reason" text constraint bsb_leases_termination_reason_check check ("termination_reason" is null or length("termination_reason") <= 2000),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint bsb_leases_check check ("ends_on" is null or "ends_on" > "starts_on")
);
create index "leases_tenant_idx" on "better_supabase"."leases" ("org_id", "status", "starts_on" desc);
create index "leases_unit_idx" on "better_supabase"."leases" ("unit_id");
create index "leases_party_idx" on "better_supabase"."leases" ("org_id", "party_type", "party_id");
create index "leases_deposit_hold_idx" on "better_supabase"."leases" ("deposit_hold_id") where "deposit_hold_id" is not null;
alter table "better_supabase"."leases" enable row level security;
revoke all on "better_supabase"."leases" from public, anon, authenticated;
grant select on "better_supabase"."leases" to authenticated;
grant all on "better_supabase"."leases" to service_role;
create policy bsb_leases_read on "better_supabase"."leases"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('leases.read')));

-- One row per rent period posted to the ledger, so each period posts once.
create table "better_supabase"."lease_charges" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "lease_id" uuid not null references "better_supabase"."leases" ("id") on delete restrict,
  "period_start" date not null,
  "period_end" date not null,
  "amount" bigint not null constraint bsb_lease_charges_amount_check check ("amount" > 0),
  "currency" char(3) not null,
  "transaction_id" uuid not null,
  "created_at" timestamptz not null default now(),
  unique ("lease_id", "period_start"),
  constraint bsb_lease_charges_check check ("period_end" > "period_start")
);
create index "lease_charges_tenant_idx" on "better_supabase"."lease_charges" ("org_id", "period_start" desc);
create index "lease_charges_transaction_idx" on "better_supabase"."lease_charges" ("transaction_id");
alter table "better_supabase"."lease_charges" enable row level security;
revoke all on "better_supabase"."lease_charges" from public, anon, authenticated;
grant select on "better_supabase"."lease_charges" to authenticated;
grant all on "better_supabase"."lease_charges" to service_role;
create policy bsb_lease_charges_read on "better_supabase"."lease_charges"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('leases.read')));


-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
-- fields: the extra columns to set.

create or replace function "better_supabase"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_unit text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_lease.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  select u."name" into v_unit from "better_supabase"."assets" u
    where u."id" = create_lease.unit_id and u."org_id" = create_lease.tenant and u."retired_at" is null;
  if not found then
    raise exception 'the unit is unknown, retired or not in this organization' using errcode = '22023', hint = 'LEASE_UNIT_INVALID';
  end if;
  if create_lease.party_type is null or create_lease.party_id is null
    or not false then
    raise exception 'the party is unknown or not in this organization' using errcode = '22023', hint = 'LEASE_PARTY_INVALID';
  end if;
  if create_lease.starts_on is null then
    raise exception 'a lease needs starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.ends_on is not null and create_lease.ends_on <= create_lease.starts_on then
    raise exception 'ends_on must be after starts_on' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.rent is null or create_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if create_lease.currency is null or create_lease.currency !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three-letter currency code' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.frequency, 'monthly') not in ('weekly', 'monthly', 'quarterly', 'yearly') then
    raise exception 'frequency is weekly, monthly, quarterly or yearly' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if coalesce(create_lease.deposit, 0) < 0 then
    raise exception 'a deposit is zero or more minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  insert into "better_supabase"."leases" ("org_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
    "rent", "currency", "frequency", "deposit", "metadata", "created_by")
  values (create_lease.tenant, create_lease.unit_id, create_lease.party_type, create_lease.party_id,
    coalesce(nullif(trim(create_lease.title), ''), left(v_unit, 190) || ' lease'), create_lease.starts_on, create_lease.ends_on,
    create_lease.rent, create_lease.currency, coalesce(create_lease.frequency, 'monthly'), coalesce(create_lease.deposit, 0),
    coalesce(create_lease.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = v_row."org_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb) to authenticated, service_role;

-- Starts a draft lease. Fails while another active lease of the unit
-- overlaps it. A deposit is received on the lease's deposit account and
-- held there until the lease ends.
create or replace function "better_supabase"."activate_lease"(lease_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "better_supabase"."leases" x
    where x."unit_id" = v_row."unit_id" and x."id" <> v_row."id" and x."status" = 'active'
      and daterange(x."starts_on", x."ends_on") && daterange(v_row."starts_on", v_row."ends_on")
  ) then
    raise exception 'another active lease of this unit overlaps these dates' using errcode = '23P01', hint = 'LEASE_OVERLAP';
  end if;
  if v_row."deposit" > 0 then
    v_account := "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id"));
    perform "better_supabase"."ledger_post"(v_row."org_id", 'lease.deposit',
      jsonb_build_array(
        jsonb_build_object('account', v_account, 'amount', v_row."deposit"),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."deposit")),
      'leases', v_row."id"::text, 'Deposit received', 'leases.deposit:' || v_row."id"::text, null,
      jsonb_build_object('leaseId', v_row."id"));
    v_hold := "better_supabase"."ledger_hold"(v_account, v_row."deposit", 'leases', v_row."id"::text, null);
  end if;
  update "better_supabase"."leases" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = v_row."org_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."activate_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."activate_lease"(uuid) to authenticated, service_role;

-- Extends an active lease with a fixed end to a later ends_on, at a new
-- rent when one is given. Periods posted from then on use the new rent.
create or replace function "better_supabase"."renew_lease"(lease_id uuid, ends_on date, rent bigint default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = renew_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'active' then
    raise exception 'only an active lease can be renewed' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_row."ends_on" is null then
    raise exception 'this lease has no end; it runs until it is terminated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if renew_lease.ends_on is null or renew_lease.ends_on <= v_row."ends_on" then
    raise exception 'a renewal ends after the current end' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if renew_lease.rent is not null and renew_lease.rent <= 0 then
    raise exception 'rent is more than zero minor units' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  update "better_supabase"."leases" x set "ends_on" = renew_lease.ends_on, "rent" = coalesce(renew_lease.rent, x."rent"),
      "renewed_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = v_row."org_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."renew_lease"(uuid, date, bigint) from public, anon;
grant execute on function "better_supabase"."renew_lease"(uuid, date, bigint) to authenticated, service_role;

-- Ends a lease on terminates_on (default today): ended on or after its end,
-- terminated before. No rent posts for periods from that day. The deposit
-- hold is captured for deposit_deduction (into rent income) and the rest
-- goes back to the party. A draft is terminated without touching the ledger.
create or replace function "better_supabase"."terminate_lease"(lease_id uuid, terminates_on date default null, reason text default null, deposit_deduction bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leases" x where x."id" = terminate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'active') then
    raise exception 'this lease has already ended' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if v_on < v_row."starts_on" and v_row."status" = 'active' then
    raise exception 'a lease can''t end before it starts' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" >= v_on) then
    raise exception 'rent is already posted for a period from this date; pick a later date' using errcode = '22023', hint = 'LEASE_TERMS_INVALID';
  end if;
  v_held := coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0);
  if v_deduction < 0 or v_deduction > v_held then
    raise exception 'a deduction is zero or more and at most the deposit held' using errcode = '22023', hint = 'LEASE_DEPOSIT_INVALID';
  end if;
  if v_held > 0 then
    if v_deduction > 0 then
      perform "better_supabase"."ledger_capture"(v_row."deposit_hold_id", "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), v_deduction, 'lease.deposit_deduction', 'Deposit deduction');
    else
      perform "better_supabase"."ledger_release"(v_row."deposit_hold_id");
    end if;
    if v_held - v_deduction > 0 then
      perform "better_supabase"."ledger_post"(v_row."org_id", 'lease.deposit_refund',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_deposit', 'leases.deposit:' || v_row."id"::text, 'Deposit ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, false, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -(v_held - v_deduction)),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', v_held - v_deduction)),
        'leases', v_row."id"::text, 'Deposit refunded', 'leases.deposit_refund:' || v_row."id"::text, null,
        jsonb_build_object('leaseId', v_row."id"));
    end if;
  end if;
  update "better_supabase"."leases" x set
      "status" = case when x."status" = 'active' and x."ends_on" is not null and v_on >= x."ends_on" then 'ended' else 'terminated' end,
      "terminated_on" = v_on, "termination_reason" = nullif(trim(terminate_lease.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = v_row."org_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) from public, anon;
grant execute on function "better_supabase"."terminate_lease"(uuid, date, text, bigint) to authenticated, service_role;

create or replace function "better_supabase"."get_lease"(lease_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = get_lease.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = v_row."org_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."get_lease"(uuid) to authenticated, service_role;

-- Leases, latest start first. filters is { status, unitId, partyType, partyId
-- (each a value or a list), sort, direction, facet, count, limit, after, offset,
-- paged, total, totalCap } (ADR 0749).
create or replace function "better_supabase"."list_leases"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_leases.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 1000);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'unitId') then
      raise exception 'facet is one of status, unitId' using errcode = '22023', hint = 'LEASE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'unitId' then (x."unit_id")::text end) as v
      from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
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
      select 1 from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."starts_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."ends_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."ends_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (coalesce(x."ends_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."ends_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."ends_on", 'infinity'::date) = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."ends_on", 'infinity'::date) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEASE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'unitId', x."unit_id", 'partyType', x."party_type", 'partyId', x."party_id", 'title', x."title", 'status', x."status", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'rent', x."rent"::text, 'currency', x."currency", 'frequency', x."frequency", 'deposit', x."deposit"::text, 'depositHoldId', x."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = x."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = x."org_id" and x."code" = 'leases.rent:' || x."id"::text), 0)::text, 'renewedAt', x."renewed_at", 'terminatedOn', x."terminated_on", 'terminationReason', x."termination_reason", 'metadata', x."metadata", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."leases" x
      where x."org_id" = list_leases.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'unitId' is not null and jsonb_typeof(v_filters -> 'unitId') <> 'null' and not (jsonb_typeof(v_filters -> 'unitId') = 'array' and jsonb_array_length(v_filters -> 'unitId') = 0)) or x."unit_id" = any((case when jsonb_typeof(v_filters -> 'unitId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'unitId')) else array[v_filters ->> 'unitId'] end)::uuid[]))
        and (not (v_filters -> 'partyType' is not null and jsonb_typeof(v_filters -> 'partyType') <> 'null' and not (jsonb_typeof(v_filters -> 'partyType') = 'array' and jsonb_array_length(v_filters -> 'partyType') = 0)) or x."party_type" = any((case when jsonb_typeof(v_filters -> 'partyType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyType')) else array[v_filters ->> 'partyType'] end)::text[]))
        and (not (v_filters -> 'partyId' is not null and jsonb_typeof(v_filters -> 'partyId') <> 'null' and not (jsonb_typeof(v_filters -> 'partyId') = 'array' and jsonb_array_length(v_filters -> 'partyId') = 0)) or x."party_id" = any((case when jsonb_typeof(v_filters -> 'partyId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'partyId')) else array[v_filters ->> 'partyId'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_leases"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_leases"(uuid, jsonb) to authenticated, service_role;

-- Posts the rent of every period of an active lease that starts on or
-- before through (default today), up to max_rows charges. Each period posts
-- once: the charge row is unique per lease and period, and its ledger
-- transaction carries the key lease:<id>:rent:<period start>. Without a
-- tenant it runs for every organization and needs the service role, so a
-- scheduled job can call it.
create or replace function "better_supabase"."post_due_rent"(tenant uuid default null, through date default null, max_rows integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_through date := coalesce(post_due_rent.through, current_date);
  v_max integer := least(greatest(coalesce(post_due_rent.max_rows, 500), 1), 5000);
  v_count integer := 0;
  v_row "better_supabase"."leases"%rowtype;
  v_charge "better_supabase"."lease_charges"%rowtype;
  v_n integer;
  v_start date;
  v_end date;
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if post_due_rent.tenant is null then
    if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'posting rent for every organization needs the service role' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', post_due_rent.tenant, 'leases.manage'), false)) then
    raise exception 'not allowed to manage leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  <<periods>>
  for v_row in
    select * from "better_supabase"."leases" x
    where x."status" = 'active' and x."starts_on" <= v_through
      and (post_due_rent.tenant is null or x."org_id" = post_due_rent.tenant)
    order by x."id"
    for update skip locked
  loop
    v_n := 0;
    loop
      v_start := (v_row."starts_on" + v_n * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date;
      exit when v_start > v_through or (v_row."ends_on" is not null and v_start >= v_row."ends_on");
      if not exists (select 1 from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id" and y."period_start" = v_start) then
        exit periods when v_count >= v_max;
        v_end := least((v_row."starts_on" + (v_n + 1) * (case v_row."frequency" when 'weekly' then interval '1 week' when 'monthly' then interval '1 month' when 'quarterly' then interval '3 months' else interval '1 year' end))::date, coalesce(v_row."ends_on", 'infinity'::date));
        v_tx := "better_supabase"."ledger_post"(v_row."org_id", 'lease.rent',
          jsonb_build_array(
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', v_row."rent"),
            jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_income', 'leases.income:' || v_row."currency", 'Rent income ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', -v_row."rent")),
          'leases', v_row."id"::text, 'Rent from ' || v_start::text,
          'leases.rent:' || v_row."id"::text || ':' || v_start::text, v_start::timestamptz,
          jsonb_build_object('leaseId', v_row."id", 'periodStart', v_start, 'periodEnd', v_end));
        insert into "better_supabase"."lease_charges" ("org_id", "lease_id", "period_start", "period_end", "amount", "currency", "transaction_id")
        values (v_row."org_id", v_row."id", v_start, v_end, v_row."rent", v_row."currency", v_tx)
        returning * into v_charge;
        
        null;
        v_count := v_count + 1;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."post_due_rent"(uuid, date, integer) from public, anon;
grant execute on function "better_supabase"."post_due_rent"(uuid, date, integer) to authenticated, service_role;

-- Records a rent payment: it moves amount from the lease's receivable to
-- rent received. With a reference a second call returns the first payment.
create or replace function "better_supabase"."record_rent_payment"(lease_id uuid, amount bigint, paid_at timestamptz default null, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."leases"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = record_rent_payment.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft lease takes no payments' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  if record_rent_payment.amount is null or record_rent_payment.amount <= 0 then
    raise exception 'a payment is more than zero minor units' using errcode = '22023', hint = 'LEASE_PAYMENT_INVALID';
  end if;
  v_key := case when nullif(trim(record_rent_payment.reference), '') is not null
    then 'leases.payment:' || v_row."id"::text || ':' || trim(record_rent_payment.reference) end;
  select x."id" into v_tx from "better_supabase"."ledger_transactions" x
    where x."org_id" = v_row."org_id" and x."idempotency_key" = v_key;
  if v_tx is null then
    v_tx := "better_supabase"."ledger_post"(v_row."org_id", 'lease.payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_receivable', 'leases.rent:' || v_row."id"::text, 'Rent ' || v_row."title",
      v_row."currency"::text, 0::smallint, 'lease', v_row."id"::text, null, true, 'leases.read', 'leases',
      jsonb_build_object('leaseId', v_row."id")), 'amount', -record_rent_payment.amount),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."org_id", 'rent_cash', 'leases.cash:' || v_row."currency", 'Rent received ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null, null, true, 'leases.read', 'leases', null), 'amount', record_rent_payment.amount)),
      'leases', v_row."id"::text, 'Rent payment', v_key, record_rent_payment.paid_at,
      jsonb_strip_nulls(jsonb_build_object('leaseId', v_row."id", 'reference', nullif(trim(record_rent_payment.reference), ''))));
    
    null;
  end if;
  return jsonb_build_object('transactionId', v_tx, 'leaseId', v_row."id", 'amount', record_rent_payment.amount::text,
    'currency', v_row."currency", 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."org_id" = v_row."org_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text);
end;
$$;
revoke execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) from public, anon;
grant execute on function "better_supabase"."record_rent_payment"(uuid, bigint, timestamptz, text) to authenticated, service_role;

create or replace function "better_supabase"."list_lease_charges"(lease_id uuid, page_size integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leases"%rowtype;
begin
  select * into v_row from "better_supabase"."leases" x where x."id" = list_lease_charges.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'leaseId', q."lease_id", 'periodStart', q."period_start", 'periodEnd', q."period_end", 'amount', q."amount"::text, 'currency', q."currency", 'transactionId', q."transaction_id", 'createdAt', q."created_at") order by q."period_start" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."lease_charges" y where y."lease_id" = v_row."id"
      order by y."period_start" desc
      limit least(greatest(coalesce(list_lease_charges.page_size, 200), 1), 2000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_lease_charges"(uuid, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."leases" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."leases" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."leases" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."leases" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."lease_charges" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('leases.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."lease_charges" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."lease_charges" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."lease_charges" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_120_leases.sql
-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:916537b0ac15a44d934f0953f1905d46b0489cbc62ee42af0d92f389f7ae4b1d
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
