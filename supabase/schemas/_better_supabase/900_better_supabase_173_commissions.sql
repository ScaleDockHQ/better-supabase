-- better-supabase module: commissions
-- @bsb-block commissions@1 managed
-- @bsb-hash sha256:9cdd4029393742f5559b3016f7f61321a3744acd515e2da409141e00be3b61e3
-- Commission plans (flat or marginal tiers) assigned to sellers, commissions accrued on the ledger from paid records, statements per period with a payout, and the lines payroll adds.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Commission plans (flat rate or marginal tiers), their assignments to sellers,
-- the commissions accrued from paid records and the statements that collect
-- a seller's commissions per period. Amounts are bigint minor units.
create table "better_supabase"."commission_plans" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_commission_plans_name_check check (length("name") >= 1 and length("name") <= 200),
  "kind" text not null constraint bsb_commission_plans_kind_check check ("kind" in ('flat', 'tiered')),
  -- A flat plan's rate in basis points (100 is 1%).
  "rate_bps" integer constraint bsb_commission_plans_rate_bps_check check ("rate_bps" >= 0 and "rate_bps" <= 10000),
  -- A tiered plan's marginal tiers: [{ "upTo": 100000, "bps": 500 }, { "upTo": null, "bps": 800 }].
  "tiers" jsonb constraint bsb_commission_plans_tiers_check check ("tiers" is null or jsonb_typeof("tiers") = 'array'),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  constraint bsb_commission_plans_check check (("kind" = 'flat' and "rate_bps" is not null and "tiers" is null)
    or ("kind" = 'tiered' and "rate_bps" is null and "tiers" is not null))
);
create index "commission_plans_tenant_idx" on "better_supabase"."commission_plans" ("tenant_id", "created_at" desc, "id" desc);
alter table "better_supabase"."commission_plans" enable row level security;
revoke all on "better_supabase"."commission_plans" from public, anon, authenticated;
grant select on "better_supabase"."commission_plans" to authenticated;
grant all on "better_supabase"."commission_plans" to service_role;
create policy bsb_commission_plans_read on "better_supabase"."commission_plans"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')));

create table "better_supabase"."commission_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan_id" uuid not null,
  "seller_id" uuid not null,
  -- A plan for one record, such as a customer, over the seller's own plan.
  "subject_type" text,
  "subject_id" text,
  "starts_on" date not null default current_date,
  "ends_on" date,
  "created_at" timestamptz not null default now(),
  constraint bsb_commission_assignments_check check (("subject_type" is null) = ("subject_id" is null)),
  constraint bsb_commission_assignments_check1 check ("ends_on" is null or "ends_on" >= "starts_on"),
  foreign key ("tenant_id", "plan_id") references "better_supabase"."commission_plans" ("tenant_id", "id") on delete cascade
);
create index "commission_assignments_plan_idx" on "better_supabase"."commission_assignments" ("tenant_id", "plan_id");
create index "commission_assignments_seller_idx" on "better_supabase"."commission_assignments" ("tenant_id", "seller_id", "starts_on" desc);
alter table "better_supabase"."commission_assignments" enable row level security;
revoke all on "better_supabase"."commission_assignments" from public, anon, authenticated;
grant select on "better_supabase"."commission_assignments" to authenticated;
grant all on "better_supabase"."commission_assignments" to service_role;
create policy bsb_commission_assignments_read on "better_supabase"."commission_assignments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')) or "seller_id" = (select auth.uid()));

create table "better_supabase"."commission_statements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "seller_id" uuid not null,
  "currency" text not null constraint bsb_commission_statements_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "starts_on" date not null,
  "ends_on" date not null,
  "status" text not null default 'open' constraint bsb_commission_statements_status_check check ("status" in ('open', 'finalized', 'paid')),
  "total" bigint not null default 0,
  -- The ledger transaction that paid the statement out.
  "ledger_transaction_id" uuid,
  "finalized_at" timestamptz,
  "paid_at" timestamptz,
  "paid_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_commission_statements_check check ("ends_on" >= "starts_on"),
  unique ("tenant_id", "id"),
  unique ("tenant_id", "seller_id", "currency", "starts_on")
);
create index "commission_statements_range_idx" on "better_supabase"."commission_statements" ("tenant_id", "ends_on", "status");
alter table "better_supabase"."commission_statements" enable row level security;
revoke all on "better_supabase"."commission_statements" from public, anon, authenticated;
grant select on "better_supabase"."commission_statements" to authenticated;
grant all on "better_supabase"."commission_statements" to service_role;
create policy bsb_commission_statements_read on "better_supabase"."commission_statements"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')) or "seller_id" = (select auth.uid()));

create table "better_supabase"."commissions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan_id" uuid not null,
  "seller_id" uuid not null,
  -- The record the commission was earned on, such as invoices and its id.
  "source_type" text not null constraint bsb_commissions_source_type_check check (length("source_type") >= 1 and length("source_type") <= 100),
  "source_id" text not null constraint bsb_commissions_source_id_check check (length("source_id") >= 1 and length("source_id") <= 200),
  -- What the percentage was taken of, and what it came to, in minor units.
  "basis" bigint not null constraint bsb_commissions_basis_check check ("basis" > 0),
  "amount" bigint not null constraint bsb_commissions_amount_check check ("amount" > 0),
  "currency" text not null constraint bsb_commissions_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "occurred_on" date not null,
  "status" text not null default 'accrued' constraint bsb_commissions_status_check check ("status" in ('accrued', 'reversed')),
  "statement_id" uuid,
  "ledger_transaction_id" uuid,
  "reversed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "source_type", "source_id", "seller_id"),
  foreign key ("tenant_id", "plan_id") references "better_supabase"."commission_plans" ("tenant_id", "id"),
  foreign key ("tenant_id", "statement_id") references "better_supabase"."commission_statements" ("tenant_id", "id")
);
create index "commissions_seller_idx" on "better_supabase"."commissions" ("tenant_id", "seller_id", "currency", "occurred_on");
create index "commissions_statement_idx" on "better_supabase"."commissions" ("tenant_id", "statement_id");
create index "commissions_plan_idx" on "better_supabase"."commissions" ("tenant_id", "plan_id");
alter table "better_supabase"."commissions" enable row level security;
revoke all on "better_supabase"."commissions" from public, anon, authenticated;
grant select on "better_supabase"."commissions" to authenticated;
grant all on "better_supabase"."commissions" to service_role;
create policy bsb_commissions_read on "better_supabase"."commissions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')) or "seller_id" = (select auth.uid()));

