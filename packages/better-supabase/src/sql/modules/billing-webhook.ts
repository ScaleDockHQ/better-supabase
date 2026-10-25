import type { BlockSqlContext } from "../context.ts";
import type { PlanLookup } from "./billing-platform.ts";

import { sqlIdent } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";

/**
 * The subscription source: the Stripe Sync Engine, or a table the webhook
 * fills.
 */
export type SubscriptionSource = "sync-engine" | "webhook";

export function subscriptionSourceOf(ctx: BlockSqlContext): SubscriptionSource {
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
  ctx: BlockSqlContext,
  plans: PlanLookup | undefined,
): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const table = ctx.table("subscriptions");
  const s = (logical: string): string => ctx.col("subscriptions", logical);
  const has = (logical: string): boolean => ctx.has("subscriptions", logical);

  const optional = (logical: string, type: string): string =>
    has(logical) ? `\n  ${s(logical)} ${type},` : "";

  const written = (
    [
      ["tenant", "upsert_billing_subscription.tenant"],
      ["subscription", "upsert_billing_subscription.subscription"],
      [
        "status",
        ctx.cast(
          "subscriptions",
          "status",
          "upsert_billing_subscription.status",
        ),
      ],
      ["price", "upsert_billing_subscription.price"],
      [
        "plan",
        `${fn("billing_plan_of_price")}(upsert_billing_subscription.price)`,
      ],
      ["periodEnd", "upsert_billing_subscription.period_end"],
      ["cancelAt", "upsert_billing_subscription.cancel_at"],
      ["eventAt", "upsert_billing_subscription.event_at"],
    ] as const
  ).filter(([logical]) => has(logical));

  const updated = [
    ...written
      .filter(([logical]) => logical !== "tenant")
      .map(([logical]) => `${s(logical)} = excluded.${s(logical)}`),
    ...(has("updatedAt") ? [`${s("updatedAt")} = now()`] : []),
  ];

  const key = ctx.owns("subscriptions")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("subscriptions").name}_tenant_key`)} on ${table} (${s("tenant")});`;

  const planOf = plans
    ? `select p.${sqlIdent(plans.key)}::text from ${plans.table} p where p.${sqlIdent(plans.price)}::text = billing_plan_of_price.price limit 1`
    : "select null::text";

  return `
-- The tenant's subscription as the webhook last reported it. event_at is the
-- Stripe event's created time; an older event never overwrites a newer one.
create table if not exists ${table} (
  ${s("tenant")} ${id} primary key,
  ${s("subscription")} text not null,
  ${s("status")} text not null,${optional("price", "text")}${optional("plan", "text")}${optional("periodEnd", "timestamptz")}${optional("cancelAt", "timestamptz")}
  ${s("eventAt")} timestamptz not null${has("updatedAt") ? `,\n  ${s("updatedAt")} timestamptz not null default now()` : ""}
);${key}
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
  insert into ${table} as b (${written.map(([logical]) => s(logical)).join(", ")})
  values (${written.map(([, value]) => value).join(",\n    ")})
  on conflict (${s("tenant")}) do update set
    ${updated.join(",\n    ")}
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
