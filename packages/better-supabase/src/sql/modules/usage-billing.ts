import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  fail,
  lockTable,
  raise,
  SERVICE_CALLER,
  serviceGrant,
} from "../shared.ts";

/**
 * Whether the module renders the usage-to-invoice functions: the usage history
 * is kept (the rated quantities) and `invoices` is installed (the draft goes
 * there).
 */
function billsUsage(ctx: BlockSqlContext): boolean {
  return (
    ctx.mode !== "custom" &&
    ctx.flag("history", false) &&
    ctx.owns("history") &&
    ctx.installed("invoices")
  );
}

/**
 * `usage_meter_prices` (what one unit of a meter costs, in minor units, and how
 * many units each period includes), `usage_billed_periods` (one row per tenant
 * and period, so a period bills once) and `bill_usage_period`, which rates the
 * period's `usage_history` into a draft invoice.
 */
export function usageBillingSql(ctx: BlockSqlContext): string {
  if (!billsUsage(ctx)) {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const prices = ctx.table("prices");
  const billed = ctx.table("billed");
  const history = ctx.table("history");
  const pc = (logical: string): string => ctx.col("prices", logical);
  const bc = (logical: string): string => ctx.col("billed", logical);
  const hc = (logical: string): string => ctx.col("history", logical);
  const createInvoice = ctx.of("invoices").fn("create_invoice");

  const billedKey = sqlIdent(
    `bsb_${ctx.tableName("billed").name}_period_key`.replaceAll('"', ""),
  );

  return `
-- What one unit of a meter costs: unit_amount in minor units of currency
-- (ADR 0024), and how many units each billing period includes for free.
create table if not exists ${prices} (
  ${pc("meter")} text not null check (length(${pc("meter")}) between 1 and 100),
  ${pc("currency")} text not null check (${pc("currency")} ~ '^[A-Z]{3}$'),
  ${pc("unitAmount")} bigint not null check (${pc("unitAmount")} >= 0),
  ${pc("included")} numeric not null default 0 check (${pc("included")} >= 0),
  ${pc("label")} text check (length(${pc("label")}) <= 200),
  primary key (${pc("meter")}, ${pc("currency")})
);
${lockTable(prices)}

-- One row per tenant and billed period, so billing a period twice returns the
-- first invoice.
create table if not exists ${billed} (
  ${bc("tenant")} ${id} not null,
  ${bc("periodStart")} date not null,
  ${bc("periodEnd")} date not null,
  ${bc("invoice")} uuid not null,
  ${bc("billedAt")} timestamptz not null default now(),
  constraint ${billedKey} primary key (${bc("tenant")}, ${bc("periodStart")}, ${bc("periodEnd")})
);
${lockTable(billed)}

-- Sets the price of one meter in one currency; service role only.
create or replace function ${fn("set_usage_price")}(meter text, currency text, unit_amount bigint, included numeric default 0, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${SERVICE_CALLER} then
    ${fail("USAGE_FORBIDDEN", "Only the service role sets usage prices")}
  end if;
  insert into ${prices} as p (${pc("meter")}, ${pc("currency")}, ${pc("unitAmount")}, ${pc("included")}, ${pc("label")})
  values (set_usage_price.meter, upper(set_usage_price.currency), set_usage_price.unit_amount, coalesce(set_usage_price.included, 0), set_usage_price.label)
  on conflict (${pc("meter")}, ${pc("currency")}) do update
    set ${pc("unitAmount")} = excluded.${pc("unitAmount")}, ${pc("included")} = excluded.${pc("included")}, ${pc("label")} = excluded.${pc("label")};
  return jsonb_build_object('meter', set_usage_price.meter, 'currency', upper(set_usage_price.currency), 'unit_amount', set_usage_price.unit_amount);
exception when check_violation then
  ${raise("The usage price is invalid", "22023", "USAGE_PRICE_INVALID")}
end;
$$;

-- Rates the usage history of [period_start, period_end) (UTC days) by the meter
-- prices into one draft invoice: per meter, the quantity beyond the included
-- units times the unit amount. A meter without a price in the currency, or
-- with nothing beyond its included units, adds no line. Billing the same
-- period again returns the first invoice with created = false; a period with
-- nothing to bill returns invoice_id = null. attrs adds invoice fields
-- (company, contact, termsDays); service role only.
create or replace function ${fn("bill_usage_period")}(tenant ${id}, period_start date, period_end date, currency text default 'EUR', attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_currency text := upper(coalesce(bill_usage_period.currency, 'EUR'));
  v_existing uuid;
  v_lines jsonb;
  v_invoice jsonb;
  v_title text;
begin
  if not ${SERVICE_CALLER} then
    ${fail("USAGE_FORBIDDEN", "Only the service role bills usage")}
  end if;
  if bill_usage_period.period_start is null or bill_usage_period.period_end is null or bill_usage_period.period_end <= bill_usage_period.period_start then
    ${raise("The billing period must end after it starts", "22023", "USAGE_PERIOD_INVALID")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended(bill_usage_period.tenant::text || bill_usage_period.period_start::text || bill_usage_period.period_end::text, 0));
  select b.${bc("invoice")} into v_existing from ${billed} b
  where b.${bc("tenant")} = bill_usage_period.tenant
    and b.${bc("periodStart")} = bill_usage_period.period_start
    and b.${bc("periodEnd")} = bill_usage_period.period_end;
  if found then
    return jsonb_build_object('invoice_id', v_existing, 'created', false, 'lines', 0);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'description', coalesce(p.${pc("label")}, u.meter) || ' ' || bill_usage_period.period_start::text || ' to ' || bill_usage_period.period_end::text,
      'quantity', round(u.total - p.${pc("included")}, 4),
      'unitAmount', p.${pc("unitAmount")}
    ) order by u.meter), '[]'::jsonb)
  into v_lines
  from (
    select h.${hc("meter")} as meter, sum(h.${hc("quantity")}) as total
    from ${history} h
    where h.${hc("tenant")} = bill_usage_period.tenant
      and h.${hc("recordedAt")} >= (bill_usage_period.period_start::timestamp at time zone 'UTC')
      and h.${hc("recordedAt")} < (bill_usage_period.period_end::timestamp at time zone 'UTC')
    group by h.${hc("meter")}
  ) u
  join ${prices} p on p.${pc("meter")} = u.meter and p.${pc("currency")} = v_currency
  where round(u.total - p.${pc("included")}, 4) > 0;
  if jsonb_array_length(v_lines) = 0 then
    return jsonb_build_object('invoice_id', null, 'created', false, 'lines', 0);
  end if;
  v_title := 'Usage ' || bill_usage_period.period_start::text || ' to ' || bill_usage_period.period_end::text;
  v_invoice := ${createInvoice}(
    bill_usage_period.tenant,
    coalesce(bill_usage_period.attrs, '{}'::jsonb) || jsonb_build_object('title', v_title, 'currency', v_currency),
    v_lines
  );
  insert into ${billed} (${bc("tenant")}, ${bc("periodStart")}, ${bc("periodEnd")}, ${bc("invoice")})
  values (bill_usage_period.tenant, bill_usage_period.period_start, bill_usage_period.period_end, (v_invoice ->> 'id')::uuid);
  return jsonb_build_object('invoice_id', (v_invoice ->> 'id')::uuid, 'created', true, 'lines', jsonb_array_length(v_lines));
end;
$$;

${serviceGrant(`${fn("set_usage_price")}(text, text, bigint, numeric, text)`)}
${serviceGrant(`${fn("bill_usage_period")}(${id}, date, date, text, jsonb)`)}
`;
}

/** The contract entries of the usage-to-invoice functions, when rendered. */
export function usageBillingContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return billsUsage(ctx)
    ? [
        {
          name: "set_usage_price",
          args: ["text", "text", "bigint", "numeric", "text"],
          returns: "jsonb",
        },
        {
          name: "bill_usage_period",
          args: ["{id}", "date", "date", "text", "jsonb"],
          returns: "jsonb",
        },
      ]
    : [];
}
