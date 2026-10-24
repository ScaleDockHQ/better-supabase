-- ==== schema supabase/schemas/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block billing@3 managed
-- @bsb-hash sha256:8d9cf399bcb9773587010e9a610106f9771f53bcd4a13df16a3f42d2e516fac4
-- Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."billing_customers";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset. A tenant billed
-- as a Stripe Accounts v2 account has its acct_ id first; Stripe creates the
-- linked cus_ id at the first checkout, and the webhook records it.
create table if not exists "better_supabase"."billing_customers" (
  "workspace_id" uuid primary key,
  "stripe_customer_id" text unique check ("stripe_customer_id" ~ '^cus_'),
  "stripe_customer_account_id" text unique check ("stripe_customer_account_id" ~ '^acct_'),
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."billing_customers" add column if not exists "stripe_customer_account_id" text unique check ("stripe_customer_account_id" ~ '^acct_');
alter table "better_supabase"."billing_customers" alter column "stripe_customer_id" drop not null;
alter table "better_supabase"."billing_customers" drop constraint if exists bsb_billing_customers_party;
alter table "better_supabase"."billing_customers" add constraint bsb_billing_customers_party check ("stripe_customer_id" is not null or "stripe_customer_account_id" is not null);
alter table "better_supabase"."billing_customers" enable row level security;
revoke all on "better_supabase"."billing_customers" from anon, authenticated;
grant select on "better_supabase"."billing_customers" to authenticated;
grant all on "better_supabase"."billing_customers" to service_role;
drop policy if exists "billing_customers_read" on "better_supabase"."billing_customers";
create policy "billing_customers_read" on "better_supabase"."billing_customers" for select to authenticated
  using ("workspace_id" in (select better_supabase.tenant_ids_with('billing.read')));

create or replace function "better_supabase"."billing_customer"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_id" from "better_supabase"."billing_customers" b
  where b."workspace_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
$$;

-- The tenant's Stripe Accounts v2 account (acct_), when it is billed as one.
create or replace function "better_supabase"."billing_account"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b
  where b."workspace_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$$;

-- The tenant of a customer (cus_) or an account (acct_).
create or replace function "better_supabase"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b."workspace_id" from "better_supabase"."billing_customers" b
  where b."stripe_customer_id" = billing_customer_tenant.customer
    or b."stripe_customer_account_id" = billing_customer_tenant.customer
$$;

-- Links tenant to customer once, or records the customer Stripe created for
-- the tenant's account. Returns the customer that is linked, which is the
-- earlier one when two checkouts raced.
create or replace function "better_supabase"."link_billing_customer"(tenant uuid, customer text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into "better_supabase"."billing_customers" as b ("workspace_id", "stripe_customer_id")
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict ("workspace_id") do update set "stripe_customer_id" = excluded."stripe_customer_id"
    where b."stripe_customer_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."workspace_id" = link_billing_customer.tenant);
end;
$$;

-- Links tenant to a Stripe Accounts v2 account once. Returns the account that
-- is linked, which is the earlier one when two calls raced.
create or replace function "better_supabase"."link_billing_account"(tenant uuid, account text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into "better_supabase"."billing_customers" as b ("workspace_id", "stripe_customer_account_id")
  values (link_billing_account.tenant, link_billing_account.account)
  on conflict ("workspace_id") do update set "stripe_customer_account_id" = excluded."stripe_customer_account_id"
    where b."stripe_customer_account_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."workspace_id" = link_billing_account.tenant);
end;
$$;

-- Members who take a seat.
create or replace function "better_supabase"."billing_seat_count"(tenant uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."memberships" m
  where m."workspace_id" = billing_seat_count.tenant
$$;

-- The tenant's active subscription item for price (or its first item), from
-- the Stripe Sync Engine's stripe schema: { subscription, item, price,
-- quantity, status }, or null.
create or replace function "better_supabase"."billing_subscription_item"(tenant uuid, price text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."workspace_id" = billing_subscription_item.tenant);
  found jsonb;
begin
  if customer is null or to_regclass('stripe.subscription_items') is null then
    return null;
  end if;
  execute $q$
    select jsonb_build_object(
      'subscription', s.id, 'item', i.id, 'price', i.price, 'quantity', i.quantity, 'status', s.status
    )
    from stripe.subscriptions s
    join stripe.subscription_items i on i.subscription = s.id
    where s.customer = $1
      and s.status in ('active', 'trialing', 'past_due')
      and ($2::text is null or i.price = $2)
    order by s.created desc nulls last, i.created nulls last
    limit 1
  $q$ into found using customer, price;
  return found;
end;
$$;

-- The Stripe price of a plan key from options.plans (the app's plan
-- catalog), for checkout({ plan }); null without the option or the plan.
-- variant picks one of the plan's prices (a credit pack, a tier); without it,
-- the row without a variant.
drop function if exists "better_supabase"."billing_plan_price"(text, text);
create or replace function "better_supabase"."billing_plan_price"(plan text, billing_interval text default null, variant text default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select null::text
$$;
revoke execute on function "better_supabase"."billing_plan_price"(text, text, text) from public, anon;
grant execute on function "better_supabase"."billing_plan_price"(text, text, text) to authenticated, service_role;

drop function if exists "better_supabase"."billing_platform_subscriptions"();
create or replace function "better_supabase"."billing_platform_subscriptions"()
returns table (
  tenant uuid,
  customer text,
  customer_email text,
  customer_name text,
  subscription text,
  status text,
  price text,
  price_metadata jsonb,
  plan text,
  quantity bigint,
  amount bigint,
  currency text,
  recurring_interval text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean,
  created timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  items text := case when to_regclass('stripe.subscription_items') is null
    then 'left join lateral (select null::jsonb as item) it on true'
    else 'left join lateral (select to_jsonb(i.*) as item from stripe.subscription_items i where i.subscription = s.id order by i.created nulls last limit 1) it on true' end;
  prices text := case when to_regclass('stripe.prices') is null
    then 'left join lateral (select null::jsonb as price_row) pr on true'
    else 'left join lateral (select to_jsonb(p.*) as price_row from stripe.prices p where p.id = coalesce(it.item -> ''price'' ->> ''id'', it.item ->> ''price'')) pr on true' end;
  customers text := case when to_regclass('stripe.customers') is null
    then 'left join lateral (select null::jsonb as customer_row) cu on true'
    else 'left join lateral (select to_jsonb(k.*) as customer_row from stripe.customers k where k.id = b."stripe_customer_id"::text) cu on true' end;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  if to_regclass('stripe.subscriptions') is null then
    return;
  end if;
  return query execute format($q$
    select r.tenant, r.customer, r.customer_email, r.customer_name, r.subscription, r.status, r.price,
      r.price_metadata, null::text, r.quantity,
      r.unit_amount * coalesce(r.quantity, 1), r.currency, r.recurring_interval, r.current_period_start,
      r.current_period_end, r.cancel_at_period_end, r.created
    from (
      select distinct on (b."workspace_id") b."workspace_id" as tenant, b."stripe_customer_id"::text as customer,
        cu.customer_row ->> 'email' as customer_email, cu.customer_row ->> 'name' as customer_name,
        s.id::text as subscription, x.row ->> 'status' as status,
        coalesce(it.item -> 'price' ->> 'id', it.item ->> 'price') as price,
        coalesce(pr.price_row -> 'metadata', it.item -> 'price' -> 'metadata') as price_metadata,
        (it.item ->> 'quantity')::bigint as quantity,
        coalesce((pr.price_row ->> 'unit_amount')::bigint, (it.item -> 'price' ->> 'unit_amount')::bigint) as unit_amount,
        coalesce(pr.price_row ->> 'currency', it.item -> 'price' ->> 'currency', x.row ->> 'currency') as currency,
        coalesce(pr.price_row -> 'recurring' ->> 'interval', it.item -> 'price' -> 'recurring' ->> 'interval') as recurring_interval,
        coalesce((case jsonb_typeof(x.row -> 'current_period_start') when 'number' then to_timestamp((x.row -> 'current_period_start')::text::double precision) when 'string' then (x.row -> 'current_period_start' #>> '{}')::timestamptz end), (case jsonb_typeof(it.item -> 'current_period_start') when 'number' then to_timestamp((it.item -> 'current_period_start')::text::double precision) when 'string' then (it.item -> 'current_period_start' #>> '{}')::timestamptz end)) as current_period_start,
        coalesce((case jsonb_typeof(x.row -> 'current_period_end') when 'number' then to_timestamp((x.row -> 'current_period_end')::text::double precision) when 'string' then (x.row -> 'current_period_end' #>> '{}')::timestamptz end), (case jsonb_typeof(it.item -> 'current_period_end') when 'number' then to_timestamp((it.item -> 'current_period_end')::text::double precision) when 'string' then (it.item -> 'current_period_end' #>> '{}')::timestamptz end)) as current_period_end,
        coalesce((x.row ->> 'cancel_at_period_end')::boolean, false) as cancel_at_period_end,
        (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) as created
      from "better_supabase"."billing_customers" b
      join stripe.subscriptions s on s.customer = b."stripe_customer_id"
      cross join lateral (select to_jsonb(s.*) as row) x
      %s
      %s
      %s
      order by b."workspace_id", (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) desc nulls last
    ) r
  $q$, items, prices, customers);
end;
$$;

drop function if exists "better_supabase"."billing_platform_invoices"();
create or replace function "better_supabase"."billing_platform_invoices"()
returns table (
  tenant uuid,
  customer text,
  invoice text,
  subscription text,
  number text,
  status text,
  amount_due bigint,
  amount_paid bigint,
  amount_remaining bigint,
  total bigint,
  currency text,
  due_date timestamptz,
  finalized_at timestamptz,
  paid_at timestamptz,
  hosted_invoice_url text,
  invoice_pdf text,
  customer_email text,
  customer_name text,
  created timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customers text := case when to_regclass('stripe.customers') is null
    then 'left join lateral (select null::jsonb as customer_row) cu on true'
    else 'left join lateral (select to_jsonb(k.*) as customer_row from stripe.customers k where k.id = b."stripe_customer_id"::text) cu on true' end;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  if to_regclass('stripe.invoices') is null then
    return;
  end if;
  return query execute format($q$
    select b."workspace_id", b."stripe_customer_id"::text, v.id::text,
      coalesce(x.row -> 'subscription' ->> 'id', x.row ->> 'subscription'),
      x.row ->> 'number', x.row ->> 'status',
      (x.row ->> 'amount_due')::bigint, (x.row ->> 'amount_paid')::bigint,
      (x.row ->> 'amount_remaining')::bigint, (x.row ->> 'total')::bigint,
      x.row ->> 'currency',
      (case jsonb_typeof(x.row -> 'due_date') when 'number' then to_timestamp((x.row -> 'due_date')::text::double precision) when 'string' then (x.row -> 'due_date' #>> '{}')::timestamptz end),
      (case jsonb_typeof(x.row -> 'status_transitions' -> 'finalized_at') when 'number' then to_timestamp((x.row -> 'status_transitions' -> 'finalized_at')::text::double precision) when 'string' then (x.row -> 'status_transitions' -> 'finalized_at' #>> '{}')::timestamptz end),
      (case jsonb_typeof(x.row -> 'status_transitions' -> 'paid_at') when 'number' then to_timestamp((x.row -> 'status_transitions' -> 'paid_at')::text::double precision) when 'string' then (x.row -> 'status_transitions' -> 'paid_at' #>> '{}')::timestamptz end),
      x.row ->> 'hosted_invoice_url', x.row ->> 'invoice_pdf',
      coalesce(x.row ->> 'customer_email', cu.customer_row ->> 'email'),
      coalesce(x.row ->> 'customer_name', cu.customer_row ->> 'name'),
      (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end),
      coalesce((case jsonb_typeof(x.row -> 'updated_at') when 'number' then to_timestamp((x.row -> 'updated_at')::text::double precision) when 'string' then (x.row -> 'updated_at' #>> '{}')::timestamptz end), (case jsonb_typeof(x.row -> '_updated_at') when 'number' then to_timestamp((x.row -> '_updated_at')::text::double precision) when 'string' then (x.row -> '_updated_at' #>> '{}')::timestamptz end))
    from "better_supabase"."billing_customers" b
    join stripe.invoices v on v.customer = b."stripe_customer_id"
    cross join lateral (select to_jsonb(v.*) as row) x
    %s
  $q$, customers);
end;
$$;
drop function if exists "better_supabase"."billing_platform_customers"();
-- Every linked customer, with or without a subscription or invoice, for
-- platform staff: the tenant, the Stripe customer and its contact from the
-- Sync Engine's stripe.customers (null without the table).
create or replace function "better_supabase"."billing_platform_customers"()
returns table (
  tenant uuid,
  customer text,
  email text,
  name text,
  created timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customers text := case when to_regclass('stripe.customers') is null
    then 'left join lateral (select null::jsonb as customer_row) cu on true'
    else 'left join lateral (select to_jsonb(k.*) as customer_row from stripe.customers k where k.id = b."stripe_customer_id"::text) cu on true' end;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  return query execute format($q$
    select b."workspace_id", b."stripe_customer_id"::text,
      cu.customer_row ->> 'email', cu.customer_row ->> 'name',
      (case jsonb_typeof(cu.customer_row -> 'created') when 'number' then to_timestamp((cu.customer_row -> 'created')::text::double precision) when 'string' then (cu.customer_row -> 'created' #>> '{}')::timestamptz end)
    from "better_supabase"."billing_customers" b
    %s
    where b."stripe_customer_id" is not null
    order by b."workspace_id"
  $q$, customers);
end;
$$;

-- billing_platform_customers as jsonb, for createBilling().allCustomers().
create or replace function "better_supabase"."billing_all_customers"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(c.*) order by c.tenant), '[]'::jsonb)
  from "better_supabase"."billing_platform_customers"() c
$$;
revoke execute on function "better_supabase"."billing_platform_customers"() from public, anon;
grant execute on function "better_supabase"."billing_platform_customers"() to authenticated, service_role;
revoke execute on function "better_supabase"."billing_all_customers"() from public, anon;
grant execute on function "better_supabase"."billing_all_customers"() to authenticated, service_role;
revoke execute on function "better_supabase"."billing_platform_subscriptions"() from public, anon;
grant execute on function "better_supabase"."billing_platform_subscriptions"() to authenticated, service_role;
revoke execute on function "better_supabase"."billing_platform_invoices"() from public, anon;
grant execute on function "better_supabase"."billing_platform_invoices"() to authenticated, service_role;

-- Rows of a Stripe Sync Engine table for the tenant's customer, newest
-- first, or [] when the table doesn't exist. Reads need billing.read in the
-- tenant, or platform staff.
create or replace function "better_supabase"."billing_stripe_rows"(tenant uuid, source text, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."workspace_id" = billing_stripe_rows.tenant);
  found jsonb;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'billing.read'), false)) or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read billing in this tenant' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  if billing_stripe_rows.source not in ('invoices', 'payment_methods', 'subscriptions', 'customers', 'tax_ids') then
    raise exception 'Unknown Stripe table %', billing_stripe_rows.source using errcode = '22023', hint = 'BILLING_SOURCE';
  end if;
  if customer is null or to_regclass('stripe.' || billing_stripe_rows.source) is null then
    return '[]'::jsonb;
  end if;
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(r.*)), ''[]''::jsonb) from (
       select * from stripe.%I x where %s = $1 order by x.created desc nulls last limit $2
     ) r',
    billing_stripe_rows.source,
    case when billing_stripe_rows.source = 'customers' then 'x.id' else 'x.customer' end
  ) into found using customer, greatest(1, least(coalesce(billing_stripe_rows.max_rows, 50), 500));
  return found;
end;
$$;

create or replace function "better_supabase"."billing_invoices"(tenant uuid, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."billing_stripe_rows"(billing_invoices.tenant, 'invoices', billing_invoices.max_rows)
$$;

create or replace function "better_supabase"."billing_payment_methods"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."billing_stripe_rows"(billing_payment_methods.tenant, 'payment_methods', 50)
$$;

-- The customer's contact details as Stripe holds them (email, name,
-- address, phone): Stripe is the record for the billing contact.
create or replace function "better_supabase"."billing_customer_details"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."billing_stripe_rows"(billing_customer_details.tenant, 'customers', 1) -> 0
$$;

-- The customer's tax ids from the Sync Engine's stripe.tax_ids, newest
-- first: [{ id, type, value, country, verification: { status } | null,
-- created }], the shape of Stripe's tax id objects; [] without the table.
create or replace function "better_supabase"."billing_tax_ids"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t ->> 'id',
    'type', coalesce(t ->> 'type', t -> '_raw_data' ->> 'type'),
    'value', coalesce(t ->> 'value', t -> '_raw_data' ->> 'value'),
    'country', coalesce(t ->> 'country', t -> '_raw_data' ->> 'country'),
    'verification', case
      when jsonb_typeof(coalesce(t -> 'verification', t -> '_raw_data' -> 'verification')) = 'object'
        then jsonb_build_object('status', coalesce(t -> 'verification', t -> '_raw_data' -> 'verification') ->> 'status')
    end,
    'created', coalesce(t -> 'created', t -> '_raw_data' -> 'created')
  ) order by ord), '[]'::jsonb)
  from jsonb_array_elements("better_supabase"."billing_stripe_rows"(billing_tax_ids.tenant, 'tax_ids', 100)) with ordinality as r(t, ord)
$$;

-- The tenant's newest subscription as the Sync Engine stores it, with its
-- items, or null, without checking the caller: for the app's own security
-- definer functions (resolving a member's plan), executable by its owner only.
create or replace function "better_supabase"."billing_tenant_subscription"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."workspace_id" = billing_tenant_subscription.tenant);
  found jsonb;
begin
  if customer is null or to_regclass('stripe.subscriptions') is null then
    return null;
  end if;
  execute $q$
    select to_jsonb(s.*) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
      from stripe.subscription_items i where i.subscription = s.id
    ), '[]'::jsonb))
    from stripe.subscriptions s
    where s.customer = $1
    order by (s.status in ('active', 'trialing', 'past_due')) desc, s.created desc nulls last
    limit 1
  $q$ into found using customer;
  return found;
end;
$$;

-- billing_tenant_subscription for billing.read in the tenant, or platform staff.
create or replace function "better_supabase"."billing_subscription"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'billing.read'), false)) or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read billing in this tenant' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  return "better_supabase"."billing_tenant_subscription"(billing_subscription.tenant);
end;
$$;

-- Every tenant's newest subscription, for platform staff: [{ tenant,
-- customer, subscription }], newest first, of one status when given, and
-- created before before_created (Stripe's epoch seconds) for the next page.
create or replace function "better_supabase"."billing_all_subscriptions"(for_status text default null, max_rows integer default 100, before_created bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  found jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  if to_regclass('stripe.subscriptions') is null then
    return '[]'::jsonb;
  end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object('tenant', p.tenant, 'customer', p.customer, 'subscription', p.subscription) order by p.created desc nulls last), '[]'::jsonb)
    from (
      select * from (
        select distinct on (b."workspace_id") b."workspace_id"::text as tenant, b."stripe_customer_id" as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from "better_supabase"."billing_customers" b
        join stripe.subscriptions s on s.customer = b."stripe_customer_id"
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b."workspace_id", s.created desc nulls last
      ) r
      order by r.created desc nulls last
      limit greatest(1, least(coalesce($2, 100), 500))
    ) p
  $q$ into found using for_status, max_rows, before_created;
  return coalesce(found, '[]'::jsonb);
end;
$$;

-- Every tenant's invoices, for platform staff: [{ tenant, customer, invoice }],
-- newest first, of one status when given, created before before_created.
create or replace function "better_supabase"."billing_all_invoices"(for_status text default null, max_rows integer default 100, before_created bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  found jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  if to_regclass('stripe.invoices') is null then
    return '[]'::jsonb;
  end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object('tenant', p.tenant, 'customer', p.customer, 'invoice', p.invoice) order by p.created desc nulls last), '[]'::jsonb)
    from (
      select b."workspace_id"::text as tenant, b."stripe_customer_id" as customer, x.created, to_jsonb(x.*) as invoice
      from "better_supabase"."billing_customers" b
      join stripe.invoices x on x.customer = b."stripe_customer_id"
      where ($1::text is null or x.status = $1)
        and ($3::bigint is null or x.created < $3)
      order by x.created desc nulls last
      limit greatest(1, least(coalesce($2, 100), 500))
    ) p
  $q$ into found using for_status, max_rows, before_created;
  return coalesce(found, '[]'::jsonb);
end;
$$;

-- For the billing page: { customer, account, seats, subscription }.
create or replace function "better_supabase"."billing_status"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'billing.read'), false)) then
    raise exception 'Not allowed to read billing in this tenant' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'customer', (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."workspace_id" = billing_status.tenant),
    'account', (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."workspace_id" = billing_status.tenant),
    'seats', "better_supabase"."billing_seat_count"(tenant),
    'subscription', "better_supabase"."billing_subscription_item"(tenant)
  );
