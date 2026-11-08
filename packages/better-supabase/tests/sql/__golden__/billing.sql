-- ==== alone: schema supabase/schemas/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block billing@4 managed
-- @bsb-hash sha256:f0a0607061300ceb13380945a7ac6d5d44f62ec4615e963bae7b061bf34187bd
-- Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset. A tenant billed
-- as a Stripe Accounts v2 account has its acct_ id first; Stripe creates the
-- linked cus_ id at the first checkout, and the webhook records it.
create table "better_supabase"."billing_customers" (
  "tenant_id" uuid primary key,
  "stripe_customer_id" text unique constraint bsb_billing_customers_stripe_customer_id_check check ("stripe_customer_id" ~ '^cus_'),
  "stripe_customer_account_id" text unique constraint bsb_billing_customers_stripe_customer_account_id_check check ("stripe_customer_account_id" ~ '^acct_'),
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."billing_customers" alter column "stripe_customer_id" drop not null;
alter table "better_supabase"."billing_customers" add constraint bsb_billing_customers_party check ("stripe_customer_id" is not null or "stripe_customer_account_id" is not null);
alter table "better_supabase"."billing_customers" enable row level security;
revoke all on "better_supabase"."billing_customers" from public, anon, authenticated;
grant select on "better_supabase"."billing_customers" to authenticated;
grant all on "better_supabase"."billing_customers" to service_role;
create policy bsb_billing_customers_read on "better_supabase"."billing_customers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')));

create or replace function "better_supabase"."billing_customer"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_id" from "better_supabase"."billing_customers" b
  where b."tenant_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
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
  where b."tenant_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$$;

-- The tenant of a customer (cus_) or an account (acct_).
create or replace function "better_supabase"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b."tenant_id" from "better_supabase"."billing_customers" b
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_id")
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict ("tenant_id") do update set "stripe_customer_id" = excluded."stripe_customer_id"
    where b."stripe_customer_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_customer.tenant);
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_account_id")
  values (link_billing_account.tenant, link_billing_account.account)
  on conflict ("tenant_id") do update set "stripe_customer_account_id" = excluded."stripe_customer_account_id"
    where b."stripe_customer_account_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_account.tenant);
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
  where m."organization_id" = billing_seat_count.tenant
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_subscription_item.tenant);
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
      select distinct on (b."tenant_id") b."tenant_id" as tenant, b."stripe_customer_id"::text as customer,
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
      order by b."tenant_id", (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) desc nulls last
    ) r
  $q$, items, prices, customers);
