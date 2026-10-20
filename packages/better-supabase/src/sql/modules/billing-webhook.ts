import type { ModuleContext } from "../context.ts";
import type { PlanLookup } from "./billing-platform.ts";

import { sqlIdent } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";

/** The subscription source: the Stripe Sync Engine, or a table the webhook fills. */
export type SubscriptionSource = "sync-engine" | "webhook";

export function subscriptionSourceOf(ctx: ModuleContext): SubscriptionSource {
  const value = ctx.text("subscriptions", "sync-engine");

  if (value !== "sync-engine" && value !== "webhook") {
    throw new TypeError(
      'blocks.billing.options.subscriptions must be "sync-engine" or "webhook"',
    );
  }

  return value;
}

/**
 * Webhook mode: the tenant's subscription lives in `billing_subscriptions`,
 * which `customer.subscription.*` events write, so an app without the Stripe
 * Sync Engine still has plans, status and a checkout guard.
 */
export function webhookSubscriptions(
  ctx: ModuleContext,
  plans: PlanLookup | undefined,
): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const table = ctx.table("subscriptions");
  const s = (logical: string): string => ctx.col("subscriptions", logical);

  const planOf = plans
    ? `select p.${sqlIdent(plans.key)}::text from ${plans.table} p where p.${sqlIdent(plans.price)}::text = billing_plan_of_price.price limit 1`
    : "select null::text";

  return `
-- The tenant's subscription as the webhook last reported it. event_at is the
-- Stripe event's created time; an older event never overwrites a newer one.
create table if not exists ${table} (
  ${s("tenant")} ${id} primary key,
  ${s("subscription")} text not null,
  ${s("status")} text not null,
  ${s("price")} text,
  ${s("plan")} text,
  ${s("periodEnd")} timestamptz,
  ${s("cancelAt")} timestamptz,
  ${s("eventAt")} timestamptz not null,
  ${s("updatedAt")} timestamptz not null default now()
);
alter table ${table} enable row level security;
revoke all on ${table} from public, anon, authenticated;
grant all on ${table} to service_role;

-- The plan key of a Stripe price in options.plans, or null.
create or replace function ${fn("billing_plan_of_price")}(price text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  ${planOf}
$$;

-- Stores a subscription event; false when a newer event is already stored.
create or replace function ${fn("upsert_billing_subscription")}(
  tenant ${id}, subscription text, status text, price text, period_end timestamptz,
  cancel_at timestamptz, event_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_applied boolean;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("BILLING_FORBIDDEN", "only the service role stores subscriptions")}
  end if;
  insert into ${table} as b (${s("tenant")}, ${s("subscription")}, ${s("status")}, ${s("price")}, ${s("plan")},
    ${s("periodEnd")}, ${s("cancelAt")}, ${s("eventAt")})
  values (upsert_billing_subscription.tenant, upsert_billing_subscription.subscription,
    upsert_billing_subscription.status, upsert_billing_subscription.price,
    ${fn("billing_plan_of_price")}(upsert_billing_subscription.price),
    upsert_billing_subscription.period_end, upsert_billing_subscription.cancel_at,
    upsert_billing_subscription.event_at)
  on conflict (${s("tenant")}) do update set
    ${s("subscription")} = excluded.${s("subscription")},
    ${s("status")} = excluded.${s("status")},
    ${s("price")} = excluded.${s("price")},
    ${s("plan")} = excluded.${s("plan")},
    ${s("periodEnd")} = excluded.${s("periodEnd")},
    ${s("cancelAt")} = excluded.${s("cancelAt")},
    ${s("eventAt")} = excluded.${s("eventAt")},
    ${s("updatedAt")} = now()
  where excluded.${s("eventAt")} >= b.${s("eventAt")};
  v_applied := found;
  return v_applied;
end;
$$;

-- Why checkout should not start for the tenant, or null: 'BILLING_ALREADY_SUBSCRIBED'
-- for an active, trialing or past due subscription, 'BILLING_EXTERNAL:<provider>'
-- when the app's public.billing_external_provider(tenant) names another
-- provider that bills the tenant (a marketplace, an invoice contract).
create or replace function ${fn("billing_checkout_block")}(tenant ${id})
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_provider text;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("BILLING_FORBIDDEN", "only the service role checks checkout")}
  end if;
  if exists (
    select 1 from ${table} b
    where b.${s("tenant")} = billing_checkout_block.tenant
      and b.${s("status")} in ('active', 'trialing', 'past_due')
  ) then
    return 'BILLING_ALREADY_SUBSCRIBED';
  end if;
  if to_regprocedure('public.billing_external_provider(${id})') is not null then
    execute 'select public.billing_external_provider($1)' into v_provider using billing_checkout_block.tenant;
    if v_provider is not null then
      return 'BILLING_EXTERNAL:' || v_provider;
    end if;
  end if;
  return null;
end;
$$;

revoke execute on function ${fn("billing_plan_of_price")}(text) from public, anon;
grant execute on function ${fn("billing_plan_of_price")}(text) to authenticated, service_role;
revoke execute on function ${fn("upsert_billing_subscription")}(${id}, text, text, text, timestamptz, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function ${fn("upsert_billing_subscription")}(${id}, text, text, text, timestamptz, timestamptz, timestamptz) to service_role;
revoke execute on function ${fn("billing_checkout_block")}(${id}) from public, anon, authenticated;
grant execute on function ${fn("billing_checkout_block")}(${id}) to service_role;
`;
}
