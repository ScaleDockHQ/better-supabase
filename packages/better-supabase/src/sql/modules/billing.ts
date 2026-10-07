import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addForeignKey,
  columnRef,
  quotedTable,
  schemaPreamble,
  SERVICE_CALLER,
  tenantIn,
} from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";
import { type PlanLookup, platformLists } from "./billing-platform.ts";

const NAMES: ModuleNames = {
  options: ["seatRoles", "plans", "tenantKey"],
  tables: {
    customers: {
      name: "billing_customers",
      lifecycle: { tenant: "tenant" },
      columns: {
        tenant: "organization_id",
        customer: "stripe_customer_id",
        createdAt: "created_at",
      },
    },
  },
};

/** `options.plans`: the app's plan catalog, so checkout takes a plan key. */
interface PlanCatalog {
  readonly table: string;
  /** The plan key column, default `key`. */
  readonly key: string;
  /** The Stripe price id column, default `stripe_price_id`. */
  readonly price: string;
  /** A billing interval column (`month`, `year`), when plans have several prices. */
  readonly interval?: string;
  /** A boolean column; only rows where it is true are offered. */
  readonly active?: string;
  /**
   * A variant column, when a plan key has several prices besides the
   * interval, such as credit packs (`1000`, `5000`) or seat tiers. The row
   * without a variant is the plan's default.
   */
  readonly variant?: string;
}

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

function plansOf(ctx: ModuleContext): PlanCatalog | undefined {
  const where = "sql.modules.billing.options.plans";
  const option = ctx.option("plans");
  if (option === undefined) return undefined;
  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(
      `${where} must be { table, key?, price?, interval?, active?, variant? }`,
    );
  }
  const entries = new Map<string, unknown>(Object.entries(option));
  const text = (name: string, fallback?: string): string | undefined => {
    const value = entries.get(name) ?? fallback;
    if (value === undefined) return undefined;
    if (
      typeof value !== "string" ||
      !value.split(".").every((part) => IDENT.test(part))
    ) {
      throw new TypeError(`${where}.${name} must be a lowercase identifier`);
    }
    return value;
  };
  const table = text("table");
  if (table === undefined || table.split(".").length > 2) {
    throw new TypeError(`${where}.table must be "table" or "schema.table"`);
  }
  const interval = text("interval");
  const active = text("active");
  const variant = text("variant");
  return {
    table,
    key: text("key", "key") ?? "key",
    price: text("price", "stripe_price_id") ?? "stripe_price_id",
    ...(interval === undefined ? {} : { interval }),
    ...(active === undefined ? {} : { active }),
    ...(variant === undefined ? {} : { variant }),
  };
}

const qualified = (table: string): string => quotedTable(table);

const platformPlans = (
  plans: PlanCatalog | undefined,
): PlanLookup | undefined =>
  plans && {
    table: qualified(plans.table),
    key: plans.key,
    price: plans.price,
  };

function planPrice(ctx: ModuleContext, plans: PlanCatalog | undefined): string {
  const fn = ctx.fn("billing_plan_price");
  const body = plans
    ? `select p.${sqlIdent(plans.price)}::text from ${qualified(plans.table)} p
  where p.${sqlIdent(plans.key)}::text = billing_plan_price.plan${
    plans.interval
      ? `
    and (billing_plan_price.billing_interval is null or p.${sqlIdent(plans.interval)}::text = billing_plan_price.billing_interval)`
      : ""
  }${
    plans.variant
      ? `
    and (billing_plan_price.variant is null or p.${sqlIdent(plans.variant)}::text = billing_plan_price.variant)`
      : ""
  }${
    plans.active
      ? `
    and p.${sqlIdent(plans.active)}`
      : ""
  }
  order by ${plans.variant ? `(p.${sqlIdent(plans.variant)} is null) desc, ` : ""}${plans.interval ? `(p.${sqlIdent(plans.interval)}::text = 'month') desc, ` : ""}1
  limit 1`
    : "select null::text";
  return `-- The Stripe price of a plan key from options.plans (the app's plan
-- catalog), for checkout({ plan }); null without the option or the plan.
-- variant picks one of the plan's prices (a credit pack, a tier); without it,
-- the row without a variant.
drop function if exists ${fn}(text, text);
create or replace function ${fn}(plan text, billing_interval text default null, variant text default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  ${body}
$$;
revoke execute on function ${fn}(text, text, text) from public, anon;
grant execute on function ${fn}(text, text, text) to authenticated, service_role;
`;
}

/**
 * The tenant row `billing_customers` references: `options.tenantKey`
 * (`schema.table.column`, `false` for none), else the organizations
 * module's table when it is installed.
 */