end;
$$;
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
    select b."tenant_id", b."stripe_customer_id"::text, v.id::text,
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
    select b."tenant_id", b."stripe_customer_id"::text,
      cu.customer_row ->> 'email', cu.customer_row ->> 'name',
      (case jsonb_typeof(cu.customer_row -> 'created') when 'number' then to_timestamp((cu.customer_row -> 'created')::text::double precision) when 'string' then (cu.customer_row -> 'created' #>> '{}')::timestamptz end)
    from "better_supabase"."billing_customers" b
    %s
    where b."stripe_customer_id" is not null
    order by b."tenant_id"
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_stripe_rows.tenant);
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_tenant_subscription.tenant);
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
        select distinct on (b."tenant_id") b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from "better_supabase"."billing_customers" b
        join stripe.subscriptions s on s.customer = b."stripe_customer_id"
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b."tenant_id", s.created desc nulls last
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
      select b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, x.created, to_jsonb(x.*) as invoice
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
    'customer', (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
    'account', (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
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

-- The billing page in one call. It runs as the caller and reads through the
-- status, invoice and usage functions, which check billing and usage reads.
create or replace function "better_supabase"."billing_overview"(tenant uuid, invoice_limit integer default 10)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status jsonb := "better_supabase"."billing_status"(billing_overview.tenant);
begin
  return jsonb_build_object(
    'customerId', v_status -> 'customer',
    'accountId', v_status -> 'account',
    'seats', coalesce((v_status ->> 'seats')::integer, 0),
    'subscription', coalesce(v_status -> 'subscription', 'null'::jsonb),
    'invoices', coalesce("better_supabase"."billing_invoices"(billing_overview.tenant, billing_overview.invoice_limit), '[]'::jsonb),
    'usage', coalesce('[]'::jsonb, '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."billing_overview"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."billing_overview"(uuid, integer) to authenticated, service_role;

-- A subscription kept in Postgres: unit_amount is the price of one unit for one
-- billing_interval in minor units of currency, and [period_start, period_end)
-- is the current period.
create table "better_supabase"."billing_native_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan" text not null constraint bsb_billing_native_subscriptions_plan_check check (length("plan") >= 1 and length("plan") <= 100),
  "currency" text not null constraint bsb_billing_native_subscriptions_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "unit_amount" bigint not null constraint bsb_billing_native_subscriptions_unit_amount_check check ("unit_amount" >= 0),
  "quantity" integer not null default 1 constraint bsb_billing_native_subscriptions_quantity_check check ("quantity" >= 0),
  "billing_interval" text not null default 'month',
  "status" text not null default 'active' constraint bsb_billing_native_subscriptions_status_check check ("status" in ('active', 'canceled')),
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "canceled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint "bsb_billing_native_subscriptions_interval_check" check ("billing_interval" in ('week', 'month', 'year')),
  constraint bsb_billing_native_subscriptions_check check ("period_end" > "period_start")
);
create index "billing_native_subscriptions_tenant_idx" on "better_supabase"."billing_native_subscriptions" ("tenant_id", "status");
alter table "better_supabase"."billing_native_subscriptions" enable row level security;
revoke all on "better_supabase"."billing_native_subscriptions" from public, anon, authenticated;
grant all on "better_supabase"."billing_native_subscriptions" to service_role;

-- Starts a subscription for tenant; its first period begins at started_at
-- (now by default). Service role only.
create or replace function "better_supabase"."create_native_subscription"(tenant uuid, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role creates native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  insert into "better_supabase"."billing_native_subscriptions" ("tenant_id", "plan", "currency", "unit_amount", "quantity", "billing_interval", "period_start", "period_end")
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'plan', v_row."plan", 'currency', v_row."currency",
    'unit_amount', v_row."unit_amount"::text, 'quantity', v_row."quantity", 'interval', v_row."billing_interval",
    'period_start', v_row."period_start", 'period_end', v_row."period_end");
exception when check_violation or invalid_text_representation then
  raise exception 'The subscription is invalid' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
end;
$$;

-- Changes the price or the quantity of a subscription at an instant inside its
-- current period and returns what the change adds: credit is the unused part
-- of the old price, charge the remaining part of the new one, and net is
-- charge minus credit (negative for a downgrade). With the ledger block the
-- net posts as one transaction (receivable against proration revenue), once
-- per subscription and instant. Service role only.
create or replace function "better_supabase"."prorate_change"(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_end" - v_at) / extract(epoch from v_row."period_end" - v_row."period_start")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  update "better_supabase"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$$;

-- Cancels a subscription. Service role only.
create or replace function "better_supabase"."cancel_native_subscription"(subscription_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role cancels native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  update "better_supabase"."billing_native_subscriptions" set "status" = 'canceled', "canceled_at" = now()
    where "id" = cancel_native_subscription.subscription_id and "status" = 'active';
  return found;
end;
$$;
revoke execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) to service_role;
revoke execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) to service_role;
revoke execute on function "better_supabase"."cancel_native_subscription"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."cancel_native_subscription"(uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."billing_customers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."billing_customers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."billing_customers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."billing_customers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:9192c5a247a10a63b3db4a9a5d145a27c1a3ad52659ca7ef8e067daddb2d51c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block billing@4 managed
-- @bsb-hash sha256:1de7a1e1ecf86fdb159290158fcfaff04caf2a766677d59ca1f6879279fa3383
-- Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset. A tenant billed
-- as a Stripe Accounts v2 account has its acct_ id first; Stripe creates the
-- linked cus_ id at the first checkout, and the webhook records it.
create table "better_supabase"."billing_customers" (
  "tenant_id" uuid primary key,
  "stripe_customer_id" text unique constraint bsb_billing_customers_stripe_customer_id_check check ("stripe_customer_id" ~ '^cus_'),
  "stripe_customer_account_id" text unique constraint bsb_billing_customers_stripe_customer_account_id_check check ("stripe_customer_account_id" ~ '^acct_'),
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."billing_customers" alter column "stripe_customer_id" drop not null;
alter table "better_supabase"."billing_customers" add constraint bsb_billing_customers_party check ("stripe_customer_id" is not null or "stripe_customer_account_id" is not null);
alter table "better_supabase"."billing_customers" enable row level security;
revoke all on "better_supabase"."billing_customers" from public, anon, authenticated;
grant select on "better_supabase"."billing_customers" to authenticated;
grant all on "better_supabase"."billing_customers" to service_role;
alter table "better_supabase"."billing_customers" add constraint "billing_customers_tenant_fkey"
  foreign key ("tenant_id") references "better_supabase"."organizations" ("id") on delete cascade;
create policy bsb_billing_customers_read on "better_supabase"."billing_customers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')));

create or replace function "better_supabase"."billing_customer"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_id" from "better_supabase"."billing_customers" b
  where b."tenant_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
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
  where b."tenant_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$$;

-- The tenant of a customer (cus_) or an account (acct_).
create or replace function "better_supabase"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b."tenant_id" from "better_supabase"."billing_customers" b
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_id")
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict ("tenant_id") do update set "stripe_customer_id" = excluded."stripe_customer_id"
    where b."stripe_customer_id" is null;
  if found then
    perform "better_supabase".emit_event('billing.customer_linked', jsonb_build_object('organizationId', link_billing_customer.tenant::text, 'customerId', link_billing_customer.customer), 'organizations/' || link_billing_customer.tenant::text, (link_billing_customer.tenant)::text, 'billing.customer_linked:' || link_billing_customer.tenant::text, 'better-supabase/billing');
  perform better_supabase.audit_event(
    event_type => 'billing.customer_linked',
    category => 'billing',
    target_type => 'billing_customer',
    record_id => link_billing_customer.customer,
    tenant => (link_billing_customer.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', link_billing_customer.tenant::text, 'customerId', link_billing_customer.customer),
    idempotency_key => 'billing.customer_linked:' || link_billing_customer.tenant::text
  );
  end if;
  return (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_customer.tenant);
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_account_id")
  values (link_billing_account.tenant, link_billing_account.account)
  on conflict ("tenant_id") do update set "stripe_customer_account_id" = excluded."stripe_customer_account_id"
    where b."stripe_customer_account_id" is null;
  if found then
    perform "better_supabase".emit_event('billing.account_linked', jsonb_build_object('organizationId', link_billing_account.tenant::text, 'accountId', link_billing_account.account), 'organizations/' || link_billing_account.tenant::text, (link_billing_account.tenant)::text, 'billing.account_linked:' || link_billing_account.tenant::text, 'better-supabase/billing');
  perform better_supabase.audit_event(
    event_type => 'billing.account_linked',
    category => 'billing',
    target_type => 'billing_customer',
    record_id => link_billing_account.account,
    tenant => (link_billing_account.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', link_billing_account.tenant::text, 'accountId', link_billing_account.account),
    idempotency_key => 'billing.account_linked:' || link_billing_account.tenant::text
  );
  end if;
  return (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_account.tenant);
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
  where m."organization_id" = billing_seat_count.tenant
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_subscription_item.tenant);
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
      select distinct on (b."tenant_id") b."tenant_id" as tenant, b."stripe_customer_id"::text as customer,
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
      order by b."tenant_id", (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) desc nulls last
    ) r
  $q$, items, prices, customers);
end;
$$;
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
    select b."tenant_id", b."stripe_customer_id"::text, v.id::text,
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
    select b."tenant_id", b."stripe_customer_id"::text,
      cu.customer_row ->> 'email', cu.customer_row ->> 'name',
      (case jsonb_typeof(cu.customer_row -> 'created') when 'number' then to_timestamp((cu.customer_row -> 'created')::text::double precision) when 'string' then (cu.customer_row -> 'created' #>> '{}')::timestamptz end)
    from "better_supabase"."billing_customers" b
    %s
    where b."stripe_customer_id" is not null
    order by b."tenant_id"
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_stripe_rows.tenant);
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_tenant_subscription.tenant);
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
        select distinct on (b."tenant_id") b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from "better_supabase"."billing_customers" b
        join stripe.subscriptions s on s.customer = b."stripe_customer_id"
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b."tenant_id", s.created desc nulls last
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
      select b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, x.created, to_jsonb(x.*) as invoice
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
    'customer', (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
    'account', (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
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

-- The billing page in one call. It runs as the caller and reads through the
-- status, invoice and usage functions, which check billing and usage reads.
create or replace function "better_supabase"."billing_overview"(tenant uuid, invoice_limit integer default 10)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status jsonb := "better_supabase"."billing_status"(billing_overview.tenant);
begin
  return jsonb_build_object(
    'customerId', v_status -> 'customer',
    'accountId', v_status -> 'account',
    'seats', coalesce((v_status ->> 'seats')::integer, 0),
    'subscription', coalesce(v_status -> 'subscription', 'null'::jsonb),
    'invoices', coalesce("better_supabase"."billing_invoices"(billing_overview.tenant, billing_overview.invoice_limit), '[]'::jsonb),
    'usage', coalesce("better_supabase"."usage_overview"(billing_overview.tenant), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."billing_overview"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."billing_overview"(uuid, integer) to authenticated, service_role;

-- A subscription kept in Postgres: unit_amount is the price of one unit for one
-- billing_interval in minor units of currency, and [period_start, period_end)
-- is the current period.
create table "better_supabase"."billing_native_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan" text not null constraint bsb_billing_native_subscriptions_plan_check check (length("plan") >= 1 and length("plan") <= 100),
  "currency" text not null constraint bsb_billing_native_subscriptions_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "unit_amount" bigint not null constraint bsb_billing_native_subscriptions_unit_amount_check check ("unit_amount" >= 0),
  "quantity" integer not null default 1 constraint bsb_billing_native_subscriptions_quantity_check check ("quantity" >= 0),
  "billing_interval" text not null default 'month',
  "status" text not null default 'active' constraint bsb_billing_native_subscriptions_status_check check ("status" in ('active', 'canceled')),
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "canceled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint "bsb_billing_native_subscriptions_interval_check" check ("billing_interval" in ('week', 'month', 'year')),
  constraint bsb_billing_native_subscriptions_check check ("period_end" > "period_start")
);
create index "billing_native_subscriptions_tenant_idx" on "better_supabase"."billing_native_subscriptions" ("tenant_id", "status");
alter table "better_supabase"."billing_native_subscriptions" enable row level security;
revoke all on "better_supabase"."billing_native_subscriptions" from public, anon, authenticated;
grant all on "better_supabase"."billing_native_subscriptions" to service_role;

-- Starts a subscription for tenant; its first period begins at started_at
-- (now by default). Service role only.
create or replace function "better_supabase"."create_native_subscription"(tenant uuid, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role creates native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  insert into "better_supabase"."billing_native_subscriptions" ("tenant_id", "plan", "currency", "unit_amount", "quantity", "billing_interval", "period_start", "period_end")
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'plan', v_row."plan", 'currency', v_row."currency",
    'unit_amount', v_row."unit_amount"::text, 'quantity', v_row."quantity", 'interval', v_row."billing_interval",
    'period_start', v_row."period_start", 'period_end', v_row."period_end");
exception when check_violation or invalid_text_representation then
  raise exception 'The subscription is invalid' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
end;
$$;

-- Changes the price or the quantity of a subscription at an instant inside its
-- current period and returns what the change adds: credit is the unused part
-- of the old price, charge the remaining part of the new one, and net is
-- charge minus credit (negative for a downgrade). With the ledger block the
-- net posts as one transaction (receivable against proration revenue), once
-- per subscription and instant. Service role only.
create or replace function "better_supabase"."prorate_change"(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_end" - v_at) / extract(epoch from v_row."period_end" - v_row."period_start")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  if v_net <> 0 then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'billing.proration',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable', 'billing:receivable:' || v_row."currency", 'Subscription receivable ' || v_row."currency", v_row."currency", 0::smallint, null, null, null, true, null, 'billing', null), 'amount', v_net),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'revenue', 'billing:proration:' || v_row."currency", 'Subscription proration ' || v_row."currency", v_row."currency", 0::smallint, null, null, null, true, null, 'billing', null), 'amount', -v_net)),
      'billing-native-subscriptions', v_row."id"::text,
      'Proration for ' || v_row."plan",
      'billing.proration:' || v_row."id"::text || ':' || extract(epoch from v_at)::text,
      v_at,
      jsonb_build_object('plan', v_row."plan", 'credit', v_credit, 'charge', v_charge));
  end if;
  update "better_supabase"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$$;

-- Cancels a subscription. Service role only.
create or replace function "better_supabase"."cancel_native_subscription"(subscription_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role cancels native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  update "better_supabase"."billing_native_subscriptions" set "status" = 'canceled', "canceled_at" = now()
    where "id" = cancel_native_subscription.subscription_id and "status" = 'active';
  return found;
end;
$$;
revoke execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) to service_role;
revoke execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) to service_role;
revoke execute on function "better_supabase"."cancel_native_subscription"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."cancel_native_subscription"(uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."billing_customers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."billing_customers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."billing_customers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."billing_customers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:9192c5a247a10a63b3db4a9a5d145a27c1a3ad52659ca7ef8e067daddb2d51c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block billing@4 managed
-- @bsb-hash sha256:f5878e5020ee93ead4409d3c2870a59e62dcba0999db52fad367c195967988b3
-- Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset. A tenant billed
-- as a Stripe Accounts v2 account has its acct_ id first; Stripe creates the
-- linked cus_ id at the first checkout, and the webhook records it.
create table "app_private"."billing_customers" (
  "tenant_id" uuid primary key,
  "stripe_customer_id" text unique constraint bsb_billing_customers_stripe_customer_id_check check ("stripe_customer_id" ~ '^cus_'),
  "stripe_customer_account_id" text unique constraint bsb_billing_customers_stripe_customer_account_id_check check ("stripe_customer_account_id" ~ '^acct_'),
  "created_at" timestamptz not null default now()
);
alter table "app_private"."billing_customers" alter column "stripe_customer_id" drop not null;
alter table "app_private"."billing_customers" add constraint bsb_billing_customers_party check ("stripe_customer_id" is not null or "stripe_customer_account_id" is not null);
alter table "app_private"."billing_customers" enable row level security;
revoke all on "app_private"."billing_customers" from public, anon, authenticated;
grant select on "app_private"."billing_customers" to authenticated;
grant all on "app_private"."billing_customers" to service_role;
create policy bsb_billing_customers_read on "app_private"."billing_customers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')));

create or replace function "app_private"."billing_customer"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_id" from "app_private"."billing_customers" b
  where b."tenant_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
$$;

-- The tenant's Stripe Accounts v2 account (acct_), when it is billed as one.
create or replace function "app_private"."billing_account"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_account_id" from "app_private"."billing_customers" b
  where b."tenant_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$$;

-- The tenant of a customer (cus_) or an account (acct_).
create or replace function "app_private"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b."tenant_id" from "app_private"."billing_customers" b
  where b."stripe_customer_id" = billing_customer_tenant.customer
    or b."stripe_customer_account_id" = billing_customer_tenant.customer
$$;

-- Links tenant to customer once, or records the customer Stripe created for
-- the tenant's account. Returns the customer that is linked, which is the
-- earlier one when two checkouts raced.
create or replace function "app_private"."link_billing_customer"(tenant uuid, customer text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into "app_private"."billing_customers" as b ("tenant_id", "stripe_customer_id")
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict ("tenant_id") do update set "stripe_customer_id" = excluded."stripe_customer_id"
    where b."stripe_customer_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_id" from "app_private"."billing_customers" b where b."tenant_id" = link_billing_customer.tenant);
end;
$$;

-- Links tenant to a Stripe Accounts v2 account once. Returns the account that
-- is linked, which is the earlier one when two calls raced.
create or replace function "app_private"."link_billing_account"(tenant uuid, account text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into "app_private"."billing_customers" as b ("tenant_id", "stripe_customer_account_id")
  values (link_billing_account.tenant, link_billing_account.account)
  on conflict ("tenant_id") do update set "stripe_customer_account_id" = excluded."stripe_customer_account_id"
    where b."stripe_customer_account_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_account_id" from "app_private"."billing_customers" b where b."tenant_id" = link_billing_account.tenant);
end;
$$;

-- Members who take a seat.
create or replace function "app_private"."billing_seat_count"(tenant uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from "better_supabase"."memberships" m
  where m."organization_id" = billing_seat_count.tenant
$$;

-- The tenant's active subscription item for price (or its first item), from
-- the Stripe Sync Engine's stripe schema: { subscription, item, price,
-- quantity, status }, or null.
create or replace function "app_private"."billing_subscription_item"(tenant uuid, price text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b."stripe_customer_id" from "app_private"."billing_customers" b where b."tenant_id" = billing_subscription_item.tenant);
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

create or replace function "app_private"."billing_plan_price"(plan text, billing_interval text default null, variant text default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select null::text
$$;
revoke execute on function "app_private"."billing_plan_price"(text, text, text) from public, anon;
grant execute on function "app_private"."billing_plan_price"(text, text, text) to authenticated, service_role;
create or replace function "app_private"."billing_platform_subscriptions"()
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
      select distinct on (b."tenant_id") b."tenant_id" as tenant, b."stripe_customer_id"::text as customer,
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
      from "app_private"."billing_customers" b
      join stripe.subscriptions s on s.customer = b."stripe_customer_id"
      cross join lateral (select to_jsonb(s.*) as row) x
      %s
      %s
      %s
      order by b."tenant_id", (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) desc nulls last
    ) r
  $q$, items, prices, customers);
end;
$$;
create or replace function "app_private"."billing_platform_invoices"()
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
    select b."tenant_id", b."stripe_customer_id"::text, v.id::text,
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
    from "app_private"."billing_customers" b
    join stripe.invoices v on v.customer = b."stripe_customer_id"
    cross join lateral (select to_jsonb(v.*) as row) x
    %s
  $q$, customers);
end;
$$;
-- Every linked customer, with or without a subscription or invoice, for
-- platform staff: the tenant, the Stripe customer and its contact from the
-- Sync Engine's stripe.customers (null without the table).
create or replace function "app_private"."billing_platform_customers"()
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
    select b."tenant_id", b."stripe_customer_id"::text,
      cu.customer_row ->> 'email', cu.customer_row ->> 'name',
      (case jsonb_typeof(cu.customer_row -> 'created') when 'number' then to_timestamp((cu.customer_row -> 'created')::text::double precision) when 'string' then (cu.customer_row -> 'created' #>> '{}')::timestamptz end)
    from "app_private"."billing_customers" b
    %s
    where b."stripe_customer_id" is not null
    order by b."tenant_id"
  $q$, customers);
end;
$$;

-- billing_platform_customers as jsonb, for createBilling().allCustomers().
create or replace function "app_private"."billing_all_customers"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(c.*) order by c.tenant), '[]'::jsonb)
  from "app_private"."billing_platform_customers"() c
$$;
revoke execute on function "app_private"."billing_platform_customers"() from public, anon;
grant execute on function "app_private"."billing_platform_customers"() to authenticated, service_role;
revoke execute on function "app_private"."billing_all_customers"() from public, anon;
grant execute on function "app_private"."billing_all_customers"() to authenticated, service_role;
revoke execute on function "app_private"."billing_platform_subscriptions"() from public, anon;
grant execute on function "app_private"."billing_platform_subscriptions"() to authenticated, service_role;
revoke execute on function "app_private"."billing_platform_invoices"() from public, anon;
grant execute on function "app_private"."billing_platform_invoices"() to authenticated, service_role;

-- Rows of a Stripe Sync Engine table for the tenant's customer, newest
-- first, or [] when the table doesn't exist. Reads need billing.read in the
-- tenant, or platform staff.
create or replace function "app_private"."billing_stripe_rows"(tenant uuid, source text, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b."stripe_customer_id" from "app_private"."billing_customers" b where b."tenant_id" = billing_stripe_rows.tenant);
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

create or replace function "app_private"."billing_invoices"(tenant uuid, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "app_private"."billing_stripe_rows"(billing_invoices.tenant, 'invoices', billing_invoices.max_rows)
$$;

create or replace function "app_private"."billing_payment_methods"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "app_private"."billing_stripe_rows"(billing_payment_methods.tenant, 'payment_methods', 50)
$$;

-- The customer's contact details as Stripe holds them (email, name,
-- address, phone): Stripe is the record for the billing contact.
create or replace function "app_private"."billing_customer_details"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "app_private"."billing_stripe_rows"(billing_customer_details.tenant, 'customers', 1) -> 0
$$;

-- The customer's tax ids from the Sync Engine's stripe.tax_ids, newest
-- first: [{ id, type, value, country, verification: { status } | null,
-- created }], the shape of Stripe's tax id objects; [] without the table.
create or replace function "app_private"."billing_tax_ids"(tenant uuid)
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
  from jsonb_array_elements("app_private"."billing_stripe_rows"(billing_tax_ids.tenant, 'tax_ids', 100)) with ordinality as r(t, ord)
$$;

-- The tenant's newest subscription as the Sync Engine stores it, with its
-- items, or null, without checking the caller: for the app's own security
-- definer functions (resolving a member's plan), executable by its owner only.
create or replace function "app_private"."billing_tenant_subscription"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b."stripe_customer_id" from "app_private"."billing_customers" b where b."tenant_id" = billing_tenant_subscription.tenant);
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
create or replace function "app_private"."billing_subscription"(tenant uuid)
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
  return "app_private"."billing_tenant_subscription"(billing_subscription.tenant);
end;
$$;

-- Every tenant's newest subscription, for platform staff: [{ tenant,
-- customer, subscription }], newest first, of one status when given, and
-- created before before_created (Stripe's epoch seconds) for the next page.
create or replace function "app_private"."billing_all_subscriptions"(for_status text default null, max_rows integer default 100, before_created bigint default null)
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
        select distinct on (b."tenant_id") b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from "app_private"."billing_customers" b
        join stripe.subscriptions s on s.customer = b."stripe_customer_id"
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b."tenant_id", s.created desc nulls last
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
create or replace function "app_private"."billing_all_invoices"(for_status text default null, max_rows integer default 100, before_created bigint default null)
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
      select b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, x.created, to_jsonb(x.*) as invoice
      from "app_private"."billing_customers" b
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
create or replace function "app_private"."billing_status"(tenant uuid)
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
    'customer', (select b."stripe_customer_id" from "app_private"."billing_customers" b where b."tenant_id" = billing_status.tenant),
    'account', (select b."stripe_customer_account_id" from "app_private"."billing_customers" b where b."tenant_id" = billing_status.tenant),
    'seats', "app_private"."billing_seat_count"(tenant),
    'subscription', "app_private"."billing_subscription_item"(tenant)
  );
end;
$$;


revoke execute on function "app_private"."billing_stripe_rows"(uuid, text, integer) from public, anon;
revoke execute on function "app_private"."billing_invoices"(uuid, integer) from public, anon;
revoke execute on function "app_private"."billing_payment_methods"(uuid) from public, anon;
revoke execute on function "app_private"."billing_customer_details"(uuid) from public, anon;
revoke execute on function "app_private"."billing_tax_ids"(uuid) from public, anon;
grant execute on function "app_private"."billing_stripe_rows"(uuid, text, integer) to authenticated, service_role;
grant execute on function "app_private"."billing_invoices"(uuid, integer) to authenticated, service_role;
grant execute on function "app_private"."billing_payment_methods"(uuid) to authenticated, service_role;
grant execute on function "app_private"."billing_customer_details"(uuid) to authenticated, service_role;
grant execute on function "app_private"."billing_tax_ids"(uuid) to authenticated, service_role;
revoke execute on function "app_private"."billing_customer"(uuid) from public, anon;
revoke execute on function "app_private"."billing_account"(uuid) from public, anon;
revoke execute on function "app_private"."link_billing_account"(uuid, text) from public, anon, authenticated;
revoke execute on function "app_private"."billing_customer_tenant"(text) from public, anon, authenticated;
revoke execute on function "app_private"."link_billing_customer"(uuid, text) from public, anon, authenticated;
revoke execute on function "app_private"."billing_seat_count"(uuid) from public, anon, authenticated;
revoke execute on function "app_private"."billing_subscription_item"(uuid, text) from public, anon, authenticated;
revoke execute on function "app_private"."billing_status"(uuid) from public, anon;
revoke execute on function "app_private"."billing_subscription"(uuid) from public, anon;
revoke execute on function "app_private"."billing_tenant_subscription"(uuid) from public, anon, authenticated, service_role;
revoke execute on function "app_private"."billing_all_subscriptions"(text, integer, bigint) from public, anon;
revoke execute on function "app_private"."billing_all_invoices"(text, integer, bigint) from public, anon;
grant execute on function "app_private"."billing_all_invoices"(text, integer, bigint) to authenticated, service_role;
grant execute on function "app_private"."billing_subscription"(uuid) to authenticated, service_role;
grant execute on function "app_private"."billing_all_subscriptions"(text, integer, bigint) to authenticated, service_role;
grant execute on function "app_private"."billing_customer"(uuid) to authenticated, service_role;
grant execute on function "app_private"."billing_account"(uuid) to authenticated, service_role;
grant execute on function "app_private"."link_billing_account"(uuid, text) to service_role;
grant execute on function "app_private"."billing_customer_tenant"(text) to service_role;
grant execute on function "app_private"."link_billing_customer"(uuid, text) to service_role;
grant execute on function "app_private"."billing_seat_count"(uuid) to service_role;
grant execute on function "app_private"."billing_subscription_item"(uuid, text) to service_role;
grant execute on function "app_private"."billing_status"(uuid) to authenticated, service_role;

-- The billing page in one call. It runs as the caller and reads through the
-- status, invoice and usage functions, which check billing and usage reads.
create or replace function "app_private"."billing_overview"(tenant uuid, invoice_limit integer default 10)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status jsonb := "app_private"."billing_status"(billing_overview.tenant);
begin
  return jsonb_build_object(
    'customerId', v_status -> 'customer',
    'accountId', v_status -> 'account',
    'seats', coalesce((v_status ->> 'seats')::integer, 0),
    'subscription', coalesce(v_status -> 'subscription', 'null'::jsonb),
    'invoices', coalesce("app_private"."billing_invoices"(billing_overview.tenant, billing_overview.invoice_limit), '[]'::jsonb),
    'usage', coalesce('[]'::jsonb, '[]'::jsonb)
  );
end;
$$;
revoke execute on function "app_private"."billing_overview"(uuid, integer) from public, anon;
grant execute on function "app_private"."billing_overview"(uuid, integer) to authenticated, service_role;

-- A subscription kept in Postgres: unit_amount is the price of one unit for one
-- billing_interval in minor units of currency, and [period_start, period_end)
-- is the current period.
create table "app_private"."billing_native_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan" text not null constraint bsb_billing_native_subscriptions_plan_check check (length("plan") >= 1 and length("plan") <= 100),
  "currency" text not null constraint bsb_billing_native_subscriptions_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "unit_amount" bigint not null constraint bsb_billing_native_subscriptions_unit_amount_check check ("unit_amount" >= 0),
  "quantity" integer not null default 1 constraint bsb_billing_native_subscriptions_quantity_check check ("quantity" >= 0),
  "billing_interval" text not null default 'month',
  "status" text not null default 'active' constraint bsb_billing_native_subscriptions_status_check check ("status" in ('active', 'canceled')),
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "canceled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint "bsb_billing_native_subscriptions_interval_check" check ("billing_interval" in ('week', 'month', 'year')),
  constraint bsb_billing_native_subscriptions_check check ("period_end" > "period_start")
);
create index "billing_native_subscriptions_tenant_idx" on "app_private"."billing_native_subscriptions" ("tenant_id", "status");
alter table "app_private"."billing_native_subscriptions" enable row level security;
revoke all on "app_private"."billing_native_subscriptions" from public, anon, authenticated;
grant all on "app_private"."billing_native_subscriptions" to service_role;

-- Starts a subscription for tenant; its first period begins at started_at
-- (now by default). Service role only.
create or replace function "app_private"."create_native_subscription"(tenant uuid, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row "app_private"."billing_native_subscriptions"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role creates native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  insert into "app_private"."billing_native_subscriptions" ("tenant_id", "plan", "currency", "unit_amount", "quantity", "billing_interval", "period_start", "period_end")
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'plan', v_row."plan", 'currency', v_row."currency",
    'unit_amount', v_row."unit_amount"::text, 'quantity', v_row."quantity", 'interval', v_row."billing_interval",
    'period_start', v_row."period_start", 'period_end', v_row."period_end");
exception when check_violation or invalid_text_representation then
  raise exception 'The subscription is invalid' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
end;
$$;

-- Changes the price or the quantity of a subscription at an instant inside its
-- current period and returns what the change adds: credit is the unused part
-- of the old price, charge the remaining part of the new one, and net is
-- charge minus credit (negative for a downgrade). With the ledger block the
-- net posts as one transaction (receivable against proration revenue), once
-- per subscription and instant. Service role only.
create or replace function "app_private"."prorate_change"(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_end" - v_at) / extract(epoch from v_row."period_end" - v_row."period_start")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  update "app_private"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$$;

-- Cancels a subscription. Service role only.
create or replace function "app_private"."cancel_native_subscription"(subscription_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role cancels native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  update "app_private"."billing_native_subscriptions" set "status" = 'canceled', "canceled_at" = now()
    where "id" = cancel_native_subscription.subscription_id and "status" = 'active';
  return found;
end;
$$;
revoke execute on function "app_private"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) to service_role;
revoke execute on function "app_private"."prorate_change"(uuid, bigint, integer, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."prorate_change"(uuid, bigint, integer, timestamptz) to service_role;
revoke execute on function "app_private"."cancel_native_subscription"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."cancel_native_subscription"(uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."billing_customers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."billing_customers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."billing_customers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."billing_customers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:9192c5a247a10a63b3db4a9a5d145a27c1a3ad52659ca7ef8e067daddb2d51c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block billing@4 managed
-- @bsb-hash sha256:448746335a21ea7f0cfcc0a7ff050448da5cd5a1112ee8f026b200cf0a51515c
-- Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset. A tenant billed
-- as a Stripe Accounts v2 account has its acct_ id first; Stripe creates the
-- linked cus_ id at the first checkout, and the webhook records it.
create table "better_supabase"."billing_customers" (
  "tenant_id" uuid primary key,
  "stripe_customer_id" text unique constraint bsb_billing_customers_stripe_customer_id_check check ("stripe_customer_id" ~ '^cus_'),
  "stripe_customer_account_id" text unique constraint bsb_billing_customers_stripe_customer_account_id_check check ("stripe_customer_account_id" ~ '^acct_'),
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."billing_customers" alter column "stripe_customer_id" drop not null;
alter table "better_supabase"."billing_customers" add constraint bsb_billing_customers_party check ("stripe_customer_id" is not null or "stripe_customer_account_id" is not null);
alter table "better_supabase"."billing_customers" enable row level security;
revoke all on "better_supabase"."billing_customers" from public, anon, authenticated;
grant select on "better_supabase"."billing_customers" to authenticated;
grant all on "better_supabase"."billing_customers" to service_role;
create policy bsb_billing_customers_read on "better_supabase"."billing_customers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')));

create or replace function "better_supabase"."billing_customer"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_id" from "better_supabase"."billing_customers" b
  where b."tenant_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
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
  where b."tenant_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$$;

-- The tenant of a customer (cus_) or an account (acct_).
create or replace function "better_supabase"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b."tenant_id" from "better_supabase"."billing_customers" b
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_id")
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict ("tenant_id") do update set "stripe_customer_id" = excluded."stripe_customer_id"
    where b."stripe_customer_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_customer.tenant);
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_account_id")
  values (link_billing_account.tenant, link_billing_account.account)
  on conflict ("tenant_id") do update set "stripe_customer_account_id" = excluded."stripe_customer_account_id"
    where b."stripe_customer_account_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_account.tenant);
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
  where m."organization_id" = billing_seat_count.tenant
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_subscription_item.tenant);
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
      select distinct on (b."tenant_id") b."tenant_id" as tenant, b."stripe_customer_id"::text as customer,
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
      order by b."tenant_id", (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) desc nulls last
    ) r
  $q$, items, prices, customers);
end;
$$;
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
    select b."tenant_id", b."stripe_customer_id"::text, v.id::text,
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
    select b."tenant_id", b."stripe_customer_id"::text,
      cu.customer_row ->> 'email', cu.customer_row ->> 'name',
      (case jsonb_typeof(cu.customer_row -> 'created') when 'number' then to_timestamp((cu.customer_row -> 'created')::text::double precision) when 'string' then (cu.customer_row -> 'created' #>> '{}')::timestamptz end)
    from "better_supabase"."billing_customers" b
    %s
    where b."stripe_customer_id" is not null
    order by b."tenant_id"
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_stripe_rows.tenant);
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_tenant_subscription.tenant);
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
        select distinct on (b."tenant_id") b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from "better_supabase"."billing_customers" b
        join stripe.subscriptions s on s.customer = b."stripe_customer_id"
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b."tenant_id", s.created desc nulls last
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
      select b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, x.created, to_jsonb(x.*) as invoice
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
    'customer', (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
    'account', (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
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

-- The billing page in one call. It runs as the caller and reads through the
-- status, invoice and usage functions, which check billing and usage reads.
create or replace function "better_supabase"."billing_overview"(tenant uuid, invoice_limit integer default 10)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status jsonb := "better_supabase"."billing_status"(billing_overview.tenant);
begin
  return jsonb_build_object(
    'customerId', v_status -> 'customer',
    'accountId', v_status -> 'account',
    'seats', coalesce((v_status ->> 'seats')::integer, 0),
    'subscription', coalesce(v_status -> 'subscription', 'null'::jsonb),
    'invoices', coalesce("better_supabase"."billing_invoices"(billing_overview.tenant, billing_overview.invoice_limit), '[]'::jsonb),
    'usage', coalesce('[]'::jsonb, '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."billing_overview"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."billing_overview"(uuid, integer) to authenticated, service_role;

-- A subscription kept in Postgres: unit_amount is the price of one unit for one
-- billing_interval in minor units of currency, and [period_start, period_end)
-- is the current period.
create table "better_supabase"."billing_native_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "plan" text not null constraint bsb_billing_native_subscriptions_plan_check check (length("plan") >= 1 and length("plan") <= 100),
  "currency" text not null constraint bsb_billing_native_subscriptions_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "unit_amount" bigint not null constraint bsb_billing_native_subscriptions_unit_amount_check check ("unit_amount" >= 0),
  "quantity" integer not null default 1 constraint bsb_billing_native_subscriptions_quantity_check check ("quantity" >= 0),
  "billing_interval" text not null default 'month',
  "status" text not null default 'active' constraint bsb_billing_native_subscriptions_status_check check ("status" in ('active', 'canceled')),
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "canceled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint "bsb_billing_native_subscriptions_interval_check" check ("billing_interval" in ('week', 'month', 'year')),
  constraint bsb_billing_native_subscriptions_check check ("period_end" > "period_start")
);
create index "billing_native_subscriptions_tenant_idx" on "better_supabase"."billing_native_subscriptions" ("tenant_id", "status");
alter table "better_supabase"."billing_native_subscriptions" enable row level security;
revoke all on "better_supabase"."billing_native_subscriptions" from public, anon, authenticated;
grant all on "better_supabase"."billing_native_subscriptions" to service_role;

-- Starts a subscription for tenant; its first period begins at started_at
-- (now by default). Service role only.
create or replace function "better_supabase"."create_native_subscription"(tenant uuid, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role creates native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  insert into "better_supabase"."billing_native_subscriptions" ("tenant_id", "plan", "currency", "unit_amount", "quantity", "billing_interval", "period_start", "period_end")
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'plan', v_row."plan", 'currency', v_row."currency",
    'unit_amount', v_row."unit_amount"::text, 'quantity', v_row."quantity", 'interval', v_row."billing_interval",
    'period_start', v_row."period_start", 'period_end', v_row."period_end");
exception when check_violation or invalid_text_representation then
  raise exception 'The subscription is invalid' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
end;
$$;

-- Changes the price or the quantity of a subscription at an instant inside its
-- current period and returns what the change adds: credit is the unused part
-- of the old price, charge the remaining part of the new one, and net is
-- charge minus credit (negative for a downgrade). With the ledger block the
-- net posts as one transaction (receivable against proration revenue), once
-- per subscription and instant. Service role only.
create or replace function "better_supabase"."prorate_change"(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_end" - v_at) / extract(epoch from v_row."period_end" - v_row."period_start")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  update "better_supabase"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$$;

-- Cancels a subscription. Service role only.
create or replace function "better_supabase"."cancel_native_subscription"(subscription_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role cancels native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  update "better_supabase"."billing_native_subscriptions" set "status" = 'canceled', "canceled_at" = now()
    where "id" = cancel_native_subscription.subscription_id and "status" = 'active';
  return found;
end;
$$;
revoke execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) to service_role;
revoke execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) to service_role;
revoke execute on function "better_supabase"."cancel_native_subscription"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."cancel_native_subscription"(uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."billing_customers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."billing_customers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."billing_customers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."billing_customers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.billing.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."billing_plan_price"(plan text, billing_interval text default null, variant text default null)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_plan_price"($1, $2, $3) $$;
revoke execute on function "api"."billing_plan_price"(text, text, text) from public, anon;
grant execute on function "api"."billing_plan_price"(text, text, text) to authenticated, service_role;

create or replace function "api"."billing_platform_customers"()
returns table (
  tenant uuid,
  customer text,
  email text,
  name text,
  created timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."billing_platform_customers"() $$;
revoke execute on function "api"."billing_platform_customers"() from public, anon;
grant execute on function "api"."billing_platform_customers"() to authenticated, service_role;

create or replace function "api"."billing_all_customers"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_all_customers"() $$;
revoke execute on function "api"."billing_all_customers"() from public, anon;
grant execute on function "api"."billing_all_customers"() to authenticated, service_role;

create or replace function "api"."billing_platform_subscriptions"()
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
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."billing_platform_subscriptions"() $$;
revoke execute on function "api"."billing_platform_subscriptions"() from public, anon;
grant execute on function "api"."billing_platform_subscriptions"() to authenticated, service_role;

create or replace function "api"."billing_platform_invoices"()
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
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."billing_platform_invoices"() $$;
revoke execute on function "api"."billing_platform_invoices"() from public, anon;
grant execute on function "api"."billing_platform_invoices"() to authenticated, service_role;

create or replace function "api"."billing_stripe_rows"(tenant uuid, source text, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_stripe_rows"($1, $2, $3) $$;
revoke execute on function "api"."billing_stripe_rows"(uuid, text, integer) from public, anon;
grant execute on function "api"."billing_stripe_rows"(uuid, text, integer) to authenticated, service_role;

create or replace function "api"."billing_invoices"(tenant uuid, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_invoices"($1, $2) $$;
revoke execute on function "api"."billing_invoices"(uuid, integer) from public, anon;
grant execute on function "api"."billing_invoices"(uuid, integer) to authenticated, service_role;

create or replace function "api"."billing_payment_methods"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_payment_methods"($1) $$;
revoke execute on function "api"."billing_payment_methods"(uuid) from public, anon;
grant execute on function "api"."billing_payment_methods"(uuid) to authenticated, service_role;

create or replace function "api"."billing_customer_details"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_customer_details"($1) $$;
revoke execute on function "api"."billing_customer_details"(uuid) from public, anon;
grant execute on function "api"."billing_customer_details"(uuid) to authenticated, service_role;

create or replace function "api"."billing_tax_ids"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_tax_ids"($1) $$;
revoke execute on function "api"."billing_tax_ids"(uuid) from public, anon;
grant execute on function "api"."billing_tax_ids"(uuid) to authenticated, service_role;

create or replace function "api"."billing_all_invoices"(for_status text default null, max_rows integer default 100, before_created bigint default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_all_invoices"($1, $2, $3) $$;
revoke execute on function "api"."billing_all_invoices"(text, integer, bigint) from public, anon;
grant execute on function "api"."billing_all_invoices"(text, integer, bigint) to authenticated, service_role;

create or replace function "api"."billing_subscription"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_subscription"($1) $$;
revoke execute on function "api"."billing_subscription"(uuid) from public, anon;
grant execute on function "api"."billing_subscription"(uuid) to authenticated, service_role;

create or replace function "api"."billing_all_subscriptions"(for_status text default null, max_rows integer default 100, before_created bigint default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_all_subscriptions"($1, $2, $3) $$;
revoke execute on function "api"."billing_all_subscriptions"(text, integer, bigint) from public, anon;
grant execute on function "api"."billing_all_subscriptions"(text, integer, bigint) to authenticated, service_role;

create or replace function "api"."billing_customer"(tenant uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_customer"($1) $$;
revoke execute on function "api"."billing_customer"(uuid) from public, anon;
grant execute on function "api"."billing_customer"(uuid) to authenticated, service_role;

create or replace function "api"."billing_account"(tenant uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_account"($1) $$;
revoke execute on function "api"."billing_account"(uuid) from public, anon;
grant execute on function "api"."billing_account"(uuid) to authenticated, service_role;

create or replace function "api"."link_billing_account"(tenant uuid, account text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_billing_account"($1, $2) $$;
revoke execute on function "api"."link_billing_account"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."link_billing_account"(uuid, text) to service_role;

create or replace function "api"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_customer_tenant"($1) $$;
revoke execute on function "api"."billing_customer_tenant"(text) from public, anon, authenticated;
grant execute on function "api"."billing_customer_tenant"(text) to service_role;

create or replace function "api"."link_billing_customer"(tenant uuid, customer text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_billing_customer"($1, $2) $$;
revoke execute on function "api"."link_billing_customer"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."link_billing_customer"(uuid, text) to service_role;

create or replace function "api"."billing_seat_count"(tenant uuid)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_seat_count"($1) $$;
revoke execute on function "api"."billing_seat_count"(uuid) from public, anon, authenticated;
grant execute on function "api"."billing_seat_count"(uuid) to service_role;

create or replace function "api"."billing_subscription_item"(tenant uuid, price text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_subscription_item"($1, $2) $$;
revoke execute on function "api"."billing_subscription_item"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."billing_subscription_item"(uuid, text) to service_role;

create or replace function "api"."billing_status"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_status"($1) $$;
revoke execute on function "api"."billing_status"(uuid) from public, anon;
grant execute on function "api"."billing_status"(uuid) to authenticated, service_role;

create or replace function "api"."billing_overview"(tenant uuid, invoice_limit integer default 10)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."billing_overview"($1, $2) $$;
revoke execute on function "api"."billing_overview"(uuid, integer) from public, anon;
grant execute on function "api"."billing_overview"(uuid, integer) to authenticated, service_role;

create or replace function "api"."create_native_subscription"(tenant uuid, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_native_subscription"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function "api"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) to service_role;

create or replace function "api"."prorate_change"(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."prorate_change"($1, $2, $3, $4) $$;
revoke execute on function "api"."prorate_change"(uuid, bigint, integer, timestamptz) from public, anon, authenticated;
grant execute on function "api"."prorate_change"(uuid, bigint, integer, timestamptz) to service_role;

create or replace function "api"."cancel_native_subscription"(subscription_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_native_subscription"($1) $$;
revoke execute on function "api"."cancel_native_subscription"(uuid) from public, anon, authenticated;
grant execute on function "api"."cancel_native_subscription"(uuid) to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:9192c5a247a10a63b3db4a9a5d145a27c1a3ad52659ca7ef8e067daddb2d51c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block billing@4 managed
-- @bsb-hash sha256:ac57d61fc42d19a1fe4b60a0d4ba10c8d097ac8b7c85210118c4a633bec0e778
-- Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset. A tenant billed
-- as a Stripe Accounts v2 account has its acct_ id first; Stripe creates the
-- linked cus_ id at the first checkout, and the webhook records it.
-- better_supabase.billing_customers is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."billing_customers" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."billing_customers" add column if not exists "stripe_customer_id" text constraint bsb_billing_customers_stripe_customer_id_check check ("stripe_customer_id" ~ '^cus_');
alter table "better_supabase"."billing_customers" add column if not exists "stripe_customer_account_id" text constraint bsb_billing_customers_stripe_customer_account_id_check check ("stripe_customer_account_id" ~ '^acct_');
alter table "better_supabase"."billing_customers" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_billing_customers_tenant_key" on "better_supabase"."billing_customers" ("tenant_id");
alter table "better_supabase"."billing_customers" enable row level security;
grant select on "better_supabase"."billing_customers" to authenticated;
grant all on "better_supabase"."billing_customers" to service_role;
create policy bsb_billing_customers_select on "better_supabase"."billing_customers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')));

create or replace function "better_supabase"."billing_customer"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_id" from "better_supabase"."billing_customers" b
  where b."tenant_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
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
  where b."tenant_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$$;

-- The tenant of a customer (cus_) or an account (acct_).
create or replace function "better_supabase"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b."tenant_id" from "better_supabase"."billing_customers" b
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_id")
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict ("tenant_id") do update set "stripe_customer_id" = excluded."stripe_customer_id"
    where b."stripe_customer_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_customer.tenant);
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
  insert into "better_supabase"."billing_customers" as b ("tenant_id", "stripe_customer_account_id")
  values (link_billing_account.tenant, link_billing_account.account)
  on conflict ("tenant_id") do update set "stripe_customer_account_id" = excluded."stripe_customer_account_id"
    where b."stripe_customer_account_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = link_billing_account.tenant);
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
  where m."organization_id" = billing_seat_count.tenant
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_subscription_item.tenant);
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
      select distinct on (b."tenant_id") b."tenant_id" as tenant, b."stripe_customer_id"::text as customer,
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
      order by b."tenant_id", (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) desc nulls last
    ) r
  $q$, items, prices, customers);
end;
$$;
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
    select b."tenant_id", b."stripe_customer_id"::text, v.id::text,
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
    select b."tenant_id", b."stripe_customer_id"::text,
      cu.customer_row ->> 'email', cu.customer_row ->> 'name',
      (case jsonb_typeof(cu.customer_row -> 'created') when 'number' then to_timestamp((cu.customer_row -> 'created')::text::double precision) when 'string' then (cu.customer_row -> 'created' #>> '{}')::timestamptz end)
    from "better_supabase"."billing_customers" b
    %s
    where b."stripe_customer_id" is not null
    order by b."tenant_id"
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_stripe_rows.tenant);
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_tenant_subscription.tenant);
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
        select distinct on (b."tenant_id") b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from "better_supabase"."billing_customers" b
        join stripe.subscriptions s on s.customer = b."stripe_customer_id"
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b."tenant_id", s.created desc nulls last
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
      select b."tenant_id"::text as tenant, b."stripe_customer_id" as customer, x.created, to_jsonb(x.*) as invoice
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
    'customer', (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
    'account', (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."tenant_id" = billing_status.tenant),
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

-- The billing page in one call. It runs as the caller and reads through the
-- status, invoice and usage functions, which check billing and usage reads.
create or replace function "better_supabase"."billing_overview"(tenant uuid, invoice_limit integer default 10)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status jsonb := "better_supabase"."billing_status"(billing_overview.tenant);
begin
  return jsonb_build_object(
    'customerId', v_status -> 'customer',
    'accountId', v_status -> 'account',
    'seats', coalesce((v_status ->> 'seats')::integer, 0),
    'subscription', coalesce(v_status -> 'subscription', 'null'::jsonb),
    'invoices', coalesce("better_supabase"."billing_invoices"(billing_overview.tenant, billing_overview.invoice_limit), '[]'::jsonb),
    'usage', coalesce('[]'::jsonb, '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."billing_overview"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."billing_overview"(uuid, integer) to authenticated, service_role;

-- A subscription kept in Postgres: unit_amount is the price of one unit for one
-- billing_interval in minor units of currency, and [period_start, period_end)
-- is the current period.
-- better_supabase.billing_native_subscriptions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "plan" text constraint bsb_billing_native_subscriptions_plan_check check (length("plan") >= 1 and length("plan") <= 100);
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "currency" text constraint bsb_billing_native_subscriptions_currency_check check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "unit_amount" bigint constraint bsb_billing_native_subscriptions_unit_amount_check check ("unit_amount" >= 0);
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "quantity" integer not null default 1 constraint bsb_billing_native_subscriptions_quantity_check check ("quantity" >= 0);
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "billing_interval" text not null default 'month';
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "status" text not null default 'active' constraint bsb_billing_native_subscriptions_status_check check ("status" in ('active', 'canceled'));
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "period_start" timestamptz;
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "period_end" timestamptz;
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "canceled_at" timestamptz;
alter table "better_supabase"."billing_native_subscriptions" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "billing_native_subscriptions_tenant_idx" on "better_supabase"."billing_native_subscriptions" ("tenant_id", "status");
alter table "better_supabase"."billing_native_subscriptions" enable row level security;
grant all on "better_supabase"."billing_native_subscriptions" to service_role;

-- Starts a subscription for tenant; its first period begins at started_at
-- (now by default). Service role only.
create or replace function "better_supabase"."create_native_subscription"(tenant uuid, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role creates native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  insert into "better_supabase"."billing_native_subscriptions" ("tenant_id", "plan", "currency", "unit_amount", "quantity", "billing_interval", "period_start", "period_end")
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'plan', v_row."plan", 'currency', v_row."currency",
    'unit_amount', v_row."unit_amount"::text, 'quantity', v_row."quantity", 'interval', v_row."billing_interval",
    'period_start', v_row."period_start", 'period_end', v_row."period_end");
exception when check_violation or invalid_text_representation then
  raise exception 'The subscription is invalid' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
end;
$$;

-- Changes the price or the quantity of a subscription at an instant inside its
-- current period and returns what the change adds: credit is the unused part
-- of the old price, charge the remaining part of the new one, and net is
-- charge minus credit (negative for a downgrade). With the ledger block the
-- net posts as one transaction (receivable against proration revenue), once
-- per subscription and instant. Service role only.
create or replace function "better_supabase"."prorate_change"(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_end" - v_at) / extract(epoch from v_row."period_end" - v_row."period_start")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  update "better_supabase"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$$;

-- Cancels a subscription. Service role only.
create or replace function "better_supabase"."cancel_native_subscription"(subscription_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role cancels native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  update "better_supabase"."billing_native_subscriptions" set "status" = 'canceled', "canceled_at" = now()
    where "id" = cancel_native_subscription.subscription_id and "status" = 'active';
  return found;
end;
$$;
revoke execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) to service_role;
revoke execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) to service_role;
revoke execute on function "better_supabase"."cancel_native_subscription"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."cancel_native_subscription"(uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."billing_customers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('billing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."billing_customers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."billing_customers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."billing_customers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:9192c5a247a10a63b3db4a9a5d145a27c1a3ad52659ca7ef8e067daddb2d51c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block billing@4 managed
-- @bsb-hash sha256:f5f0e14d53cec74c42a69434229f50bc74c585210b7cf22d9e56c0001220d77d
-- Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset. A tenant billed
-- as a Stripe Accounts v2 account has its acct_ id first; Stripe creates the
-- linked cus_ id at the first checkout, and the webhook records it.
create table "better_supabase"."billing_customers" (
  "org_id" uuid primary key,
  "stripe_customer_id" text unique constraint bsb_billing_customers_stripe_customer_id_check check ("stripe_customer_id" ~ '^cus_'),
  "stripe_customer_account_id" text unique constraint bsb_billing_customers_stripe_customer_account_id_check check ("stripe_customer_account_id" ~ '^acct_'),
  "created_at" timestamptz not null default now()
);
alter table "better_supabase"."billing_customers" alter column "stripe_customer_id" drop not null;
alter table "better_supabase"."billing_customers" add constraint bsb_billing_customers_party check ("stripe_customer_id" is not null or "stripe_customer_account_id" is not null);
alter table "better_supabase"."billing_customers" enable row level security;
revoke all on "better_supabase"."billing_customers" from public, anon, authenticated;
grant select on "better_supabase"."billing_customers" to authenticated;
grant all on "better_supabase"."billing_customers" to service_role;
create policy bsb_billing_customers_read on "better_supabase"."billing_customers"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('billing.read')));

create or replace function "better_supabase"."billing_customer"(tenant uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b."stripe_customer_id" from "better_supabase"."billing_customers" b
  where b."org_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
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
  where b."org_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$$;

-- The tenant of a customer (cus_) or an account (acct_).
create or replace function "better_supabase"."billing_customer_tenant"(customer text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b."org_id" from "better_supabase"."billing_customers" b
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
  insert into "better_supabase"."billing_customers" as b ("org_id", "stripe_customer_id")
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict ("org_id") do update set "stripe_customer_id" = excluded."stripe_customer_id"
    where b."stripe_customer_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."org_id" = link_billing_customer.tenant);
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
  insert into "better_supabase"."billing_customers" as b ("org_id", "stripe_customer_account_id")
  values (link_billing_account.tenant, link_billing_account.account)
  on conflict ("org_id") do update set "stripe_customer_account_id" = excluded."stripe_customer_account_id"
    where b."stripe_customer_account_id" is null;
  if found then
    null;
  end if;
  return (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."org_id" = link_billing_account.tenant);
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
  where m."org_id" = billing_seat_count.tenant
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."org_id" = billing_subscription_item.tenant);
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
      select distinct on (b."org_id") b."org_id" as tenant, b."stripe_customer_id"::text as customer,
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
      order by b."org_id", (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, (case jsonb_typeof(x.row -> 'created') when 'number' then to_timestamp((x.row -> 'created')::text::double precision) when 'string' then (x.row -> 'created' #>> '{}')::timestamptz end) desc nulls last
    ) r
  $q$, items, prices, customers);
end;
$$;
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
    select b."org_id", b."stripe_customer_id"::text, v.id::text,
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
    select b."org_id", b."stripe_customer_id"::text,
      cu.customer_row ->> 'email', cu.customer_row ->> 'name',
      (case jsonb_typeof(cu.customer_row -> 'created') when 'number' then to_timestamp((cu.customer_row -> 'created')::text::double precision) when 'string' then (cu.customer_row -> 'created' #>> '{}')::timestamptz end)
    from "better_supabase"."billing_customers" b
    %s
    where b."stripe_customer_id" is not null
    order by b."org_id"
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."org_id" = billing_stripe_rows.tenant);
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
  customer text := (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."org_id" = billing_tenant_subscription.tenant);
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
        select distinct on (b."org_id") b."org_id"::text as tenant, b."stripe_customer_id" as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from "better_supabase"."billing_customers" b
        join stripe.subscriptions s on s.customer = b."stripe_customer_id"
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b."org_id", s.created desc nulls last
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
      select b."org_id"::text as tenant, b."stripe_customer_id" as customer, x.created, to_jsonb(x.*) as invoice
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
    'customer', (select b."stripe_customer_id" from "better_supabase"."billing_customers" b where b."org_id" = billing_status.tenant),
    'account', (select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b where b."org_id" = billing_status.tenant),
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

-- The billing page in one call. It runs as the caller and reads through the
-- status, invoice and usage functions, which check billing and usage reads.
create or replace function "better_supabase"."billing_overview"(tenant uuid, invoice_limit integer default 10)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status jsonb := "better_supabase"."billing_status"(billing_overview.tenant);
begin
  return jsonb_build_object(
    'customerId', v_status -> 'customer',
    'accountId', v_status -> 'account',
    'seats', coalesce((v_status ->> 'seats')::integer, 0),
    'subscription', coalesce(v_status -> 'subscription', 'null'::jsonb),
    'invoices', coalesce("better_supabase"."billing_invoices"(billing_overview.tenant, billing_overview.invoice_limit), '[]'::jsonb),
    'usage', coalesce('[]'::jsonb, '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."billing_overview"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."billing_overview"(uuid, integer) to authenticated, service_role;

-- A subscription kept in Postgres: unit_amount is the price of one unit for one
-- billing_interval in minor units of currency, and [period_start, period_end)
-- is the current period.
create table "better_supabase"."billing_native_subscriptions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "plan" text not null constraint bsb_billing_native_subscriptions_plan_check check (length("plan") >= 1 and length("plan") <= 100),
  "currency" text not null constraint bsb_billing_native_subscriptions_currency_check check ("currency" ~ '^[A-Z]{3}$'),
  "unit_amount" bigint not null constraint bsb_billing_native_subscriptions_unit_amount_check check ("unit_amount" >= 0),
  "quantity" integer not null default 1 constraint bsb_billing_native_subscriptions_quantity_check check ("quantity" >= 0),
  "billing_interval" text not null default 'month',
  "status" text not null default 'active' constraint bsb_billing_native_subscriptions_status_check check ("status" in ('active', 'canceled')),
  "period_start" timestamptz not null,
  "period_end" timestamptz not null,
  "canceled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  constraint "bsb_billing_native_subscriptions_interval_check" check ("billing_interval" in ('week', 'month', 'year')),
  constraint bsb_billing_native_subscriptions_check check ("period_end" > "period_start")
);
create index "billing_native_subscriptions_tenant_idx" on "better_supabase"."billing_native_subscriptions" ("org_id", "status");
alter table "better_supabase"."billing_native_subscriptions" enable row level security;
revoke all on "better_supabase"."billing_native_subscriptions" from public, anon, authenticated;
grant all on "better_supabase"."billing_native_subscriptions" to service_role;

-- Starts a subscription for tenant; its first period begins at started_at
-- (now by default). Service role only.
create or replace function "better_supabase"."create_native_subscription"(tenant uuid, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role creates native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  insert into "better_supabase"."billing_native_subscriptions" ("org_id", "plan", "currency", "unit_amount", "quantity", "billing_interval", "period_start", "period_end")
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'plan', v_row."plan", 'currency', v_row."currency",
    'unit_amount', v_row."unit_amount"::text, 'quantity', v_row."quantity", 'interval', v_row."billing_interval",
    'period_start', v_row."period_start", 'period_end', v_row."period_end");
exception when check_violation or invalid_text_representation then
  raise exception 'The subscription is invalid' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
end;
$$;

-- Changes the price or the quantity of a subscription at an instant inside its
-- current period and returns what the change adds: credit is the unused part
-- of the old price, charge the remaining part of the new one, and net is
-- charge minus credit (negative for a downgrade). With the ledger block the
-- net posts as one transaction (receivable against proration revenue), once
-- per subscription and instant. Service role only.
create or replace function "better_supabase"."prorate_change"(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_end" - v_at) / extract(epoch from v_row."period_end" - v_row."period_start")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  update "better_supabase"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$$;

-- Cancels a subscription. Service role only.
create or replace function "better_supabase"."cancel_native_subscription"(subscription_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role cancels native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  update "better_supabase"."billing_native_subscriptions" set "status" = 'canceled', "canceled_at" = now()
    where "id" = cancel_native_subscription.subscription_id and "status" = 'active';
  return found;
end;
$$;
revoke execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamptz) to service_role;
revoke execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."prorate_change"(uuid, bigint, integer, timestamptz) to service_role;
revoke execute on function "better_supabase"."cancel_native_subscription"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."cancel_native_subscription"(uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."billing_customers" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('billing.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."billing_customers" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."billing_customers" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."billing_customers" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_031_billing.sql
-- better-supabase module: billing
-- @bsb-block-data billing
-- @bsb-hash sha256:9192c5a247a10a63b3db4a9a5d145a27c1a3ad52659ca7ef8e067daddb2d51c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('billing', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
