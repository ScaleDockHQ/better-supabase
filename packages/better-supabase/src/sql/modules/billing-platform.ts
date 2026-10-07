import type { ModuleContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { SERVICE_CALLER } from "../shared.ts";

export interface PlanLookup {
  readonly table: string;
  readonly key: string;
  readonly price: string;
}

const instant = (value: string): string =>
  `(case jsonb_typeof(${value}) when 'number' then to_timestamp((${value})::text::double precision) when 'string' then (${value} #>> '{}')::timestamptz end)`;

export function platformLists(
  ctx: ModuleContext,
  viewAll: string,
  plans: PlanLookup | undefined,
): string {
  const id = ctx.idType;
  const t = ctx.table("customers");
  const c = (logical: string): string => ctx.col("customers", logical);
  const fn = (name: string): string => ctx.fn(name);
  const plan = plans
    ? `(select p.${sqlIdent(plans.key)}::text from ${plans.table} p where p.${sqlIdent(plans.price)}::text = r.price limit 1)`
    : "null::text";
  const guard = `if not (${SERVICE_CALLER} or ${viewAll}) then
    raise exception 'Not allowed to read every tenant''s billing' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;`;
  return `
create or replace function ${fn("billing_platform_subscriptions")}()
returns table (
  tenant ${id},
  customer text,
  subscription text,
  status text,
  price text,
  plan text,
  quantity bigint,
  amount bigint,
  currency text,
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
begin
  ${guard}
  if to_regclass('stripe.subscriptions') is null then
    return;
  end if;
  return query execute format($q$
    select r.tenant, r.customer, r.subscription, r.status, r.price, ${plan}, r.quantity,
      r.unit_amount * coalesce(r.quantity, 1), r.currency, r.current_period_end, r.cancel_at_period_end, r.created
    from (
      select distinct on (b.${c("tenant")}) b.${c("tenant")} as tenant, b.${c("customer")}::text as customer,
        s.id::text as subscription, x.row ->> 'status' as status,
        coalesce(it.item -> 'price' ->> 'id', it.item ->> 'price') as price,
        (it.item ->> 'quantity')::bigint as quantity,
        coalesce((pr.price_row ->> 'unit_amount')::bigint, (it.item -> 'price' ->> 'unit_amount')::bigint) as unit_amount,
        coalesce(pr.price_row ->> 'currency', it.item -> 'price' ->> 'currency', x.row ->> 'currency') as currency,
        coalesce(${instant("x.row -> 'current_period_end'")}, ${instant("it.item -> 'current_period_end'")}) as current_period_end,
        coalesce((x.row ->> 'cancel_at_period_end')::boolean, false) as cancel_at_period_end,
        ${instant("x.row -> 'created'")} as created
      from ${t} b
      join stripe.subscriptions s on s.customer = b.${c("customer")}
      cross join lateral (select to_jsonb(s.*) as row) x
      %s
      %s
      order by b.${c("tenant")}, (x.row ->> 'status' in ('active', 'trialing', 'past_due')) desc, ${instant("x.row -> 'created'")} desc nulls last
    ) r
  $q$, items, prices);
end;
$$;

create or replace function ${fn("billing_platform_invoices")}()
returns table (
  tenant ${id},
  customer text,
  invoice text,
  subscription text,
  number text,
  status text,
  amount_due bigint,
  amount_paid bigint,
  total bigint,
  currency text,
  due_date timestamptz,
  created timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  ${guard}
  if to_regclass('stripe.invoices') is null then
    return;
  end if;
  return query execute $q$
    select b.${c("tenant")}, b.${c("customer")}::text, v.id::text,
      coalesce(x.row -> 'subscription' ->> 'id', x.row ->> 'subscription'),
      x.row ->> 'number', x.row ->> 'status',
      (x.row ->> 'amount_due')::bigint, (x.row ->> 'amount_paid')::bigint, (x.row ->> 'total')::bigint,
      x.row ->> 'currency',
      ${instant("x.row -> 'due_date'")},
      ${instant("x.row -> 'created'")}
    from ${t} b
    join stripe.invoices v on v.customer = b.${c("customer")}
    cross join lateral (select to_jsonb(v.*) as row) x
  $q$;
end;
$$;
revoke execute on function ${fn("billing_platform_subscriptions")}() from public, anon;
grant execute on function ${fn("billing_platform_subscriptions")}() to authenticated, service_role;
revoke execute on function ${fn("billing_platform_invoices")}() from public, anon;
grant execute on function ${fn("billing_platform_invoices")}() to authenticated, service_role;
`;
}
