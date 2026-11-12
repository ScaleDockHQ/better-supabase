SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."billing_customers" (
  "tenant_id"                  uuid                     NOT NULL,
  "stripe_customer_id"         text,
  "stripe_customer_account_id" text,
  "created_at"                 timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "billing_customers_pkey" PRIMARY KEY (tenant_id),
  CONSTRAINT "billing_customers_stripe_customer_account_id_key" UNIQUE (stripe_customer_account_id),
  CONSTRAINT "billing_customers_stripe_customer_id_key" UNIQUE (stripe_customer_id),
  CONSTRAINT "bsb_billing_customers_party" CHECK (((stripe_customer_id IS NOT NULL) OR (stripe_customer_account_id IS NOT NULL))),
  CONSTRAINT "bsb_billing_customers_stripe_customer_account_id_check" CHECK ((stripe_customer_account_id ~ '^acct_'::text)),
  CONSTRAINT "bsb_billing_customers_stripe_customer_id_check" CHECK ((stripe_customer_id ~ '^cus_'::text))
);

ALTER TABLE "better_supabase"."billing_customers"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."billing_native_subscriptions" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"        uuid                     NOT NULL,
  "plan"             text                     NOT NULL,
  "currency"         text                     NOT NULL,
  "unit_amount"      bigint                   NOT NULL,
  "quantity"         integer                  NOT NULL DEFAULT 1,
  "billing_interval" text                     NOT NULL DEFAULT 'month'::text,
  "status"           text                     NOT NULL DEFAULT 'active'::text,
  "period_start"     timestamp with time zone NOT NULL,
  "period_end"       timestamp with time zone NOT NULL,
  "canceled_at"      timestamp with time zone,
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "billing_native_subscriptions_pkey" PRIMARY KEY (id),
  CONSTRAINT "bsb_billing_native_subscriptions_check" CHECK ((period_end > period_start)),
  CONSTRAINT "bsb_billing_native_subscriptions_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "bsb_billing_native_subscriptions_interval_check" CHECK ((billing_interval = ANY (ARRAY['week'::text, 'month'::text, 'year'::text]))),
  CONSTRAINT "bsb_billing_native_subscriptions_plan_check" CHECK (((length(plan) >= 1) AND (length(plan) <= 100))),
  CONSTRAINT "bsb_billing_native_subscriptions_quantity_check" CHECK ((quantity >= 0)),
  CONSTRAINT "bsb_billing_native_subscriptions_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'canceled'::text]))),
  CONSTRAINT "bsb_billing_native_subscriptions_unit_amount_check" CHECK ((unit_amount >= 0))
);

ALTER TABLE "better_supabase"."billing_native_subscriptions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.billing_account (
  tenant uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_account"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_all_customers()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_all_customers"() $function$;

