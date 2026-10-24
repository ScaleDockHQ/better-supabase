-- better-supabase module: leases
-- @bsb-block leases@2 managed
-- @bsb-hash sha256:8bb8c33b7302b617d763718d95786d068de492b47e48e52db1d19a7de22a65eb
-- Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals and terminations. Maintenance requests are a tasks instance on the unit.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."lease_agreements";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."lease_charges";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, and deposits held through ledger holds.

create table if not exists "better_supabase"."lease_agreements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "unit_id" uuid not null references "better_supabase"."assets" ("id") on delete restrict,
  -- The party renting the unit: a registered subject such as a contact.
  "party_type" text not null,
  "party_id" text not null,
  "title" text not null check (length("title") between 1 and 200),
  "status" text not null default 'draft' check ("status" in ('draft', 'active', 'ended', 'terminated')),
  "starts_on" date not null,
  -- Null runs the lease until it is terminated.
  "ends_on" date,
  -- Minor units of currency per period (ADR 0037).
  "rent" bigint not null check ("rent" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "frequency" text not null default 'monthly' check ("frequency" in ('weekly', 'monthly', 'quarterly', 'yearly')),
  "deposit" bigint not null default 0 check ("deposit" >= 0),
  -- The ledger hold that keeps the deposit aside while the lease runs.
  "deposit_hold_id" uuid,
  "renewed_at" timestamptz,
  "terminated_on" date,
  "termination_reason" text check ("termination_reason" is null or length("termination_reason") <= 2000),
  "metadata" jsonb not null default '{}'::jsonb,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" > "starts_on")
);
create index if not exists "lease_agreements_tenant_idx" on "better_supabase"."lease_agreements" ("tenant_id", "status", "starts_on" desc);
create index if not exists "lease_agreements_unit_idx" on "better_supabase"."lease_agreements" ("unit_id");
create index if not exists "lease_agreements_party_idx" on "better_supabase"."lease_agreements" ("tenant_id", "party_type", "party_id");
create index if not exists "lease_agreements_deposit_hold_idx" on "better_supabase"."lease_agreements" ("deposit_hold_id") where "deposit_hold_id" is not null;
alter table "better_supabase"."lease_agreements" enable row level security;
revoke all on "better_supabase"."lease_agreements" from anon, authenticated;
grant select on "better_supabase"."lease_agreements" to authenticated;
grant all on "better_supabase"."lease_agreements" to service_role;
drop policy if exists "lease_agreements_read" on "better_supabase"."lease_agreements";
create policy "lease_agreements_read" on "better_supabase"."lease_agreements" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));

-- One row per rent period posted to the ledger, so each period posts once.
create table if not exists "better_supabase"."lease_charges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "lease_id" uuid not null references "better_supabase"."lease_agreements" ("id") on delete restrict,
  "period_start" date not null,
  "period_end" date not null,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null,
  "transaction_id" uuid not null,
  "created_at" timestamptz not null default now(),
  unique ("lease_id", "period_start"),
  check ("period_end" > "period_start")
);
create index if not exists "lease_charges_tenant_idx" on "better_supabase"."lease_charges" ("tenant_id", "period_start" desc);
create index if not exists "lease_charges_transaction_idx" on "better_supabase"."lease_charges" ("transaction_id");
alter table "better_supabase"."lease_charges" enable row level security;
revoke all on "better_supabase"."lease_charges" from anon, authenticated;
grant select on "better_supabase"."lease_charges" to authenticated;
grant all on "better_supabase"."lease_charges" to service_role;
drop policy if exists "lease_charges_read" on "better_supabase"."lease_charges";
create policy "lease_charges_read" on "better_supabase"."lease_charges" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')));


-- Creates a draft lease of a unit (an asset) to a party (a registered
-- subject). Rent is minor units of currency per period of frequency.
-- fields: the extra columns to set.
drop function if exists "better_supabase"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb, jsonb);
create or replace function "better_supabase"."create_lease"(tenant uuid, unit_id uuid, party_type text, party_id text, starts_on date, rent bigint, currency text, frequency text default 'monthly', ends_on date default null, deposit bigint default 0, title text default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."lease_agreements"%rowtype;
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
    or not (case create_lease.party_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_lease.party_id)::uuid and s."organization_id"::text = create_lease.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_lease.party_id)::uuid and s."tenant_id"::text = create_lease.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_lease.party_id)::uuid and s."organization_id"::text = create_lease.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_lease.party_id)::uuid and s."organization_id"::text = create_lease.tenant::text)
      else false
    end and "better_supabase"."can_subject"(create_lease.party_type, create_lease.party_id, 'read')) then
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
  insert into "better_supabase"."lease_agreements" ("tenant_id", "unit_id", "party_type", "party_id", "title", "starts_on", "ends_on",
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
  v_row "better_supabase"."lease_agreements"%rowtype;
  v_account uuid;
  v_hold "better_supabase"."ledger_holds"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lease_agreements" x where x."id" = activate_lease.lease_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.manage'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft lease can be activated' using errcode = '55000', hint = 'LEASE_STATUS_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leases.unit:' || v_row."unit_id"::text, 0));
  if exists (
    select 1 from "better_supabase"."lease_agreements" x
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
  update "better_supabase"."lease_agreements" x set "status" = 'active', "deposit_hold_id" = v_hold."id", "updated_at" = now()
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
  v_row "better_supabase"."lease_agreements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lease_agreements" x where x."id" = renew_lease.lease_id for update;
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
  update "better_supabase"."lease_agreements" x set "ends_on" = renew_lease.ends_on, "rent" = coalesce(renew_lease.rent, x."rent"),
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
  v_row "better_supabase"."lease_agreements"%rowtype;
  v_on date := coalesce(terminate_lease.terminates_on, current_date);
  v_deduction bigint := coalesce(terminate_lease.deposit_deduction, 0);
  v_held bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."lease_agreements" x where x."id" = terminate_lease.lease_id for update;
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
  update "better_supabase"."lease_agreements" x set
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
  v_row "better_supabase"."lease_agreements"%rowtype;
begin
  select * into v_row from "better_supabase"."lease_agreements" x where x."id" = get_lease.lease_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)) then
    raise exception 'no such lease you can read' using errcode = 'P0002', hint = 'LEASE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'unitId', v_row."unit_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'title', v_row."title", 'status', v_row."status", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'rent', v_row."rent"::text, 'currency', v_row."currency", 'frequency', v_row."frequency", 'deposit', v_row."deposit"::text, 'depositHoldId', v_row."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = v_row."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = v_row."tenant_id" and x."code" = 'leases.rent:' || v_row."id"::text), 0)::text, 'renewedAt', v_row."renewed_at", 'terminatedOn', v_row."terminated_on", 'terminationReason', v_row."termination_reason", 'metadata', v_row."metadata", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."get_lease"(uuid) from public, anon;
