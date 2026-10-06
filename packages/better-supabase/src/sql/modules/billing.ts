import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["seatRoles"],
  tables: {
    customers: {
      name: "billing_customers",
      columns: {
        tenant: "organization_id",
        customer: "stripe_customer_id",
        createdAt: "created_at",
      },
    },
  },
};

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
  const seatRoles = ctx.list("seatRoles", []);
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
drop policy if exists "billing_customers_read" on ${t};
create policy "billing_customers_read" on ${t} for select to authenticated
  using (${can(c("tenant"), "read")});

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

revoke execute on function ${fn("billing_customer")}(${id}) from public, anon;
revoke execute on function ${fn("billing_customer_tenant")}(text) from public, anon, authenticated;
revoke execute on function ${fn("link_billing_customer")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("billing_seat_count")}(${id}) from public, anon, authenticated;
revoke execute on function ${fn("billing_subscription_item")}(${id}, text) from public, anon, authenticated;
revoke execute on function ${fn("billing_status")}(${id}) from public, anon;
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
  version: 1,
  names: NAMES,
  contract,
  build,
};