CREATE OR REPLACE FUNCTION api.billing_all_invoices (
  for_status     text    DEFAULT NULL::text,
  max_rows       integer DEFAULT 100,
  before_created bigint  DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_all_invoices"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.billing_all_subscriptions (
  for_status     text    DEFAULT NULL::text,
  max_rows       integer DEFAULT 100,
  before_created bigint  DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_all_subscriptions"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.billing_customer (
  tenant uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_customer"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_customer_details (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_customer_details"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_customer_tenant (
  customer text
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_customer_tenant"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_invoices (
  tenant   uuid,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_invoices"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.billing_overview (
  tenant        uuid,
  invoice_limit integer DEFAULT 10
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_overview"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.billing_payment_methods (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_payment_methods"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_plan_price (
  plan             text,
  billing_interval text DEFAULT NULL::text,
  variant          text DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_plan_price"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.billing_platform_customers()
  RETURNS TABLE (
    tenant   uuid,
    customer text,
    email    text,
    name     text,
    created  timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."billing_platform_customers"() $function$;

CREATE OR REPLACE FUNCTION api.billing_platform_invoices()
  RETURNS TABLE (
    tenant             uuid,
    customer           text,
    invoice            text,
    subscription       text,
    number             text,
    status             text,
    amount_due         bigint,
    amount_paid        bigint,
    amount_remaining   bigint,
    total              bigint,
    currency           text,
    due_date           timestamp with time zone,
    finalized_at       timestamp with time zone,
    paid_at            timestamp with time zone,
    hosted_invoice_url text,
    invoice_pdf        text,
    customer_email     text,
    customer_name      text,
    created            timestamp with time zone,
    updated_at         timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."billing_platform_invoices"() $function$;

CREATE OR REPLACE FUNCTION api.billing_platform_subscriptions()
  RETURNS TABLE (
    tenant               uuid,
    customer             text,
    customer_email       text,
    customer_name        text,
    subscription         text,
    status               text,
    price                text,
    price_metadata       jsonb,
    plan                 text,
    quantity             bigint,
    amount               bigint,
    currency             text,
    recurring_interval   text,
    current_period_start timestamp with time zone,
    current_period_end   timestamp with time zone,
    cancel_at_period_end boolean,
    created              timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."billing_platform_subscriptions"() $function$;

CREATE OR REPLACE FUNCTION api.billing_seat_count (
  tenant uuid
)
  RETURNS integer
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_seat_count"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_status (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_status"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_stripe_rows (
  tenant   uuid,
  source   text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_stripe_rows"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.billing_subscription (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_subscription"($1) $function$;

CREATE OR REPLACE FUNCTION api.billing_subscription_item (
  tenant uuid,
  price  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_subscription_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.billing_tax_ids (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."billing_tax_ids"($1) $function$;

CREATE OR REPLACE FUNCTION api.cancel_native_subscription (
  subscription_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_native_subscription"($1) $function$;

CREATE OR REPLACE FUNCTION api.create_native_subscription (
  tenant           uuid,
  plan             text,
  currency         text,
  unit_amount      bigint,
  quantity         integer                  DEFAULT 1,
  billing_interval text                     DEFAULT 'month'::text,
  started_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_native_subscription"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.link_billing_account (
  tenant  uuid,
  account text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."link_billing_account"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.link_billing_customer (
  tenant   uuid,
  customer text
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."link_billing_customer"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.prorate_change (
  subscription_id uuid,
  unit_amount     bigint                   DEFAULT NULL::bigint,
  quantity        integer                  DEFAULT NULL::integer,
  at              timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."prorate_change"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_account (
  tenant uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select b."stripe_customer_account_id" from "better_supabase"."billing_customers" b
  where b."tenant_id" = billing_account.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_account.tenant, 'billing.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_all_customers()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(c.*) order by c.tenant), '[]'::jsonb)
  from "better_supabase"."billing_platform_customers"() c
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_all_invoices (
  for_status     text    DEFAULT NULL::text,
  max_rows       integer DEFAULT 100,
  before_created bigint  DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_all_subscriptions (
  for_status     text    DEFAULT NULL::text,
  max_rows       integer DEFAULT 100,
  before_created bigint  DEFAULT NULL::bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_customer (
  tenant uuid
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select b."stripe_customer_id" from "better_supabase"."billing_customers" b
  where b."tenant_id" = billing_customer.tenant and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', billing_customer.tenant, 'billing.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_customer_details (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."billing_stripe_rows"(billing_customer_details.tenant, 'customers', 1) -> 0
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_customer_tenant (
  customer text
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select b."tenant_id" from "better_supabase"."billing_customers" b
  where b."stripe_customer_id" = billing_customer_tenant.customer
    or b."stripe_customer_account_id" = billing_customer_tenant.customer
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_invoices (
  tenant   uuid,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."billing_stripe_rows"(billing_invoices.tenant, 'invoices', billing_invoices.max_rows)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_overview (
  tenant        uuid,
  invoice_limit integer DEFAULT 10
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_payment_methods (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."billing_stripe_rows"(billing_payment_methods.tenant, 'payment_methods', 50)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_plan_price (
  plan             text,
  billing_interval text DEFAULT NULL::text,
  variant          text DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select null::text
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_platform_customers()
  RETURNS TABLE (
    tenant   uuid,
    customer text,
    email    text,
    name     text,
    created  timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_platform_invoices()
  RETURNS TABLE (
    tenant             uuid,
    customer           text,
    invoice            text,
    subscription       text,
    number             text,
    status             text,
    amount_due         bigint,
    amount_paid        bigint,
    amount_remaining   bigint,
    total              bigint,
    currency           text,
    due_date           timestamp with time zone,
    finalized_at       timestamp with time zone,
    paid_at            timestamp with time zone,
    hosted_invoice_url text,
    invoice_pdf        text,
    customer_email     text,
    customer_name      text,
    created            timestamp with time zone,
    updated_at         timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_platform_subscriptions()
  RETURNS TABLE (
    tenant               uuid,
    customer             text,
    customer_email       text,
    customer_name        text,
    subscription         text,
    status               text,
    price                text,
    price_metadata       jsonb,
    plan                 text,
    quantity             bigint,
    amount               bigint,
    currency             text,
    recurring_interval   text,
    current_period_start timestamp with time zone,
    current_period_end   timestamp with time zone,
    cancel_at_period_end boolean,
    created              timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_seat_count (
  tenant uuid
)
  RETURNS integer
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select count(*)::integer from "public"."memberships" m
  where m."organization_id" = billing_seat_count.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_status (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_stripe_rows (
  tenant   uuid,
  source   text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_subscription (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'billing.read'), false)) or (select coalesce(better_supabase.is_platform('billing.read'), false))) then
    raise exception 'Not allowed to read billing in this tenant' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  return "better_supabase"."billing_tenant_subscription"(billing_subscription.tenant);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_subscription_item (
  tenant uuid,
  price  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_tax_ids (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.billing_tenant_subscription (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_native_subscription (
  subscription_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role cancels native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  update "better_supabase"."billing_native_subscriptions" set "status" = 'canceled', "canceled_at" = now()
    where "id" = cancel_native_subscription.subscription_id and "status" = 'active';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_native_subscription (
  tenant           uuid,
  plan             text,
  currency         text,
  unit_amount      bigint,
  quantity         integer                  DEFAULT 1,
  billing_interval text                     DEFAULT 'month'::text,
  started_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_links', '"better_supabase"."ai_chat_links"', 'created_by', true, array['salt']::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.identity_links', '"better_supabase"."identity_links"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.identity_link_codes', '"better_supabase"."identity_link_codes"', 'user_id', true, '{}'::text[], false),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_collections', '"better_supabase"."subject_collections"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.collection_favorites', '"better_supabase"."collection_favorites"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_items', '"better_supabase"."saved_items"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'notifier_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'appellant_id', true, '{}'::text[], true),
    ('user', 'better_supabase.reviews', '"better_supabase"."reviews"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leave_requests', '"better_supabase"."leave_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.warranty_claims', '"better_supabase"."warranty_claims"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'appraisee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'calibrated_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'assignee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'opened_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'counted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.periods', '"better_supabase"."periods"', 'closed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'satisfied_by', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commissions', '"better_supabase"."commissions"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referrals', '"better_supabase"."referrals"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'prescriber_id', true, '{}'::text[], true),
    ('user', 'better_supabase.checkout_sessions', '"better_supabase"."checkout_sessions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_mandates', '"better_supabase"."agent_mandates"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.advisory_products', '"better_supabase"."advisory_products"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.vex_statements', '"better_supabase"."vex_statements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.advisories', '"better_supabase"."advisories"', 'created_by', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'tenant_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'tenant_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.support_sessions', '"better_supabase"."support_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.support_requests', '"better_supabase"."support_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incoming_webhooks', '"better_supabase"."incoming_webhooks"', 'tenant', true, array['token_hash', 'secret', 'secret_id', 'previous_secret', 'previous_secret_id']::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_billed_periods', '"better_supabase"."usage_billed_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_native_subscriptions', '"better_supabase"."billing_native_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_customers', '"better_supabase"."billing_customers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.billing_subscriptions', '"better_supabase"."billing_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.data_subject_requests', '"better_supabase"."data_subject_requests"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'tenant_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_chunks', '"better_supabase"."import_chunks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_tax_lines', '"better_supabase"."purchase_order_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_specification_lines', '"better_supabase"."work_item_specification_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_material_lines', '"better_supabase"."work_item_material_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_locations', '"better_supabase"."party_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_bank_accounts', '"better_supabase"."party_bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_channels', '"better_supabase"."party_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_subjects', '"better_supabase"."activity_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_open_items', '"better_supabase"."invoice_open_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_endpoints', '"better_supabase"."e_invoice_endpoints"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_deliveries', '"better_supabase"."e_invoice_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_escalations', '"better_supabase"."sla_escalations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_collections', '"better_supabase"."subject_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_collection_entries', '"better_supabase"."subject_collection_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_favorites', '"better_supabase"."collection_favorites"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_items', '"better_supabase"."saved_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.hostnames', '"better_supabase"."hostnames"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_statements', '"better_supabase"."moderation_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reviews', '"better_supabase"."reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.review_stats', '"better_supabase"."review_stats"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leave_types', '"better_supabase"."leave_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leave_requests', '"better_supabase"."leave_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_profiles', '"better_supabase"."incident_regulatory_profiles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_schedules', '"better_supabase"."accounting_recognition_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_rows', '"better_supabase"."accounting_recognition_rows"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_receipts', '"better_supabase"."consent_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.warranty_claims', '"better_supabase"."warranty_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_methods', '"better_supabase"."lims_methods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_competencies', '"better_supabase"."appraisal_competencies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_review_ratings', '"better_supabase"."appraisal_review_ratings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_goals', '"better_supabase"."appraisal_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lines', '"better_supabase"."pick_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.count_plans', '"better_supabase"."count_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.putaway_rules', '"better_supabase"."putaway_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bin_slots', '"better_supabase"."bin_slots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.variant_sizes', '"better_supabase"."variant_sizes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_lines', '"better_supabase"."rfq_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_suppliers', '"better_supabase"."rfq_suppliers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quote_lines', '"better_supabase"."rfq_quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tills', '"better_supabase"."tills"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_rules', '"better_supabase"."care_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.periods', '"better_supabase"."periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_plans', '"better_supabase"."commission_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commissions', '"better_supabase"."commissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referrals', '"better_supabase"."referrals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.checkout_sessions', '"better_supabase"."checkout_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_mandates', '"better_supabase"."agent_mandates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisory_products', '"better_supabase"."advisory_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisory_product_versions', '"better_supabase"."advisory_product_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sbom_components', '"better_supabase"."sbom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.vulnerabilities', '"better_supabase"."vulnerabilities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.vex_statements', '"better_supabase"."vex_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisories', '"better_supabase"."advisories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.advisory_vulnerabilities', '"better_supabase"."advisory_vulnerabilities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prompt_versions', '"better_supabase"."prompt_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prompt_labels', '"better_supabase"."prompt_labels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eval_datasets', '"better_supabase"."eval_datasets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eval_runs', '"better_supabase"."eval_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guardrail_policies', '"better_supabase"."guardrail_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guardrail_decisions', '"better_supabase"."guardrail_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.option_sets', '"better_supabase"."option_sets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.option_set_items', '"better_supabase"."option_set_items"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link_billing_account (
  tenant  uuid,
  account text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link_billing_customer (
  tenant   uuid,
  customer text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'advisories.publish' then 'advisories.publish'
    when 'advisories.read' then 'advisories.read'
    when 'advisories.write' then 'advisories.write'
    when 'agent-checkout.manage' then 'agent_checkout.manage'
    when 'agent-checkout.read' then 'agent_checkout.read'
    when 'agent-checkout.write' then 'agent_checkout.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.manage' then 'ai_chat.manage'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'appraisals.manage' then 'appraisals.manage'
    when 'appraisals.read' then 'appraisals.read'
    when 'appraisals.review' then 'appraisals.review'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.read' then 'audit.read'
    when 'audit.readAll' then 'audit.read'
    when 'audit.revert' then 'audit.revert'
    when 'automations.manage' then 'automations.manage'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'automations.write' then 'automations.write'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'billing.manage' then 'billing.manage'
    when 'billing.read' then 'billing.read'
    when 'billing.readAll' then 'billing.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk-actions.run' then 'bulk_actions.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'clinical-decision-support.manage' then 'clinical_decision_support.manage'
    when 'clinical-decision-support.read' then 'clinical_decision_support.read'
    when 'clinical-decision-support.write' then 'clinical_decision_support.write'
    when 'collections.read' then 'collections.read'
    when 'collections.share' then 'collections.share'
    when 'collections.write' then 'collections.write'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'commissions.manage' then 'commissions.manage'
    when 'commissions.read' then 'commissions.read'
    when 'commissions.write' then 'commissions.write'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'dam.read' then 'dam.read'
    when 'dam.write' then 'dam.write'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deadlines.manage' then 'deadlines.manage'
    when 'deadlines.read' then 'deadlines.read'
    when 'deadlines.write' then 'deadlines.write'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'document-templates.manage' then 'document_templates.manage'
    when 'document-templates.read' then 'document_templates.read'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'domains.manage' then 'domains.manage'
    when 'domains.read' then 'domains.read'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'e-prescribing.manage' then 'e_prescribing.manage'
    when 'e-prescribing.read' then 'e_prescribing.read'
    when 'e-prescribing.sign' then 'e_prescribing.sign'
    when 'e-prescribing.write' then 'e_prescribing.write'
    when 'employees.read' then 'employees.read'
    when 'employees.readSensitive' then 'employees.read_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'funding.approve' then 'funding.approve'
    when 'funding.claim' then 'funding.claim'
    when 'funding.manage' then 'funding.manage'
    when 'funding.read' then 'funding.read'
    when 'funding.register' then 'funding.register'
    when 'funding.write' then 'funding.write'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'impersonation.read' then 'impersonation.read'
    when 'impersonation.revoke' then 'impersonation.revoke'
    when 'impersonation.start' then 'impersonation.start'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.read' then 'members.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invoices.approve' then 'invoices.approve'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.send' then 'invoices.send'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'leave.approve' then 'leave.approve'
    when 'leave.manage' then 'leave.manage'
    when 'leave.read' then 'leave.read'
    when 'leave.request' then 'leave.request'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'legal-entities.manage' then 'legal_entities.manage'
    when 'legal-entities.read' then 'legal_entities.read'
    when 'lims.manage' then 'lims.manage'
    when 'lims.read' then 'lims.read'
    when 'lims.write' then 'lims.write'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'maintenance.manage' then 'maintenance.manage'
    when 'maintenance.read' then 'maintenance.read'
    when 'maintenance.record' then 'maintenance.record'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'meetings.manage' then 'meetings.manage'
    when 'meetings.read' then 'meetings.read'
    when 'meetings.write' then 'meetings.write'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'option-sets.manage' then 'option_sets.manage'
    when 'option-sets.read' then 'option_sets.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'payroll-export.export' then 'payroll_export.export'
    when 'payroll-export.read' then 'payroll_export.read'
    when 'periods.manage' then 'periods.manage'
    when 'periods.read' then 'periods.read'
    when 'periods.write' then 'periods.write'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'referrals.manage' then 'referrals.manage'
    when 'referrals.read' then 'referrals.read'
    when 'referrals.write' then 'referrals.write'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'reviews.manage' then 'reviews.manage'
    when 'rfqs.manage' then 'rfqs.manage'
    when 'rfqs.read' then 'rfqs.read'
    when 'rfqs.write' then 'rfqs.write'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.read' then 'segments.read'
    when 'segments.write' then 'segments.write'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'tax.manage' then 'tax.manage'
    when 'tax.read' then 'tax.read'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'tills.manage' then 'tills.manage'
    when 'tills.read' then 'tills.read'
    when 'tills.write' then 'tills.write'
    when 'time-entries.approve' then 'time_entries.approve'
    when 'time-entries.manage' then 'time_entries.manage'
    when 'time-entries.read' then 'time_entries.read'
    when 'time-entries.track' then 'time_entries.track'
    when 'timeline.read' then 'timeline.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'warehouse.manage' then 'warehouse.manage'
    when 'warehouse.pick' then 'warehouse.pick'
    when 'warehouse.read' then 'warehouse.read'
    when 'warranty.decide' then 'warranty.decide'
    when 'warranty.read' then 'warranty.read'
    when 'warranty.write' then 'warranty.write'
    when 'webhooks-in.create' then 'webhooks.manage'
    when 'webhooks-in.delete' then 'webhooks.manage'
    when 'webhooks-in.read' then 'webhooks.read'
    when 'webhooks-in.update' then 'webhooks.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.read' then 'webhooks.read'
    when 'workflow-editor.manage' then 'workflow_editor.manage'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflow-editor.write' then 'workflow_editor.write'
    when 'workflows.manage' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_overview (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_org jsonb;
  v_seats integer;
begin
  select to_jsonb(o) into v_org
  from "better_supabase"."list_my_organizations"() o
  where o.id = organization_overview.organization;
  if v_org is null then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  begin
    v_seats := ("better_supabase"."billing_status"(organization_overview.organization) ->> 'seats')::integer;
  exception when others then
    v_seats := null;
  end;
  return jsonb_build_object(
    'id', v_org ->> 'id',
    'name', v_org ->> 'name',
    'slug', v_org -> 'slug',
    'role', v_org ->> 'role',
    'seats', v_seats,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role,
        'roles', coalesce(to_jsonb(m) -> 'roles', jsonb_build_array(m.role)),
        'disabledAt', to_jsonb(m) -> 'disabled_at')
        order by m.user_id)
      from "better_supabase"."list_members"(organization_overview.organization) m
    ), '[]'::jsonb),
    'invitations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id, 'email', i.email, 'role', i.role, 'expiresAt', to_jsonb(i) -> 'expires_at')
          order by i.email)
        from "better_supabase"."list_organization_invitations"(organization_overview.organization) i
      ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prorate_change (
  subscription_id uuid,
  unit_amount     bigint                   DEFAULT NULL::bigint,
  quantity        integer                  DEFAULT NULL::integer,
  at              timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

ALTER TABLE "better_supabase"."billing_customers"
  ADD CONSTRAINT "billing_customers_tenant_fkey" FOREIGN KEY (tenant_id) REFERENCES public.organizations(id) ON DELETE CASCADE;

CREATE INDEX billing_native_subscriptions_tenant_idx ON better_supabase.billing_native_subscriptions USING btree (tenant_id, status);

CREATE POLICY "bsb_billing_customers_read" ON "better_supabase"."billing_customers"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('billing.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."billing_customers"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."billing_customers"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."billing_customers"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('billing.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."billing_customers"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

REVOKE ALL ON FUNCTION "api"."billing_account"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_account"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_all_customers"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_all_customers"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_all_invoices"(text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_all_invoices"(text, integer, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_all_subscriptions"(text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_all_subscriptions"(text, integer, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_customer"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_customer"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_customer_details"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_customer_details"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_customer_tenant"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_customer_tenant"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."billing_invoices"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_invoices"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_overview"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_overview"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_payment_methods"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_payment_methods"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_plan_price"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_plan_price"(text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_platform_customers"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_platform_customers"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_platform_invoices"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_platform_invoices"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_platform_subscriptions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_platform_subscriptions"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_seat_count"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_seat_count"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."billing_status"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_status"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_stripe_rows"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_stripe_rows"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_subscription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_subscription"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."billing_subscription_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_subscription_item"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."billing_tax_ids"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."billing_tax_ids"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."cancel_native_subscription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_native_subscription"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."link_billing_account"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."link_billing_account"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."link_billing_customer"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."link_billing_customer"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."prorate_change"(uuid, bigint, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."prorate_change"(uuid, bigint, integer, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_account"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_account"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_all_customers"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_all_customers"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_all_invoices"(text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_all_invoices"(text, integer, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_all_subscriptions"(text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_all_subscriptions"(text, integer, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_customer"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_customer"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_customer_details"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_customer_details"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_customer_tenant"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_customer_tenant"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_invoices"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_invoices"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_overview"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_overview"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_payment_methods"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_payment_methods"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_plan_price"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_plan_price"(text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_platform_customers"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_platform_customers"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_platform_invoices"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_platform_invoices"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_platform_subscriptions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_platform_subscriptions"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_seat_count"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_seat_count"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_status"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_status"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_stripe_rows"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_stripe_rows"(uuid, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_subscription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_subscription"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_subscription_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_subscription_item"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_tax_ids"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."billing_tax_ids"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."billing_tenant_subscription"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."cancel_native_subscription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_native_subscription"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_native_subscription"(uuid, text, text, bigint, integer, text, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."link_billing_account"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."link_billing_account"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."link_billing_customer"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."link_billing_customer"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."prorate_change"(uuid, bigint, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."prorate_change"(uuid, bigint, integer, timestamp WITH time zone) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."billing_customers" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."billing_customers" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."billing_native_subscriptions" TO "service_role";