function tenantReference(ctx: ModuleContext): string | undefined {
  const configured = ctx.option("tenantKey");
  if (configured === false) return undefined;
  if (configured !== undefined) {
    if (typeof configured !== "string") {
      throw new TypeError(
        'sql.modules.billing.options.tenantKey must be "schema.table.column" or false',
      );
    }
    const ref = columnRef("sql.modules.billing.options.tenantKey", configured);
    return `${ref.table} (${ref.column})`;
  }
  if (!ctx.installed("organizations")) return undefined;
  const organizations = ctx.of("organizations");
  return `${organizations.table("organizations")} (${organizations.col("organizations", "id")})`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const t = ctx.table("customers");
  const c = (logical: string): string => ctx.col("customers", logical);
  const fn = (name: string): string => ctx.fn(name);
  const tenant = ctx.of("tenant");
  const memberships = tenant.table("memberships");
  const mc = (logical: string): string => tenant.col("memberships", logical);
  const permissions = MODULE_PERMISSIONS.billing;
  const can = (scope: string, action: "read" | "manage"): string =>
    `(${SERVICE_CALLER} or coalesce(better_supabase.can('tenant', ${scope}, ${ctx.permission(action, permissions[action])}), false))`;
  const viewAll = `coalesce(better_supabase.is_platform(${ctx.permission("viewAll", permissions.viewAll)}), false)`;
  const seatRoles = ctx.list("seatRoles", []);
  const references = ctx.manages ? tenantReference(ctx) : undefined;
  const tenantKey =
    references === undefined
      ? ""
      : `${addForeignKey({
          table: t,
          name: "billing_customers_tenant_fkey",
          column: c("tenant"),
          references,
          onDelete: "cascade",
        })}\n`;
  const seatFilter =
    seatRoles.length === 0
      ? ""
      : `\n    and m.${mc("role")}::text = any (${sqlString(`{${seatRoles.join(",")}}`)}::text[])`;

  return `${schemaPreamble(ctx)}
-- Each tenant's Stripe customer. The entitlements module reads it as its
-- customer source when config.entitlements.customer is unset.
create table if not exists ${t} (
  ${c("tenant")} ${id} primary key,
  ${c("customer")} text not null unique check (${c("customer")} ~ '^cus_'),
  ${c("createdAt")} timestamptz not null default now()
);
alter table ${t} enable row level security;
revoke all on ${t} from anon, authenticated;
grant select on ${t} to authenticated;
grant all on ${t} to service_role;
${tenantKey}drop policy if exists "billing_customers_read" on ${t};
create policy "billing_customers_read" on ${t} for select to authenticated
  using (${tenantIn(c("tenant"), ctx.permission("read", permissions.read))});

create or replace function ${fn("billing_customer")}(tenant ${id})
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select b.${c("customer")} from ${t} b
  where b.${c("tenant")} = billing_customer.tenant and ${can("billing_customer.tenant", "read")}
$$;

create or replace function ${fn("billing_customer_tenant")}(customer text)
returns ${id}
language sql
stable
security definer
set search_path = ''
as $$
  select b.${c("tenant")} from ${t} b where b.${c("customer")} = billing_customer_tenant.customer
$$;

-- Links tenant to customer once. Returns the customer that is linked, which
-- is the earlier one when two checkouts raced.
create or replace function ${fn("link_billing_customer")}(tenant ${id}, customer text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  insert into ${t} (${c("tenant")}, ${c("customer")})
  values (link_billing_customer.tenant, link_billing_customer.customer)
  on conflict (${c("tenant")}) do nothing;
  return (select b.${c("customer")} from ${t} b where b.${c("tenant")} = link_billing_customer.tenant);
end;
$$;

-- Members who take a seat${seatRoles.length === 0 ? "" : ` (roles ${seatRoles.join(", ")}, from options.seatRoles)`}.
create or replace function ${fn("billing_seat_count")}(tenant ${id})
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from ${memberships} m
  where m.${mc("tenant")} = billing_seat_count.tenant${seatFilter}
$$;

-- The tenant's active subscription item for price (or its first item), from
-- the Stripe Sync Engine's stripe schema: { subscription, item, price,
-- quantity, status }, or null.
create or replace function ${fn("billing_subscription_item")}(tenant ${id}, price text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b.${c("customer")} from ${t} b where b.${c("tenant")} = billing_subscription_item.tenant);
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

${planPrice(ctx, plansOf(ctx))}${platformLists(ctx, viewAll, platformPlans(plansOf(ctx)))}
-- Rows of a Stripe Sync Engine table for the tenant's customer, newest
-- first, or [] when the table doesn't exist. Reads need billing.read in the
-- tenant, or platform staff.
create or replace function ${fn("billing_stripe_rows")}(tenant ${id}, source text, max_rows integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b.${c("customer")} from ${t} b where b.${c("tenant")} = billing_stripe_rows.tenant);
  found jsonb;
begin
  if not (${can("tenant", "read")} or ${viewAll}) then
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

create or replace function ${fn("billing_invoices")}(tenant ${id}, max_rows integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("billing_stripe_rows")}(billing_invoices.tenant, 'invoices', billing_invoices.max_rows)
$$;

create or replace function ${fn("billing_payment_methods")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("billing_stripe_rows")}(billing_payment_methods.tenant, 'payment_methods', 50)
$$;

-- The customer's contact details as Stripe holds them (email, name,
-- address, phone): Stripe is the record for the billing contact.
create or replace function ${fn("billing_customer_details")}(tenant ${id})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("billing_stripe_rows")}(billing_customer_details.tenant, 'customers', 1) -> 0
$$;

-- The customer's tax ids from the Sync Engine's stripe.tax_ids, newest
-- first: [{ id, type, value, country, verification: { status } | null,
-- created }], the shape of Stripe's tax id objects; [] without the table.
create or replace function ${fn("billing_tax_ids")}(tenant ${id})
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
  from jsonb_array_elements(${fn("billing_stripe_rows")}(billing_tax_ids.tenant, 'tax_ids', 100)) with ordinality as r(t, ord)
$$;

-- The tenant's newest subscription as the Sync Engine stores it, with its
-- items, or null, without checking the caller: for the app's own security
-- definer functions (resolving a member's plan), executable by its owner only.
create or replace function ${fn("billing_tenant_subscription")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  customer text := (select b.${c("customer")} from ${t} b where b.${c("tenant")} = billing_tenant_subscription.tenant);
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
create or replace function ${fn("billing_subscription")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${can("tenant", "read")} or ${viewAll}) then
    raise exception 'Not allowed to read billing in this tenant' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  return ${fn("billing_tenant_subscription")}(billing_subscription.tenant);
end;
$$;

-- Every tenant's newest subscription, for platform staff: [{ tenant,
-- customer, subscription }], newest first, of one status when given, and
-- created before before_created (Stripe's epoch seconds) for the next page.
create or replace function ${fn("billing_all_subscriptions")}(for_status text default null, max_rows integer default 100, before_created bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  found jsonb;
begin
  if not (${SERVICE_CALLER} or ${viewAll}) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  if to_regclass('stripe.subscriptions') is null then
    return '[]'::jsonb;
  end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object('tenant', p.tenant, 'customer', p.customer, 'subscription', p.subscription) order by p.created desc nulls last), '[]'::jsonb)
    from (
      select * from (
        select distinct on (b.${c("tenant")}) b.${c("tenant")}::text as tenant, b.${c("customer")} as customer, s.created,
          to_jsonb(s.*) || jsonb_build_object('items', coalesce((
            select jsonb_agg(to_jsonb(i.*) order by i.created nulls last)
            from stripe.subscription_items i where i.subscription = s.id
          ), '[]'::jsonb)) as subscription
        from ${t} b
        join stripe.subscriptions s on s.customer = b.${c("customer")}
        where ($1::text is null or s.status = $1)
          and ($3::bigint is null or s.created < $3)
        order by b.${c("tenant")}, s.created desc nulls last
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
create or replace function ${fn("billing_all_invoices")}(for_status text default null, max_rows integer default 100, before_created bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  found jsonb;
begin
  if not (${SERVICE_CALLER} or ${viewAll}) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  if to_regclass('stripe.invoices') is null then
    return '[]'::jsonb;
  end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object('tenant', p.tenant, 'customer', p.customer, 'invoice', p.invoice) order by p.created desc nulls last), '[]'::jsonb)
    from (
      select b.${c("tenant")}::text as tenant, b.${c("customer")} as customer, x.created, to_jsonb(x.*) as invoice
      from ${t} b
      join stripe.invoices x on x.customer = b.${c("customer")}
      where ($1::text is null or x.status = $1)
        and ($3::bigint is null or x.created < $3)
      order by x.created desc nulls last
      limit greatest(1, least(coalesce($2, 100), 500))
    ) p
  $q$ into found using for_status, max_rows, before_created;
  return coalesce(found, '[]'::jsonb);
end;
$$;

-- For the billing page: { customer, seats, subscription }.
create or replace function ${fn("billing_status")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${can("tenant", "read")} then
    raise exception 'Not allowed to read billing in this tenant' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'customer', (select b.${c("customer")} from ${t} b where b.${c("tenant")} = billing_status.tenant),
    'seats', ${fn("billing_seat_count")}(tenant),
    'subscription', ${fn("billing_subscription_item")}(tenant)
  );
end;
$$;

revoke execute on function ${fn("billing_stripe_rows")}(${id}, text, integer) from public, anon;
revoke execute on function ${fn("billing_invoices")}(${id}, integer) from public, anon;
revoke execute on function ${fn("billing_payment_methods")}(${id}) from public, anon;
revoke execute on function ${fn("billing_customer_details")}(${id}) from public, anon;
revoke execute on function ${fn("billing_tax_ids")}(${id}) from public, anon;
grant execute on function ${fn("billing_stripe_rows")}(${id}, text, integer) to authenticated, service_role;
grant execute on function ${fn("billing_invoices")}(${id}, integer) to authenticated, service_role;
grant execute on function ${fn("billing_payment_methods")}(${id}) to authenticated, service_role;
grant execute on function ${fn("billing_customer_details")}(${id}) to authenticated, service_role;
grant execute on function ${fn("billing_tax_ids")}(${id}) to authenticated, service_role;
revoke execute on function ${fn("billing_customer")}(${id}) from public, anon;
revoke execute on function ${fn("billing_customer_tenant")}(text) from public, anon, authenticated;
revoke execute on function ${fn("link_billing_customer")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("billing_seat_count")}(${id}) from public, anon, authenticated;
revoke execute on function ${fn("billing_subscription_item")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("billing_status")}(${id}) from public, anon;
revoke execute on function ${fn("billing_subscription")}(${id}) from public, anon;
revoke execute on function ${fn("billing_tenant_subscription")}(${id}) from public, anon, authenticated, service_role;
revoke execute on function ${fn("billing_all_subscriptions")}(text, integer, bigint) from public, anon;
revoke execute on function ${fn("billing_all_invoices")}(text, integer, bigint) from public, anon;
grant execute on function ${fn("billing_all_invoices")}(text, integer, bigint) to authenticated, service_role;
grant execute on function ${fn("billing_subscription")}(${id}) to authenticated, service_role;
grant execute on function ${fn("billing_all_subscriptions")}(text, integer, bigint) to authenticated, service_role;
grant execute on function ${fn("billing_customer")}(${id}) to authenticated, service_role;
grant execute on function ${fn("billing_customer_tenant")}(text) to service_role;
grant execute on function ${fn("link_billing_customer")}(${id}, text) to service_role;
grant execute on function ${fn("billing_seat_count")}(${id}) to service_role;
grant execute on function ${fn("billing_subscription_item")}(${id}, text) to service_role;
grant execute on function ${fn("billing_status")}(${id}) to authenticated, service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    { name: "billing_customer", args: ["{id}"], returns: "text" },
    { name: "billing_customer_tenant", args: ["text"], returns: "{id}" },
    { name: "link_billing_customer", args: ["{id}", "text"], returns: "text" },
    { name: "billing_seat_count", args: ["{id}"], returns: "integer" },
    {
      name: "billing_subscription_item",
      args: ["{id}", "text"],
      returns: "jsonb",
    },
    { name: "billing_status", args: ["{id}"], returns: "jsonb" },
    { name: "billing_subscription", args: ["{id}"], returns: "jsonb" },
    {
      name: "billing_all_invoices",
      args: ["text", "integer", "bigint"],
      returns: "jsonb",
    },
    {
      name: "billing_all_subscriptions",
      args: ["text", "integer", "bigint"],
      returns: "jsonb",
    },
    {
      name: "billing_plan_price",
      args: ["text", "text", "text"],
      returns: "text",
    },
    { name: "billing_invoices", args: ["{id}", "integer"], returns: "jsonb" },
    { name: "billing_platform_subscriptions", args: [], returns: "record" },
    { name: "billing_platform_invoices", args: [], returns: "record" },
    { name: "billing_platform_customers", args: [], returns: "record" },
    { name: "billing_all_customers", args: [], returns: "jsonb" },
    { name: "billing_payment_methods", args: ["{id}"], returns: "jsonb" },
    { name: "billing_customer_details", args: ["{id}"], returns: "jsonb" },
    { name: "billing_tax_ids", args: ["{id}"], returns: "jsonb" },
  ];
}

export const BILLING: ModuleDefinition = {
  name: "billing",
  title: "Stripe billing",
  description:
    "Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "billing_plan_price takes a variant, for plans with several prices.",
      sql: (ctx) =>
        `drop function if exists ${ctx.fn("billing_plan_price")}(text, text);`,
    },
  ],
  names: NAMES,
  contract,
  build,
};