end;
$$;


revoke execute on function "better_supabase"."billing_stripe_rows"(uuid, text, integer) from public, anon;
revoke execute on function "better_supabase"."billing_invoices"(uuid, integer) from public, anon;
revoke execute on function "better_supabase"."billing_payment_methods"(uuid) from public, anon;
revoke execute on function "better_supabase"."billing_customer_details"(uuid) from public, anon;
revoke execute on function "better_supabase"."billing_tax_ids"(uuid) from public, anon;
grant execute on function "better_supabase"."billing_stripe_rows"(uuid, text, integer) to authenticated, service_role;
grant execute on function "better_supabase"."billing_invoices"(uuid, integer) to authenticated, service_role;
grant execute on function "better_supabase"."billing_payment_methods"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."billing_customer_details"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."billing_tax_ids"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."billing_customer"(uuid) from public, anon;
revoke execute on function "better_supabase"."billing_account"(uuid) from public, anon;
revoke execute on function "better_supabase"."link_billing_account"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."billing_customer_tenant"(text) from public, anon, authenticated;
revoke execute on function "better_supabase"."link_billing_customer"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."billing_seat_count"(uuid) from public, anon, authenticated;
revoke execute on function "better_supabase"."billing_subscription_item"(uuid, text) from public, anon, authenticated;
revoke execute on function "better_supabase"."billing_status"(uuid) from public, anon;
revoke execute on function "better_supabase"."billing_subscription"(uuid) from public, anon;
revoke execute on function "better_supabase"."billing_tenant_subscription"(uuid) from public, anon, authenticated, service_role;
revoke execute on function "better_supabase"."billing_all_subscriptions"(text, integer, bigint) from public, anon;
revoke execute on function "better_supabase"."billing_all_invoices"(text, integer, bigint) from public, anon;
grant execute on function "better_supabase"."billing_all_invoices"(text, integer, bigint) to authenticated, service_role;
grant execute on function "better_supabase"."billing_subscription"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."billing_all_subscriptions"(text, integer, bigint) to authenticated, service_role;
grant execute on function "better_supabase"."billing_customer"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."billing_account"(uuid) to authenticated, service_role;
grant execute on function "better_supabase"."link_billing_account"(uuid, text) to service_role;
grant execute on function "better_supabase"."billing_customer_tenant"(text) to service_role;
grant execute on function "better_supabase"."link_billing_customer"(uuid, text) to service_role;
grant execute on function "better_supabase"."billing_seat_count"(uuid) to service_role;
grant execute on function "better_supabase"."billing_subscription_item"(uuid, text) to service_role;
grant execute on function "better_supabase"."billing_status"(uuid) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."billing_customers";
create policy bsb_tenant_scope on "better_supabase"."billing_customers" as restrictive
  for all to authenticated
  using (
    "workspace_id" in (select better_supabase.member_workspace_ids())
    or ("workspace_id" in (select better_supabase.tenant_ids_with('billing.read')))
  )
  with check ("workspace_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:4f71483342cbef4eba9156af3657fd76790c1c0e4d2c4596f41d7a2edb3b3651
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
