import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  fail,
  lockTable,
  raise,
  SERVICE_CALLER,
  serviceGrant,
} from "../shared.ts";

/** The table of subscriptions that don't depend on Stripe. */
export const NATIVE_TABLE = {
  name: "billing_native_subscriptions",
  app: {},
  lifecycle: { tenant: "tenant" },
  columns: {
    id: "id",
    tenant: "tenant_id",
    plan: "plan",
    currency: "currency",
    unitAmount: "unit_amount",
    quantity: "quantity",
    interval: "billing_interval",
    status: "status",
    periodStart: "period_starts_at",
    periodEnd: "period_ends_at",
    canceledAt: "canceled_at",
    createdAt: "created_at",
  },
} as const;

/**
 * Subscriptions that live in Postgres: a plan, a price per period in minor
 * units (ADR 0024), a quantity and the current period. Stripe stays one
 * provider; these rows never need a Stripe object. `prorate_change` computes
 * what a mid-period change of price or quantity adds or credits and, when the
 * ledger block is installed, posts it as one balanced transaction.
 */
export function nativeSubscriptionsSql(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const table = ctx.table("native");
  const c = (logical: string): string => ctx.col("native", logical);
  const ledger = ctx.installed("ledger");

  const typeKey = sqlIdent(
    `bsb_${ctx.tableName("native").name}_interval_check`.replaceAll('"', ""),
  );

  const post = ledger
    ? `
  if v_net <> 0 then
    v_tx := ${ctx.of("ledger").fn("ledger_post")}(v_row.${c("tenant")}, 'billing.proration',
      jsonb_build_array(
        jsonb_build_object('account', ${ctx.of("ledger").fn("ledger_account_for")}(v_row.${c("tenant")}, 'receivable', 'billing:receivable:' || v_row.${c("currency")}, 'Subscription receivable ' || v_row.${c("currency")}, v_row.${c("currency")}, 0::smallint, null, null, null, true, null, 'billing', null), 'amount', v_net),
        jsonb_build_object('account', ${ctx.of("ledger").fn("ledger_account_for")}(v_row.${c("tenant")}, 'revenue', 'billing:proration:' || v_row.${c("currency")}, 'Subscription proration ' || v_row.${c("currency")}, v_row.${c("currency")}, 0::smallint, null, null, null, true, null, 'billing', null), 'amount', -v_net)),
      'billing-native-subscriptions', v_row.${c("id")}::text,
      'Proration for ' || v_row.${c("plan")},
      'billing.proration:' || v_row.${c("id")}::text || ':' || extract(epoch from v_at)::text,
      v_at,
      jsonb_build_object('plan', v_row.${c("plan")}, 'credit', v_credit, 'charge', v_charge));
  end if;`
    : "";

  return `
-- A subscription kept in Postgres: unit_amount is the price of one unit for one
-- billing_interval in minor units of currency, and
-- [period_starts_at, period_ends_at)
-- is the current period.
create table if not exists ${table} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id} not null,
  ${c("plan")} text not null check (length(${c("plan")}) between 1 and 100),
  ${c("currency")} text not null check (${c("currency")} ~ '^[A-Z]{3}$'),
  ${c("unitAmount")} bigint not null check (${c("unitAmount")} >= 0),
  ${c("quantity")} integer not null default 1 check (${c("quantity")} >= 0),
  ${c("interval")} text not null default 'month',
  ${c("status")} text not null default 'active' check (${c("status")} in ('active', 'canceled')),
  ${c("periodStart")} timestamptz not null,
  ${c("periodEnd")} timestamptz not null,
  ${c("canceledAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now(),
  constraint ${typeKey} check (${c("interval")} in ('week', 'month', 'year')),
  check (${c("periodEnd")} > ${c("periodStart")})
);
create index if not exists ${sqlIdent(`${ctx.tableName("native").name}_tenant_idx`.replaceAll('"', ""))} on ${table} (${c("tenant")}, ${c("status")});
${lockTable(table)}

-- Starts a subscription for tenant; its first period begins at started_at
-- (now by default). Service role only.
create or replace function ${fn("create_native_subscription")}(tenant ${id}, plan text, currency text, unit_amount bigint, quantity integer default 1, billing_interval text default 'month', started_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row ${table}%rowtype;
begin
  if not ${SERVICE_CALLER} then
    ${fail("BILLING_FORBIDDEN", "Only the service role creates native subscriptions")}
  end if;
  insert into ${table} (${c("tenant")}, ${c("plan")}, ${c("currency")}, ${c("unitAmount")}, ${c("quantity")}, ${c("interval")}, ${c("periodStart")}, ${c("periodEnd")})
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row.${c("id")}, 'plan', v_row.${c("plan")}, 'currency', v_row.${c("currency")},
    'unit_amount', v_row.${c("unitAmount")}::text, 'quantity', v_row.${c("quantity")}, 'interval', v_row.${c("interval")},
    'period_starts_at', v_row.${c("periodStart")}, 'period_ends_at', v_row.${c("periodEnd")});
exception when check_violation or invalid_text_representation then
  ${raise("The subscription is invalid", "22023", "BILLING_SUBSCRIPTION_INVALID")}
end;
$$;

-- Changes the price or the quantity of a subscription at an instant inside its
-- current period and returns what the change adds: credit is the unused part
-- of the old price, charge the remaining part of the new one, and net is
-- charge minus credit (negative for a downgrade). With the ledger block the
-- net posts as one transaction (receivable against proration revenue), once
-- per subscription and instant. Service role only.
create or replace function ${fn("prorate_change")}(subscription_id uuid, unit_amount bigint default null, quantity integer default null, at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${table}%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not ${SERVICE_CALLER} then
    ${fail("BILLING_FORBIDDEN", "Only the service role prorates subscription changes")}
  end if;
  select * into v_row from ${table} x where x.${c("id")} = prorate_change.subscription_id for update;
  if not found or v_row.${c("status")} <> 'active' then
    ${raise("The subscription does not exist or is canceled", "P0002", "BILLING_SUBSCRIPTION_NOT_FOUND")}
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row.${c("unitAmount")});
  v_new_quantity := coalesce(prorate_change.quantity, v_row.${c("quantity")});
  if v_new_amount < 0 or v_new_quantity < 0 then
    ${raise("The new price or quantity is negative", "22023", "BILLING_SUBSCRIPTION_INVALID")}
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row.${c("periodEnd")} - v_at) / extract(epoch from v_row.${c("periodEnd")} - v_row.${c("periodStart")})));
  v_credit := round(v_row.${c("unitAmount")} * v_row.${c("quantity")} * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;
${post}
  update ${table} set ${c("unitAmount")} = v_new_amount, ${c("quantity")} = v_new_quantity
    where ${c("id")} = v_row.${c("id")};
  return jsonb_build_object('subscription_id', v_row.${c("id")}, 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row.${c("currency")}, 'transaction_id', v_tx);
end;
$$;

-- Cancels a subscription. Service role only.
create or replace function ${fn("cancel_native_subscription")}(subscription_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${SERVICE_CALLER} then
    ${fail("BILLING_FORBIDDEN", "Only the service role cancels native subscriptions")}
  end if;
  update ${table} set ${c("status")} = 'canceled', ${c("canceledAt")} = now()
    where ${c("id")} = cancel_native_subscription.subscription_id and ${c("status")} = 'active';
  return found;
end;
$$;
${serviceGrant(`${fn("create_native_subscription")}(${id}, text, text, bigint, integer, text, timestamptz)`)}
${serviceGrant(`${fn("prorate_change")}(uuid, bigint, integer, timestamptz)`)}
${serviceGrant(`${fn("cancel_native_subscription")}(uuid)`)}
`;
}

/** The contract entries of the native subscription functions. */
export function nativeSubscriptionsContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return ctx.mode === "custom"
    ? []
    : [
        {
          name: "create_native_subscription",
          args: [
            "{id}",
            "text",
            "text",
            "bigint",
            "integer",
            "text",
            "timestamptz",
          ],
          returns: "jsonb",
        },
        {
          name: "prorate_change",
          args: ["uuid", "bigint", "integer", "timestamptz"],
          returns: "jsonb",
        },
        {
          name: "cancel_native_subscription",
          args: ["uuid"],
          returns: "boolean",
        },
      ];
}