-- A commission as a bigint of minor units. A flat plan takes rate_bps of the
-- basis. A tiered plan takes each tier's bps of the part of the seller's
-- cumulative basis inside the tier, so prior is what the seller sold earlier
-- in the same month. The tiers are marginal and the last one has no upTo.
create or replace function "better_supabase"."commission_amount"(kind text, rate_bps integer, tiers jsonb, prior bigint, basis bigint)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tier jsonb;
  v_lower numeric := 0;
  v_upper numeric;
  v_before numeric := 0;
  v_after numeric := 0;
begin
  if commission_amount.kind = 'flat' then
    return round(commission_amount.basis * commission_amount.rate_bps / 10000.0)::bigint;
  end if;
  for v_tier in
    select t.value from jsonb_array_elements(commission_amount.tiers) with ordinality as t(value, n) order by t.n
  loop
    v_upper := (v_tier ->> 'upTo')::numeric;
    v_before := v_before + greatest(0, least(coalesce(v_upper, commission_amount.prior), commission_amount.prior) - v_lower) * (v_tier ->> 'bps')::numeric / 10000.0;
    v_after := v_after + greatest(0, least(coalesce(v_upper, commission_amount.prior + commission_amount.basis), commission_amount.prior + commission_amount.basis) - v_lower) * (v_tier ->> 'bps')::numeric / 10000.0;
    exit when v_upper is null;
    v_lower := v_upper;
  end loop;
  return round(v_after)::bigint - round(v_before)::bigint;
end;
$$;
revoke execute on function "better_supabase"."commission_amount"(text, integer, jsonb, bigint, bigint) from public, anon, authenticated;
grant execute on function "better_supabase"."commission_amount"(text, integer, jsonb, bigint, bigint) to service_role;