grant execute on function "better_supabase"."get_lease"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_leases"(tenant uuid, status text default null, unit_id uuid default null, party_type text default null, party_id text default null, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leases.tenant, 'leases.read'), false)) then
    raise exception 'not allowed to read leases' using errcode = '42501', hint = 'LEASES_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'unitId', q."unit_id", 'partyType', q."party_type", 'partyId', q."party_id", 'title', q."title", 'status', q."status", 'startsOn', q."starts_on", 'endsOn', q."ends_on", 'rent', q."rent"::text, 'currency', q."currency", 'frequency', q."frequency", 'deposit', q."deposit"::text, 'depositHoldId', q."deposit_hold_id", 'depositHeld', coalesce((select h."amount" from "better_supabase"."ledger_holds" h where h."id" = q."deposit_hold_id" and h."status" = 'active'), 0)::text, 'balanceDue', coalesce((select y."balance" from "better_supabase"."ledger_accounts" x join "better_supabase"."ledger_balances" y on y."account_id" = x."id"
      where x."tenant_id" = q."tenant_id" and x."code" = 'leases.rent:' || q."id"::text), 0)::text, 'renewedAt', q."renewed_at", 'terminatedOn', q."terminated_on", 'terminationReason', q."termination_reason", 'metadata', q."metadata", 'createdBy', q."created_by", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."starts_on" desc, q."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."lease_agreements" x
      where x."tenant_id" = list_leases.tenant
        and (list_leases.status is null or x."status" = list_leases.status)
        and (list_leases.unit_id is null or x."unit_id" = list_leases.unit_id)
        and (list_leases.party_type is null or (x."party_type" = list_leases.party_type and x."party_id" = list_leases.party_id))
      order by x."starts_on" desc, x."id"
      limit least(greatest(coalesce(list_leases.page_size, 100), 1), 1000)
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_leases"(uuid, text, uuid, text, text, integer) from public, anon;
grant execute on function "better_supabase"."list_leases"(uuid, text, uuid, text, text, integer) to authenticated, service_role;

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
  v_row "better_supabase"."lease_agreements"%rowtype;
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
    select * from "better_supabase"."lease_agreements" x
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
  v_row "better_supabase"."lease_agreements"%rowtype;
  v_key text;
  v_tx uuid;
begin
  select * into v_row from "better_supabase"."lease_agreements" x where x."id" = record_rent_payment.lease_id;
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
  v_row "better_supabase"."lease_agreements"%rowtype;
begin
  select * into v_row from "better_supabase"."lease_agreements" x where x."id" = list_lease_charges.lease_id;
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

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."leases_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.forms' then array['form'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."lease_agreements" x set "party_id" = v_keep where x."party_type" = v_type and x."party_id" = v_drop;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."leases_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."leases_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."lease_agreements";
create policy bsb_tenant_scope on "better_supabase"."lease_agreements" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."lease_charges";
create policy bsb_tenant_scope on "better_supabase"."lease_charges" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('leases.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.leases.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_lease"(uuid, uuid, text, text, date, bigint, text, text, date, bigint, text, jsonb, jsonb);

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
security invoker
set search_path = ''
as $$ select "better_supabase"."get_lease"($1) $$;
revoke execute on function "api"."get_lease"(uuid) from public, anon;
grant execute on function "api"."get_lease"(uuid) to authenticated, service_role;

create or replace function "api"."list_leases"(tenant uuid, status text default null, unit_id uuid default null, party_type text default null, party_id text default null, page_size integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_leases"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."list_leases"(uuid, text, uuid, text, text, integer) from public, anon;
grant execute on function "api"."list_leases"(uuid, text, uuid, text, text, integer) to authenticated, service_role;

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
security invoker
set search_path = ''
as $$ select "better_supabase"."list_lease_charges"($1, $2) $$;
revoke execute on function "api"."list_lease_charges"(uuid, integer) from public, anon;
grant execute on function "api"."list_lease_charges"(uuid, integer) to authenticated, service_role;

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