-- Whether tiers is a list of { upTo, bps } with rising upTo values and one
-- last tier without upTo.
create or replace function "better_supabase"."commission_tiers_valid"(tiers jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_tier jsonb;
  v_last numeric := 0;
  v_count integer;
  v_n integer := 0;
begin
  if jsonb_typeof(commission_tiers_valid.tiers) is distinct from 'array' then
    return false;
  end if;
  v_count := jsonb_array_length(commission_tiers_valid.tiers);
  if v_count = 0 or v_count > 50 then
    return false;
  end if;
  for v_tier in select t.value from jsonb_array_elements(commission_tiers_valid.tiers) with ordinality as t(value, n) order by t.n loop
    v_n := v_n + 1;
    if jsonb_typeof(v_tier) is distinct from 'object'
      or coalesce(v_tier ->> 'bps', '') !~ '^[0-9]{1,5}$' or (v_tier ->> 'bps')::integer > 10000 then
      return false;
    end if;
    if v_tier ->> 'upTo' is null then
      return v_n = v_count;
    end if;
    if v_tier ->> 'upTo' !~ '^[0-9]{1,18}$' or (v_tier ->> 'upTo')::numeric <= v_last then
      return false;
    end if;
    v_last := (v_tier ->> 'upTo')::numeric;
  end loop;
  return false;
end;
$$;
revoke execute on function "better_supabase"."commission_tiers_valid"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."commission_tiers_valid"(jsonb) to service_role;

-- Creates a plan, or changes the one with plan_id. A flat plan sets rate_bps, a
-- tiered plan sets tiers. archived hides a plan from new assignments. Needs
-- commissions.manage.
create or replace function "better_supabase"."save_commission_plan"(tenant uuid, name text, kind text, rate_bps integer default null, tiers jsonb default null, plan_id uuid default null, archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan "better_supabase"."commission_plans";
  v_created boolean := save_commission_plan.plan_id is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_commission_plan.tenant is not null and coalesce(better_supabase.can('tenant', save_commission_plan.tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to manage commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if nullif(trim(save_commission_plan.name), '') is null or length(trim(save_commission_plan.name)) > 200 then
    raise exception 'a plan needs a name of at most 200 characters' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if save_commission_plan.kind = 'flat' then
    if save_commission_plan.rate_bps is null or save_commission_plan.rate_bps not between 0 and 10000 or save_commission_plan.tiers is not null then
      raise exception 'a flat plan takes rate_bps from 0 to 10000 and no tiers' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
  elsif save_commission_plan.kind = 'tiered' then
    if save_commission_plan.rate_bps is not null or not "better_supabase"."commission_tiers_valid"(save_commission_plan.tiers) then
      raise exception 'a tiered plan takes rising { upTo, bps } tiers with a last tier that has no upTo' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
  else
    raise exception 'a plan is flat or tiered' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_created then
    insert into "better_supabase"."commission_plans" ("tenant_id", "name", "kind", "rate_bps", "tiers", "archived_at")
    values (save_commission_plan.tenant, trim(save_commission_plan.name), save_commission_plan.kind, save_commission_plan.rate_bps, save_commission_plan.tiers,
      case when save_commission_plan.archived then now() end)
    returning * into v_plan;
    perform "better_supabase".emit_event('commission_plan.created', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind"), 'commission-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_plan.created',
    category => 'billing',
    target_type => 'commission_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."name",
    summary => 'created a commission plan',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind")
  );
  else
    update "better_supabase"."commission_plans" x set "name" = trim(save_commission_plan.name), "kind" = save_commission_plan.kind,
      "rate_bps" = save_commission_plan.rate_bps, "tiers" = save_commission_plan.tiers,
      "archived_at" = case when save_commission_plan.archived then coalesce(x."archived_at", now()) end,
      "updated_at" = now()
    where x."id" = save_commission_plan.plan_id and x."tenant_id" = save_commission_plan.tenant
    returning * into v_plan;
    if not found then
      raise exception 'no such commission plan' using errcode = 'P0002', hint = 'COMMISSION_PLAN_NOT_FOUND';
    end if;
    perform "better_supabase".emit_event('commission_plan.updated', jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind"), 'commission-plans/' || v_plan."id"::text, (v_plan."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_plan.updated',
    category => 'billing',
    target_type => 'commission_plan',
    record_id => v_plan."id"::text,
    target_label => v_plan."name",
    summary => 'updated a commission plan',
    tenant => (v_plan."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_plan."tenant_id", 'id', v_plan."id", 'name', v_plan."name", 'kind', v_plan."kind")
  );
  end if;
  return jsonb_build_object('id', v_plan."id", 'organizationId', v_plan."tenant_id", 'name', v_plan."name", 'kind', v_plan."kind", 'rateBps', v_plan."rate_bps", 'tiers', v_plan."tiers", 'archivedAt', v_plan."archived_at", 'createdAt', v_plan."created_at", 'updatedAt', v_plan."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) to authenticated, service_role;

-- Puts a seller on a plan from starts_on until ends_on. With a subject the
-- plan applies to sales on that record only, and wins over the seller's own
-- plan. Needs commissions.manage.
create or replace function "better_supabase"."assign_commission_plan"(tenant uuid, plan_id uuid, seller_id uuid, subject_type text default null, subject_id text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."commission_assignments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (assign_commission_plan.tenant is not null and coalesce(better_supabase.can('tenant', assign_commission_plan.tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to assign commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if assign_commission_plan.seller_id is null or (assign_commission_plan.subject_type is null) <> (assign_commission_plan.subject_id is null)
    or (assign_commission_plan.ends_on is not null and assign_commission_plan.ends_on < coalesce(assign_commission_plan.starts_on, current_date)) then
    raise exception 'an assignment needs a seller, a subject with both parts and a range that ends after it starts' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."commission_plans" x
    where x."id" = assign_commission_plan.plan_id and x."tenant_id" = assign_commission_plan.tenant and x."archived_at" is null
  ) then
    raise exception 'no such open commission plan' using errcode = 'P0002', hint = 'COMMISSION_PLAN_NOT_FOUND';
  end if;
  insert into "better_supabase"."commission_assignments" ("tenant_id", "plan_id", "seller_id", "subject_type", "subject_id", "starts_on", "ends_on")
  values (assign_commission_plan.tenant, assign_commission_plan.plan_id, assign_commission_plan.seller_id, assign_commission_plan.subject_type,
    assign_commission_plan.subject_id, coalesce(assign_commission_plan.starts_on, current_date), assign_commission_plan.ends_on)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'planId', v_row."plan_id", 'sellerId', v_row."seller_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) from public, anon;
grant execute on function "better_supabase"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) to authenticated, service_role;

-- Ends an assignment today. Needs commissions.manage.
create or replace function "better_supabase"."end_commission_assignment"(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."commission_assignments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."commission_assignments" x where x."id" = end_commission_assignment.assignment_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'commissions.read'), false))) then
    raise exception 'no such assignment' using errcode = 'P0002', hint = 'COMMISSION_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'commissions.manage'), false))) then
    raise exception 'not allowed to assign commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  update "better_supabase"."commission_assignments" x set "ends_on" = greatest(current_date, x."starts_on")
  where x."id" = v_row."id" and (x."ends_on" is null or x."ends_on" > current_date)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'planId', v_row."plan_id", 'sellerId', v_row."seller_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."end_commission_assignment"(uuid) from public, anon;
grant execute on function "better_supabase"."end_commission_assignment"(uuid) to authenticated, service_role;

-- The plan that applies to a seller on a date: the one assigned for the
-- subject, else the seller's own. Null when the seller has none.
create or replace function "better_supabase"."commission_plan_for"(tenant uuid, seller_id uuid, subject_type text, subject_id text, on_date date)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x."plan_id" from "better_supabase"."commission_assignments" x
  join "better_supabase"."commission_plans" y on y."id" = x."plan_id" and y."archived_at" is null
  where x."tenant_id" = commission_plan_for.tenant and x."seller_id" = commission_plan_for.seller_id
    and x."starts_on" <= commission_plan_for.on_date and (x."ends_on" is null or x."ends_on" >= commission_plan_for.on_date)
    and (x."subject_type" is null or (x."subject_type" = commission_plan_for.subject_type and x."subject_id" = commission_plan_for.subject_id))
  order by (x."subject_type" is not null) desc, x."starts_on" desc, x."created_at" desc
  limit 1
$$;
revoke execute on function "better_supabase"."commission_plan_for"(uuid, uuid, text, text, date) from public, anon, authenticated;
grant execute on function "better_supabase"."commission_plan_for"(uuid, uuid, text, text, date) to service_role;

-- Accrues a commission without checking the caller: the invoice trigger and
-- accrue_commission call it. It returns the earlier commission of the same
-- seller on the same record, or null when the seller has no plan or the
-- commission rounds to nothing. The ledger moves the amount from the
-- commission expense account to the seller's payable account.
create or replace function "better_supabase"."commission_accrue"(tenant uuid, seller_id uuid, source_type text, source_id text, basis bigint, currency text, occurred_on date default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_entry "better_supabase"."commissions";
  v_plan "better_supabase"."commission_plans";
  v_on date := coalesce(commission_accrue.occurred_on, current_date);
  v_currency text := upper(commission_accrue.currency);
  v_prior bigint;
  v_amount bigint;
  v_tx uuid;
begin
  if commission_accrue.seller_id is null or nullif(trim(commission_accrue.source_type), '') is null
    or nullif(trim(commission_accrue.source_id), '') is null or coalesce(commission_accrue.basis, 0) <= 0
    or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'a commission needs a seller, a source, a positive basis and a currency code' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(commission_accrue.tenant::text || commission_accrue.seller_id::text, 0));
  select * into v_entry from "better_supabase"."commissions" x
  where x."tenant_id" = commission_accrue.tenant and x."source_type" = commission_accrue.source_type
    and x."source_id" = commission_accrue.source_id and x."seller_id" = commission_accrue.seller_id;
  if found then
    return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
  end if;
  select y.* into v_plan from "better_supabase"."commission_plans" y
  where y."id" = "better_supabase"."commission_plan_for"(commission_accrue.tenant, commission_accrue.seller_id, commission_accrue.subject_type, commission_accrue.subject_id, v_on);
  if not found then
    return null;
  end if;
  select coalesce(sum(x."basis"), 0) into v_prior from "better_supabase"."commissions" x
  where x."tenant_id" = commission_accrue.tenant and x."seller_id" = commission_accrue.seller_id
    and x."plan_id" = v_plan."id" and x."currency" = v_currency and x."status" = 'accrued'
    and date_trunc('month', x."occurred_on"::timestamp) = date_trunc('month', v_on::timestamp);
  v_amount := "better_supabase"."commission_amount"(v_plan."kind", v_plan."rate_bps", v_plan."tiers", v_prior, commission_accrue.basis);
  if v_amount <= 0 then
    return null;
  end if;
  v_tx := "better_supabase"."ledger_post"(commission_accrue.tenant, 'commission.accrual',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(commission_accrue.tenant, 'expense', 'commissions:expense:' || v_currency::text, 'Commissions', v_currency::text, 0::smallint, null, null, null, true, 'commissions.read', 'commissions', null), 'amount', (-v_amount)::text),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(commission_accrue.tenant, 'payable', 'commissions:payable:' || commission_accrue.seller_id::text || ':' || v_currency::text, 'Commissions payable', v_currency::text, 0::smallint, null, null, commission_accrue.seller_id, true, 'commissions.read', 'commissions', null), 'amount', v_amount::text)),
    'commissions', commission_accrue.source_type || '/' || commission_accrue.source_id, null,
    'commission:' || commission_accrue.source_type || ':' || commission_accrue.source_id || ':' || commission_accrue.seller_id::text,
    v_on::timestamptz,
    jsonb_build_object('sellerId', commission_accrue.seller_id, 'planId', v_plan."id"));
  insert into "better_supabase"."commissions" ("tenant_id", "plan_id", "seller_id", "source_type", "source_id", "basis", "amount", "currency", "occurred_on", "ledger_transaction_id")
  values (commission_accrue.tenant, v_plan."id", commission_accrue.seller_id, commission_accrue.source_type, commission_accrue.source_id,
    commission_accrue.basis, v_amount, v_currency, v_on, v_tx)
  returning * into v_entry;
  perform "better_supabase".emit_event('commission.accrued', jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency"), 'commissions/' || v_entry."id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission.accrued',
    category => 'billing',
    target_type => 'commission',
    record_id => v_entry."id"::text,
    summary => 'accrued a commission',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency")
  );
  return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
end;
$$;
revoke execute on function "better_supabase"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) to service_role;

-- Accrues a commission for a seller on a record the app sold, such as an order
-- or a payment the invoice trigger does not see. basis is the amount in minor
-- units the plan takes its percentage of. Calling it again for the same seller
-- and record returns the first commission. Needs commissions.write.
create or replace function "better_supabase"."accrue_commission"(tenant uuid, seller_id uuid, source_type text, source_id text, basis bigint, currency text, occurred_on date default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (accrue_commission.tenant is not null and coalesce(better_supabase.can('tenant', accrue_commission.tenant, 'commissions.write'), false))) then
    raise exception 'not allowed to accrue commissions' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  return "better_supabase"."commission_accrue"(accrue_commission.tenant, accrue_commission.seller_id, accrue_commission.source_type, accrue_commission.source_id,
    accrue_commission.basis, accrue_commission.currency, accrue_commission.occurred_on, accrue_commission.subject_type, accrue_commission.subject_id);
end;
$$;
revoke execute on function "better_supabase"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) from public, anon;
grant execute on function "better_supabase"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) to authenticated, service_role;

-- Reverses an accrued commission, for example after a refund. The ledger gets
-- the opposite transaction. A commission on a finalized or paid statement
-- can't be reversed. Needs commissions.manage.
create or replace function "better_supabase"."reverse_commission"(commission_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_entry "better_supabase"."commissions";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_entry from "better_supabase"."commissions" x where x."id" = reverse_commission.commission_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_entry."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_entry."tenant_id", 'commissions.read'), false))) then
    raise exception 'no such commission' using errcode = 'P0002', hint = 'COMMISSION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_entry."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_entry."tenant_id", 'commissions.manage'), false))) then
    raise exception 'not allowed to reverse commissions' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if v_entry."status" = 'reversed' then
    return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
  end if;
  if v_entry."statement_id" is not null then
    select y."status" into v_status from "better_supabase"."commission_statements" y where y."id" = v_entry."statement_id";
    if v_status <> 'open' then
      raise exception 'the commission is on a statement that is no longer open' using errcode = '55000', hint = 'COMMISSION_STATEMENT_LOCKED';
    end if;
  end if;
  perform "better_supabase"."ledger_post"(v_entry."tenant_id", 'commission.reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = v_entry."ledger_transaction_id"),
    'commissions', v_entry."source_type" || '/' || v_entry."source_id", nullif(trim(reverse_commission.reason), ''),
    'commission-reversal:' || v_entry."id"::text, null,
    jsonb_build_object('reversal', true, 'reason', nullif(trim(reverse_commission.reason), '')),
    v_entry."ledger_transaction_id");
  update "better_supabase"."commissions" x set "status" = 'reversed', "reversed_at" = now()
  where x."id" = v_entry."id" returning * into v_entry;
  if v_entry."statement_id" is not null then
    update "better_supabase"."commission_statements" y set "total" = coalesce((select sum(x."amount") from "better_supabase"."commissions" x where x."statement_id" = y."id" and x."status" = 'accrued'), 0)
    where y."id" = v_entry."statement_id";
  end if;
  perform "better_supabase".emit_event('commission.reversed', jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency"), 'commissions/' || v_entry."id"::text, (v_entry."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission.reversed',
    category => 'billing',
    target_type => 'commission',
    record_id => v_entry."id"::text,
    summary => 'reversed a commission',
    tenant => (v_entry."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_entry."tenant_id", 'id', v_entry."id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'amount', v_entry."amount"::text, 'currency', v_entry."currency")
  );
  return jsonb_build_object('id', v_entry."id", 'organizationId', v_entry."tenant_id", 'planId', v_entry."plan_id", 'sellerId', v_entry."seller_id", 'sourceType', v_entry."source_type", 'sourceId', v_entry."source_id", 'basis', v_entry."basis"::text, 'amount', v_entry."amount"::text, 'currency', v_entry."currency", 'occurredOn', v_entry."occurred_on", 'status', v_entry."status", 'statementId', v_entry."statement_id", 'ledgerTransactionId', v_entry."ledger_transaction_id", 'reversedAt', v_entry."reversed_at", 'createdAt', v_entry."created_at");
end;
$$;
revoke execute on function "better_supabase"."reverse_commission"(uuid, text) from public, anon;
grant execute on function "better_supabase"."reverse_commission"(uuid, text) to authenticated, service_role;

-- Collects a seller's accrued commissions dated from starts_on to ends_on
-- that are on no statement into the open statement of that range, and
-- updates its total. Without checking the caller: build_commission_statement
-- and the period close call it.
create or replace function "better_supabase"."commission_statement_build"(tenant uuid, seller_id uuid, currency text, starts_on date, ends_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
begin
  select * into v_statement from "better_supabase"."commission_statements" x
  where x."tenant_id" = commission_statement_build.tenant and x."seller_id" = commission_statement_build.seller_id
    and x."currency" = commission_statement_build.currency and x."starts_on" = commission_statement_build.starts_on
  for update;
  if found and v_statement."status" <> 'open' then
    raise exception 'the statement of this range is no longer open' using errcode = '55000', hint = 'COMMISSION_STATEMENT_LOCKED';
  end if;
  if not found then
    insert into "better_supabase"."commission_statements" ("tenant_id", "seller_id", "currency", "starts_on", "ends_on")
    values (commission_statement_build.tenant, commission_statement_build.seller_id, commission_statement_build.currency,
      commission_statement_build.starts_on, commission_statement_build.ends_on)
    returning * into v_statement;
  end if;
  update "better_supabase"."commissions" x set "statement_id" = v_statement."id"
  where x."tenant_id" = commission_statement_build.tenant and x."seller_id" = commission_statement_build.seller_id
    and x."currency" = commission_statement_build.currency and x."status" = 'accrued' and x."statement_id" is null
    and x."occurred_on" between commission_statement_build.starts_on and commission_statement_build.ends_on;
  update "better_supabase"."commission_statements" x set "ends_on" = commission_statement_build.ends_on, "total" = coalesce((select sum(e."amount") from "better_supabase"."commissions" e where e."statement_id" = x."id" and e."status" = 'accrued'), 0)
  where x."id" = v_statement."id";
  return v_statement."id";
end;
$$;
revoke execute on function "better_supabase"."commission_statement_build"(uuid, uuid, text, date, date) from public, anon, authenticated;
grant execute on function "better_supabase"."commission_statement_build"(uuid, uuid, text, date, date) to service_role;

-- Builds the statement of one seller and currency for a date range. Calling
-- it again adds commissions accrued since, until the statement is finalized.
-- Needs commissions.manage.
create or replace function "better_supabase"."build_commission_statement"(tenant uuid, seller_id uuid, currency text, starts_on date, ends_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_statement "better_supabase"."commission_statements";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (build_commission_statement.tenant is not null and coalesce(better_supabase.can('tenant', build_commission_statement.tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to build commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if build_commission_statement.seller_id is null or upper(build_commission_statement.currency) !~ '^[A-Z]{3}$'
    or build_commission_statement.starts_on is null or build_commission_statement.ends_on is null
    or build_commission_statement.ends_on < build_commission_statement.starts_on then
    raise exception 'a statement needs a seller, a currency code and a range that ends on or after it starts' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  v_id := "better_supabase"."commission_statement_build"(build_commission_statement.tenant, build_commission_statement.seller_id,
    upper(build_commission_statement.currency), build_commission_statement.starts_on, build_commission_statement.ends_on);
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = v_id;
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
end;
$$;
revoke execute on function "better_supabase"."build_commission_statement"(uuid, uuid, text, date, date) from public, anon;
grant execute on function "better_supabase"."build_commission_statement"(uuid, uuid, text, date, date) to authenticated, service_role;

-- Locks a statement: its commissions can't be reversed afterwards. Without
-- checking the caller; finalize_commission_statement and the period close
-- call it.
create or replace function "better_supabase"."commission_statement_finalize"(statement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
begin
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = commission_statement_finalize.statement_id for update;
  if not found then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  if v_statement."status" <> 'open' then
    return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
  end if;
  update "better_supabase"."commission_statements" x set "status" = 'finalized', "finalized_at" = now(), "total" = coalesce((select sum(e."amount") from "better_supabase"."commissions" e where e."statement_id" = x."id" and e."status" = 'accrued'), 0)
  where x."id" = v_statement."id" returning * into v_statement;
  perform "better_supabase".emit_event('commission_statement.finalized', jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status"), 'commission-statements/' || v_statement."id"::text, (v_statement."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_statement.finalized',
    category => 'billing',
    target_type => 'commission_statement',
    record_id => v_statement."id"::text,
    summary => 'finalized a commission statement',
    tenant => (v_statement."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status")
  );
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
end;
$$;
revoke execute on function "better_supabase"."commission_statement_finalize"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."commission_statement_finalize"(uuid) to service_role;

-- Finalizes an open statement. Finalizing a finalized or paid statement
-- returns it unchanged. Needs commissions.manage.
create or replace function "better_supabase"."finalize_commission_statement"(statement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."commission_statements" x where x."id" = finalize_commission_statement.statement_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'commissions.read'), false))) then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'commissions.manage'), false))) then
    raise exception 'not allowed to finalize commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  return "better_supabase"."commission_statement_finalize"(finalize_commission_statement.statement_id);
end;
$$;
revoke execute on function "better_supabase"."finalize_commission_statement"(uuid) from public, anon;
grant execute on function "better_supabase"."finalize_commission_statement"(uuid) to authenticated, service_role;

-- Pays a finalized statement out: the ledger moves the total from the
-- seller's payable account to the commissions paid account. Paying a paid
-- statement returns it unchanged. Needs commissions.manage.
create or replace function "better_supabase"."pay_commission_statement"(statement_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
  v_tx uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = pay_commission_statement.statement_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_statement."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_statement."tenant_id", 'commissions.read'), false))) then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_statement."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_statement."tenant_id", 'commissions.manage'), false))) then
    raise exception 'not allowed to pay commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if v_statement."status" = 'paid' then
    return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
  end if;
  if v_statement."status" <> 'finalized' then
    raise exception 'finalize the statement before paying it' using errcode = '55000', hint = 'COMMISSION_STATEMENT_OPEN';
  end if;
  if v_statement."total" > 0 then
    v_tx := "better_supabase"."ledger_post"(v_statement."tenant_id", 'commission.payout',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_statement."tenant_id", 'payable', 'commissions:payable:' || v_statement."seller_id"::text || ':' || v_statement."currency"::text, 'Commissions payable', v_statement."currency"::text, 0::smallint, null, null, v_statement."seller_id", true, 'commissions.read', 'commissions', null), 'amount', (-v_statement."total")::text),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_statement."tenant_id", 'paid', 'commissions:paid:' || v_statement."currency"::text, 'Commissions paid', v_statement."currency"::text, 0::smallint, null, null, null, true, 'commissions.read', 'commissions', null), 'amount', v_statement."total"::text)),
      'commission-statements', v_statement."id"::text, null,
      'commission-statement:' || v_statement."id"::text, null,
      jsonb_build_object('sellerId', v_statement."seller_id"));
  end if;
  update "better_supabase"."commission_statements" x set "status" = 'paid', "paid_at" = now(), "paid_by" = auth.uid(), "ledger_transaction_id" = v_tx
  where x."id" = v_statement."id" returning * into v_statement;
  perform "better_supabase".emit_event('commission_statement.paid', jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status"), 'commission-statements/' || v_statement."id"::text, (v_statement."tenant_id")::text, null, 'better-supabase/commissions');
  perform better_supabase.audit_event(
    event_type => 'commission_statement.paid',
    category => 'billing',
    target_type => 'commission_statement',
    record_id => v_statement."id"::text,
    summary => 'paid a commission statement',
    tenant => (v_statement."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_statement."tenant_id", 'id', v_statement."id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'total', v_statement."total"::text, 'status', v_statement."status")
  );
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at");
end;
$$;
revoke execute on function "better_supabase"."pay_commission_statement"(uuid) from public, anon;
grant execute on function "better_supabase"."pay_commission_statement"(uuid) to authenticated, service_role;

-- A statement with its commissions. Needs commissions.read, or the seller's
-- own statement.
create or replace function "better_supabase"."get_commission_statement"(statement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_statement "better_supabase"."commission_statements";
begin
  select * into v_statement from "better_supabase"."commission_statements" x where x."id" = get_commission_statement.statement_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_statement."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_statement."tenant_id", 'commissions.read'), false))) or v_statement."seller_id" = (select auth.uid())) then
    raise exception 'no such commission statement' using errcode = 'P0002', hint = 'COMMISSION_STATEMENT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_statement."id", 'organizationId', v_statement."tenant_id", 'sellerId', v_statement."seller_id", 'currency', v_statement."currency", 'startsOn', v_statement."starts_on", 'endsOn', v_statement."ends_on", 'status', v_statement."status", 'total', v_statement."total"::text, 'ledgerTransactionId', v_statement."ledger_transaction_id", 'finalizedAt', v_statement."finalized_at", 'paidAt', v_statement."paid_at", 'paidBy', v_statement."paid_by", 'createdAt', v_statement."created_at") || jsonb_build_object('entries', coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'planId', y."plan_id", 'sellerId', y."seller_id", 'sourceType', y."source_type", 'sourceId', y."source_id", 'basis', y."basis"::text, 'amount', y."amount"::text, 'currency', y."currency", 'occurredOn', y."occurred_on", 'status', y."status", 'statementId', y."statement_id", 'ledgerTransactionId', y."ledger_transaction_id", 'reversedAt', y."reversed_at", 'createdAt', y."created_at") order by y."occurred_on", y."created_at")
    from "better_supabase"."commissions" y where y."statement_id" = v_statement."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_commission_statement"(uuid) from public, anon;
grant execute on function "better_supabase"."get_commission_statement"(uuid) to authenticated, service_role;

-- An organization's statements, newest first. filters is { seller (a value or a
-- list), status (a value or a list), sort, direction, facet, count, limit,
-- after, offset, paged, total, totalCap } (ADR 0749). Needs commissions.read;
-- without it a member sees their own.
create or replace function "better_supabase"."list_commission_statements"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commission_statements.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commission_statements.tenant is not null and coalesce(better_supabase.can('tenant', list_commission_statements.tenant, 'commissions.read'), false)));
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'seller') then
      raise exception 'facet is one of status, seller' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'seller' then (x."seller_id")::text end) as v
      from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('endsOn', 'createdAt', 'total') then
    raise exception 'sort is one of endsOn, createdAt, total' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" >= (v_after ->> 0)::date and ((x."ends_on" > (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" >= (v_after ->> 0)::date and ((x."ends_on" > (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."ends_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."ends_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."ends_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."total")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."total" >= (v_after ->> 0)::numeric and ((x."total" > (v_after ->> 0)::numeric) or (x."total" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."total" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."total" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'total' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sellerId', x."seller_id", 'currency', x."currency", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'status', x."status", 'total', x."total"::text, 'ledgerTransactionId', x."ledger_transaction_id", 'finalizedAt', x."finalized_at", 'paidAt', x."paid_at", 'paidBy', x."paid_by", 'createdAt', x."created_at") as j, jsonb_build_array((x."total")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."total" <= (v_after ->> 0)::numeric and ((x."total" < (v_after ->> 0)::numeric) or (x."total" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."total" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."total" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."commission_statements" x
      where x."tenant_id" = list_commission_statements.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_commission_statements"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_commission_statements"(uuid, jsonb) to authenticated, service_role;

-- An organization's accrued commissions, newest first. filters is { seller (a
-- value or a list), status (a value or a list), sort, direction, facet, count,
-- limit, after, offset, paged, total, totalCap } (ADR 0749). Needs
-- commissions.read; without it a member sees their own.
create or replace function "better_supabase"."list_commissions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commissions.filters, '{}'::jsonb);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commissions.tenant is not null and coalesce(better_supabase.can('tenant', list_commissions.tenant, 'commissions.read'), false)));
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'seller') then
      raise exception 'facet is one of status, seller' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'seller' then (x."seller_id")::text end) as v
      from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      select 1 from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('occurredOn', 'createdAt', 'amount') then
    raise exception 'sort is one of occurredOn, createdAt, amount' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" >= (v_after ->> 0)::date and ((x."occurred_on" > (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" <= (v_after ->> 0)::date and ((x."occurred_on" < (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'occurredOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" >= (v_after ->> 0)::date and ((x."occurred_on" > (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'occurredOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."occurred_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."occurred_on" <= (v_after ->> 0)::date and ((x."occurred_on" < (v_after ->> 0)::date) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" < (v_after ->> 1)::timestamptz) or (x."occurred_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."occurred_on" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."created_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."created_at" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."amount")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."amount" >= (v_after ->> 0)::numeric and ((x."amount" > (v_after ->> 0)::numeric) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."amount" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'amount' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'planId', x."plan_id", 'sellerId', x."seller_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'basis', x."basis"::text, 'amount', x."amount"::text, 'currency', x."currency", 'occurredOn', x."occurred_on", 'status', x."status", 'statementId', x."statement_id", 'ledgerTransactionId', x."ledger_transaction_id", 'reversedAt', x."reversed_at", 'createdAt', x."created_at") as j, jsonb_build_array((x."amount")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."amount" <= (v_after ->> 0)::numeric and ((x."amount" < (v_after ->> 0)::numeric) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" < (v_after ->> 1)::timestamptz) or (x."amount" = (v_after ->> 0)::numeric and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."amount" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."commissions" x
      where x."tenant_id" = list_commissions.tenant
        and (v_all or x."seller_id" = (select auth.uid()))
        and (not (v_filters -> 'seller' is not null and jsonb_typeof(v_filters -> 'seller') <> 'null' and not (jsonb_typeof(v_filters -> 'seller') = 'array' and jsonb_array_length(v_filters -> 'seller') = 0)) or x."seller_id" = any((case when jsonb_typeof(v_filters -> 'seller') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'seller')) else array[v_filters ->> 'seller'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_commissions"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_commissions"(uuid, jsonb) to authenticated, service_role;

-- An organization's plans and the assignments of each, newest first. filters
-- is { archived, sort, direction, facet, count, limit, after, offset, paged,
-- total, totalCap } (ADR 0749). Needs commissions.read.
create or replace function "better_supabase"."list_commission_plans"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_commission_plans.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_commission_plans.tenant is not null and coalesce(better_supabase.can('tenant', list_commission_plans.tenant, 'commissions.read'), false))) then
    raise exception 'not allowed to read commission plans' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'COMMISSION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind")::text end) as v
      from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
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
      select 1 from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'name') then
    raise exception 'sort is one of createdAt, name' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMMISSION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'kind', x."kind", 'rateBps', x."rate_bps", 'tiers', x."tiers", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('assignments', coalesce((
        select jsonb_agg(jsonb_build_object('id', a."id", 'organizationId', a."tenant_id", 'planId', a."plan_id", 'sellerId', a."seller_id", 'subjectType', a."subject_type", 'subjectId', a."subject_id", 'startsOn', a."starts_on", 'endsOn', a."ends_on", 'createdAt', a."created_at") order by a."starts_on" desc, a."created_at" desc)
        from "better_supabase"."commission_assignments" a where a."plan_id" = x."id"
      ), '[]'::jsonb)) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."commission_plans" x
      where x."tenant_id" = list_commission_plans.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;
revoke execute on function "better_supabase"."list_commission_plans"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_commission_plans"(uuid, jsonb) to authenticated, service_role;

-- What payroll adds for commissions: one line per seller and currency with
-- the total of the finalized and paid statements that end from from_date to
-- to_date. A payroll run reads it as the service role, or as a member with
-- commissions.read; payroll-export does not collect it by itself. amount is
-- in minor units, as text.
create or replace function "better_supabase"."commission_payroll_lines"(tenant uuid, from_date date, to_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (commission_payroll_lines.tenant is not null and coalesce(better_supabase.can('tenant', commission_payroll_lines.tenant, 'commissions.read'), false))) then
    raise exception 'not allowed to read commission statements' using errcode = '42501', hint = 'COMMISSION_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('userId', y.seller, 'currency', y.currency, 'amount', y.amount::text, 'statementIds', y.ids) order by y.seller, y.currency)
    from (
      select x."seller_id" as seller, x."currency" as currency, sum(x."total") as amount, jsonb_agg(x."id" order by x."ends_on") as ids
      from "better_supabase"."commission_statements" x
      where x."tenant_id" = commission_payroll_lines.tenant and x."status" in ('finalized', 'paid')
        and x."ends_on" between commission_payroll_lines.from_date and commission_payroll_lines.to_date and x."total" > 0
      group by x."seller_id", x."currency"
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."commission_payroll_lines"(uuid, date, date) from public, anon;
grant execute on function "better_supabase"."commission_payroll_lines"(uuid, date, date) to authenticated, service_role;

-- The period engine's close step for a commission period (ADR 0197): builds
-- and finalizes every seller's statement for the range, so a closed period
-- has no accrued commission outside a locked statement.
create or replace function "better_supabase"."commission_close_range"(tenant uuid, starts_on date, ends_on date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row record;
  v_id uuid;
begin
  for v_row in
    select distinct x."seller_id" as seller, x."currency" as currency from "better_supabase"."commissions" x
    where x."tenant_id" = commission_close_range.tenant and x."status" = 'accrued' and x."statement_id" is null
      and x."occurred_on" between commission_close_range.starts_on and commission_close_range.ends_on
  loop
    perform "better_supabase"."commission_statement_build"(commission_close_range.tenant, v_row.seller, v_row.currency, commission_close_range.starts_on, commission_close_range.ends_on);
  end loop;
  for v_id in
    select x."id" from "better_supabase"."commission_statements" x
    where x."tenant_id" = commission_close_range.tenant and x."status" = 'open'
      and x."starts_on" >= commission_close_range.starts_on and x."ends_on" <= commission_close_range.ends_on
  loop
    perform "better_supabase"."commission_statement_finalize"(v_id);
  end loop;
end;
$$;
revoke execute on function "better_supabase"."commission_close_range"(uuid, date, date) from public, anon, authenticated;
grant execute on function "better_supabase"."commission_close_range"(uuid, date, date) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."commission_plans" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."commission_plans" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."commission_plans" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."commission_plans" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."commission_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')) or "seller_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."commission_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."commission_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."commission_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."commissions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')) or "seller_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."commissions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."commissions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."commissions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."commission_statements" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('commissions.read')) or "seller_id" = (select auth.uid()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."commission_statements" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."commission_statements" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."commission_statements" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.commission_plans deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"commission_plan","event_prefix":"commission_plan"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.commission_assignments deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"commission_assignment","event_prefix":"commission_assignment"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.commissions deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"commission","event_prefix":"commission"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.commission_statements deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"commission_statement","event_prefix":"commission_statement"}');

-- blocks.commissions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."commission_amount"(kind text, rate_bps integer, tiers jsonb, prior bigint, basis bigint)
returns bigint
language sql
immutable
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_amount"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."commission_amount"(text, integer, jsonb, bigint, bigint) from public, anon, authenticated;
grant execute on function "api"."commission_amount"(text, integer, jsonb, bigint, bigint) to service_role;

create or replace function "api"."commission_tiers_valid"(tiers jsonb)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_tiers_valid"($1) $$;
revoke execute on function "api"."commission_tiers_valid"(jsonb) from public, anon, authenticated;
grant execute on function "api"."commission_tiers_valid"(jsonb) to service_role;

create or replace function "api"."save_commission_plan"(tenant uuid, name text, kind text, rate_bps integer default null, tiers jsonb default null, plan_id uuid default null, archived boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_commission_plan"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) from public, anon;
grant execute on function "api"."save_commission_plan"(uuid, text, text, integer, jsonb, uuid, boolean) to authenticated, service_role;

create or replace function "api"."assign_commission_plan"(tenant uuid, plan_id uuid, seller_id uuid, subject_type text default null, subject_id text default null, starts_on date default null, ends_on date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assign_commission_plan"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) from public, anon;
grant execute on function "api"."assign_commission_plan"(uuid, uuid, uuid, text, text, date, date) to authenticated, service_role;

create or replace function "api"."end_commission_assignment"(assignment_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_commission_assignment"($1) $$;
revoke execute on function "api"."end_commission_assignment"(uuid) from public, anon;
grant execute on function "api"."end_commission_assignment"(uuid) to authenticated, service_role;

create or replace function "api"."commission_plan_for"(tenant uuid, seller_id uuid, subject_type text, subject_id text, on_date date)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_plan_for"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."commission_plan_for"(uuid, uuid, text, text, date) from public, anon, authenticated;
grant execute on function "api"."commission_plan_for"(uuid, uuid, text, text, date) to service_role;

create or replace function "api"."commission_accrue"(tenant uuid, seller_id uuid, source_type text, source_id text, basis bigint, currency text, occurred_on date default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_accrue"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) from public, anon, authenticated;
grant execute on function "api"."commission_accrue"(uuid, uuid, text, text, bigint, text, date, text, text) to service_role;

create or replace function "api"."accrue_commission"(tenant uuid, seller_id uuid, source_type text, source_id text, basis bigint, currency text, occurred_on date default null, subject_type text default null, subject_id text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."accrue_commission"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) from public, anon;
grant execute on function "api"."accrue_commission"(uuid, uuid, text, text, bigint, text, date, text, text) to authenticated, service_role;

create or replace function "api"."reverse_commission"(commission_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reverse_commission"($1, $2) $$;
revoke execute on function "api"."reverse_commission"(uuid, text) from public, anon;
grant execute on function "api"."reverse_commission"(uuid, text) to authenticated, service_role;

create or replace function "api"."commission_statement_build"(tenant uuid, seller_id uuid, currency text, starts_on date, ends_on date)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_statement_build"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."commission_statement_build"(uuid, uuid, text, date, date) from public, anon, authenticated;
grant execute on function "api"."commission_statement_build"(uuid, uuid, text, date, date) to service_role;

create or replace function "api"."build_commission_statement"(tenant uuid, seller_id uuid, currency text, starts_on date, ends_on date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."build_commission_statement"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."build_commission_statement"(uuid, uuid, text, date, date) from public, anon;
grant execute on function "api"."build_commission_statement"(uuid, uuid, text, date, date) to authenticated, service_role;

create or replace function "api"."commission_statement_finalize"(statement_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_statement_finalize"($1) $$;
revoke execute on function "api"."commission_statement_finalize"(uuid) from public, anon, authenticated;
grant execute on function "api"."commission_statement_finalize"(uuid) to service_role;

create or replace function "api"."finalize_commission_statement"(statement_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."finalize_commission_statement"($1) $$;
revoke execute on function "api"."finalize_commission_statement"(uuid) from public, anon;
grant execute on function "api"."finalize_commission_statement"(uuid) to authenticated, service_role;

create or replace function "api"."pay_commission_statement"(statement_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pay_commission_statement"($1) $$;
revoke execute on function "api"."pay_commission_statement"(uuid) from public, anon;
grant execute on function "api"."pay_commission_statement"(uuid) to authenticated, service_role;

create or replace function "api"."get_commission_statement"(statement_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_commission_statement"($1) $$;
revoke execute on function "api"."get_commission_statement"(uuid) from public, anon;
grant execute on function "api"."get_commission_statement"(uuid) to authenticated, service_role;

create or replace function "api"."list_commission_statements"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_commission_statements"($1, $2) $$;
revoke execute on function "api"."list_commission_statements"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_commission_statements"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_commissions"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_commissions"($1, $2) $$;
revoke execute on function "api"."list_commissions"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_commissions"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_commission_plans"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_commission_plans"($1, $2) $$;
revoke execute on function "api"."list_commission_plans"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_commission_plans"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."commission_payroll_lines"(tenant uuid, from_date date, to_date date)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_payroll_lines"($1, $2, $3) $$;
revoke execute on function "api"."commission_payroll_lines"(uuid, date, date) from public, anon;
grant execute on function "api"."commission_payroll_lines"(uuid, date, date) to authenticated, service_role;

create or replace function "api"."commission_close_range"(tenant uuid, starts_on date, ends_on date)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."commission_close_range"($1, $2, $3) $$;
revoke execute on function "api"."commission_close_range"(uuid, date, date) from public, anon, authenticated;
grant execute on function "api"."commission_close_range"(uuid, date, date) to service_role;
