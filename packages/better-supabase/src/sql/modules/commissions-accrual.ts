import type { CommissionSql } from "./commissions-sql.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { commissionJson } from "./commissions-tables.ts";

/** The `ctx.record` statements for the events the commission functions write. */
function commissionRecords(k: CommissionSql): {
  readonly plan: (
    type: "commission_plan.created" | "commission_plan.updated",
  ) => string;
  readonly entry: (
    type: "commission.accrued" | "commission.reversed",
  ) => string;
} {
  const { ctx, p, c } = k;

  return {
    plan: (type) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', v_plan.${p("tenant")}, 'id', v_plan.${p("id")}, 'name', v_plan.${p("name")}, 'kind', v_plan.${p("kind")})`,
        subject: `'commission-plans/' || v_plan.${p("id")}::text`,
        tenant: `v_plan.${p("tenant")}`,
        audit: {
          category: "billing",
          targetType: "commission_plan",
          recordId: `v_plan.${p("id")}::text`,
          targetLabel: `v_plan.${p("name")}`,
          summary: `'${type === "commission_plan.created" ? "created" : "updated"} a commission plan'`,
        },
      }),
    entry: (type) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', v_entry.${c("tenant")}, 'id', v_entry.${c("id")}, 'planId', v_entry.${c("plan")}, 'sellerId', v_entry.${c("seller")}, 'sourceType', v_entry.${c("sourceType")}, 'sourceId', v_entry.${c("sourceId")}, 'amount', v_entry.${c("amount")}::text, 'currency', v_entry.${c("currency")})`,
        subject: `'commissions/' || v_entry.${c("id")}::text`,
        tenant: `v_entry.${c("tenant")}`,
        audit: {
          category: "billing",
          targetType: "commission",
          recordId: `v_entry.${c("id")}::text`,
          summary: `'${type === "commission.accrued" ? "accrued" : "reversed"} a commission'`,
        },
      }),
  };
}

/**
 * The ledger account of the commission expense, a seller's payable or the paid
 * total.
 */
export function commissionAccount(
  k: CommissionSql,
  tenant: string,
  kind: "expense" | "payable" | "paid",
  currency: string,
  seller?: string,
): string {
  const code =
    seller === undefined
      ? `'commissions:${kind}:' || ${currency}::text`
      : `'commissions:${kind}:' || ${seller}::text || ':' || ${currency}::text`;

  const names = {
    expense: "Commissions",
    payable: "Commissions payable",
    paid: "Commissions paid",
  } as const;

  return `${k.ledger.fn("ledger_account_for")}(${tenant}, '${kind}', ${code}, '${names[kind]}', ${currency}::text, 0::smallint, null, null, ${seller ?? "null"}, true, ${k.read}, 'commissions', null)`;
}

/** Plans, assignments and the accrual of a commission onto the ledger. */
export function commissionAccrual(k: CommissionSql): string {
  const { idType, fn, plans, assignments, entries, statements } = k;
  const { p, a, c, s, ledger } = k;
  const json = commissionJson(k);
  const records = commissionRecords(k);
  const le = (column: string): string => ledger.col("entries", column);
  const ledgerEntries = ledger.table("entries");

  const forbidden = (message: string): string =>
    fail("COMMISSION_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("COMMISSION_INVALID", message, "22023");

  return `
-- A commission as a bigint of minor units. A flat plan takes rate_bps of the
-- basis. A tiered plan takes each tier's bps of the part of the seller's
-- cumulative basis inside the tier, so prior is what the seller sold earlier
-- in the same month. The tiers are marginal and the last one has no upTo.
create or replace function ${fn("commission_amount")}(kind text, rate_bps integer, tiers jsonb, prior bigint, basis bigint)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tier jsonb;
  v_lower numeric := 0;
  v_upper numeric;
  v_before numeric := 0;
  v_after numeric := 0;
begin
  if commission_amount.kind = 'flat' then
    return round(commission_amount.basis * commission_amount.rate_bps / 10000.0)::bigint;
  end if;
  for v_tier in
    select t.value from jsonb_array_elements(commission_amount.tiers) with ordinality as t(value, n) order by t.n
  loop
    v_upper := (v_tier ->> 'upTo')::numeric;
    v_before := v_before + greatest(0, least(coalesce(v_upper, commission_amount.prior), commission_amount.prior) - v_lower) * (v_tier ->> 'bps')::numeric / 10000.0;
    v_after := v_after + greatest(0, least(coalesce(v_upper, commission_amount.prior + commission_amount.basis), commission_amount.prior + commission_amount.basis) - v_lower) * (v_tier ->> 'bps')::numeric / 10000.0;
    exit when v_upper is null;
    v_lower := v_upper;
  end loop;
  return round(v_after)::bigint - round(v_before)::bigint;
end;
$$;
${serviceGrant(`${fn("commission_amount")}(text, integer, jsonb, bigint, bigint)`)}

-- Whether tiers is a list of { upTo, bps } with rising upTo values and one
-- last tier without upTo.
create or replace function ${fn("commission_tiers_valid")}(tiers jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_tier jsonb;
  v_last numeric := 0;
  v_count integer;
  v_n integer := 0;
begin
  if jsonb_typeof(commission_tiers_valid.tiers) is distinct from 'array' then
    return false;
  end if;
  v_count := jsonb_array_length(commission_tiers_valid.tiers);
  if v_count = 0 or v_count > 50 then
    return false;
  end if;
  for v_tier in select t.value from jsonb_array_elements(commission_tiers_valid.tiers) with ordinality as t(value, n) order by t.n loop
    v_n := v_n + 1;
    if jsonb_typeof(v_tier) is distinct from 'object'
      or coalesce(v_tier ->> 'bps', '') !~ '^[0-9]{1,5}$' or (v_tier ->> 'bps')::integer > 10000 then
      return false;
    end if;
    if v_tier ->> 'upTo' is null then
      return v_n = v_count;
    end if;
    if v_tier ->> 'upTo' !~ '^[0-9]{1,18}$' or (v_tier ->> 'upTo')::numeric <= v_last then
      return false;
    end if;
    v_last := (v_tier ->> 'upTo')::numeric;
  end loop;
  return false;
end;
$$;
${serviceGrant(`${fn("commission_tiers_valid")}(jsonb)`)}

-- Creates a plan, or changes the one with plan_id. A flat plan sets rate_bps, a
-- tiered plan sets tiers. archived hides a plan from new assignments. Needs
-- commissions.manage.
create or replace function ${fn("save_commission_plan")}(tenant ${idType}, name text, kind text, rate_bps integer default null, tiers jsonb default null, plan_id uuid default null, archived boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_plan ${plans};
  v_created boolean := save_commission_plan.plan_id is null;
begin
  if not ${k.allowed("save_commission_plan.tenant", k.manage)} then
    ${forbidden("not allowed to manage commission plans")}
  end if;
  if nullif(trim(save_commission_plan.name), '') is null or length(trim(save_commission_plan.name)) > 200 then
    ${invalid("a plan needs a name of at most 200 characters")}
  end if;
  if save_commission_plan.kind = 'flat' then
    if save_commission_plan.rate_bps is null or save_commission_plan.rate_bps not between 0 and 10000 or save_commission_plan.tiers is not null then
      ${invalid("a flat plan takes rate_bps from 0 to 10000 and no tiers")}
    end if;
  elsif save_commission_plan.kind = 'tiered' then
    if save_commission_plan.rate_bps is not null or not ${fn("commission_tiers_valid")}(save_commission_plan.tiers) then
      ${invalid("a tiered plan takes rising { upTo, bps } tiers with a last tier that has no upTo")}
    end if;
  else
    ${invalid("a plan is flat or tiered")}
  end if;
  if v_created then
    insert into ${plans} (${p("tenant")}, ${p("name")}, ${p("kind")}, ${p("rateBps")}, ${p("tiers")}, ${p("archivedAt")})
    values (save_commission_plan.tenant, trim(save_commission_plan.name), save_commission_plan.kind, save_commission_plan.rate_bps, save_commission_plan.tiers,
      case when save_commission_plan.archived then now() end)
    returning * into v_plan;
    ${records.plan("commission_plan.created")}
  else
    update ${plans} x set ${p("name")} = trim(save_commission_plan.name), ${p("kind")} = save_commission_plan.kind,
      ${p("rateBps")} = save_commission_plan.rate_bps, ${p("tiers")} = save_commission_plan.tiers,
      ${p("archivedAt")} = case when save_commission_plan.archived then coalesce(x.${p("archivedAt")}, now()) end,
      ${p("updatedAt")} = now()
    where x.${p("id")} = save_commission_plan.plan_id and x.${p("tenant")} = save_commission_plan.tenant
    returning * into v_plan;
    if not found then
      ${fail("COMMISSION_PLAN_NOT_FOUND", "no such commission plan", "P0002")}
    end if;
    ${records.plan("commission_plan.updated")}
  end if;
  return ${json.plan("v_plan")};
end;
$$;
${userGrant(`${fn("save_commission_plan")}(${idType}, text, text, integer, jsonb, uuid, boolean)`)}

-- Puts a seller on a plan from starts_on until ends_on. With a subject the
-- plan applies to sales on that record only, and wins over the seller's own
-- plan. Needs commissions.manage.
create or replace function ${fn("assign_commission_plan")}(tenant ${idType}, plan_id uuid, seller_id uuid, subject_type text default null, subject_id text default null, starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${assignments};
begin
  if not ${k.allowed("assign_commission_plan.tenant", k.manage)} then
    ${forbidden("not allowed to assign commission plans")}
  end if;
  if assign_commission_plan.seller_id is null or (assign_commission_plan.subject_type is null) <> (assign_commission_plan.subject_id is null)
    or (assign_commission_plan.ends_on is not null and assign_commission_plan.ends_on < coalesce(assign_commission_plan.starts_on, current_date)) then
    ${invalid("an assignment needs a seller, a subject with both parts and a range that ends after it starts")}
  end if;
  if not exists (
    select 1 from ${plans} x
    where x.${p("id")} = assign_commission_plan.plan_id and x.${p("tenant")} = assign_commission_plan.tenant and x.${p("archivedAt")} is null
  ) then
    ${fail("COMMISSION_PLAN_NOT_FOUND", "no such open commission plan", "P0002")}
  end if;
  insert into ${assignments} (${a("tenant")}, ${a("plan")}, ${a("seller")}, ${a("subjectType")}, ${a("subjectId")}, ${a("startsOn")}, ${a("endsOn")})
  values (assign_commission_plan.tenant, assign_commission_plan.plan_id, assign_commission_plan.seller_id, assign_commission_plan.subject_type,
    assign_commission_plan.subject_id, coalesce(assign_commission_plan.starts_on, current_date), assign_commission_plan.ends_on)
  returning * into v_row;
  return ${json.assignment("v_row")};
end;
$$;
${userGrant(`${fn("assign_commission_plan")}(${idType}, uuid, uuid, text, text, date, date)`)}

-- Ends an assignment today. Needs commissions.manage.
create or replace function ${fn("end_commission_assignment")}(assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${assignments};
begin
  select * into v_row from ${assignments} x where x.${a("id")} = end_commission_assignment.assignment_id for update;
  if not found or not ${k.allowed(`v_row.${a("tenant")}`, k.read)} then
    ${fail("COMMISSION_ASSIGNMENT_NOT_FOUND", "no such assignment", "P0002")}
  end if;
  if not ${k.allowed(`v_row.${a("tenant")}`, k.manage)} then
    ${forbidden("not allowed to assign commission plans")}
  end if;
  update ${assignments} x set ${a("endsOn")} = greatest(current_date, x.${a("startsOn")})
  where x.${a("id")} = v_row.${a("id")} and (x.${a("endsOn")} is null or x.${a("endsOn")} > current_date)
  returning * into v_row;
  return ${json.assignment("v_row")};
end;
$$;
${userGrant(`${fn("end_commission_assignment")}(uuid)`)}

-- The plan that applies to a seller on a date: the one assigned for the
-- subject, else the seller's own. Null when the seller has none.
create or replace function ${fn("commission_plan_for")}(tenant ${idType}, seller_id uuid, subject_type text, subject_id text, on_date date)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x.${a("plan")} from ${assignments} x
  join ${plans} y on y.${p("id")} = x.${a("plan")} and y.${p("archivedAt")} is null
  where x.${a("tenant")} = commission_plan_for.tenant and x.${a("seller")} = commission_plan_for.seller_id
    and x.${a("startsOn")} <= commission_plan_for.on_date and (x.${a("endsOn")} is null or x.${a("endsOn")} >= commission_plan_for.on_date)
    and (x.${a("subjectType")} is null or (x.${a("subjectType")} = commission_plan_for.subject_type and x.${a("subjectId")} = commission_plan_for.subject_id))
  order by (x.${a("subjectType")} is not null) desc, x.${a("startsOn")} desc, x.${a("createdAt")} desc
  limit 1
$$;
${serviceGrant(`${fn("commission_plan_for")}(${idType}, uuid, text, text, date)`)}

-- Accrues a commission without checking the caller: the invoice trigger and
-- accrue_commission call it. It returns the earlier commission of the same
-- seller on the same record, or null when the seller has no plan or the
-- commission rounds to nothing. The ledger moves the amount from the
-- commission expense account to the seller's payable account.
create or replace function ${fn("commission_accrue")}(tenant ${idType}, seller_id uuid, source_type text, source_id text, basis bigint, currency text, occurred_on date default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_entry ${entries};
  v_plan ${plans};
  v_on date := coalesce(commission_accrue.occurred_on, current_date);
  v_currency text := upper(commission_accrue.currency);
  v_prior bigint;
  v_amount bigint;
  v_tx uuid;
begin
  if commission_accrue.seller_id is null or nullif(trim(commission_accrue.source_type), '') is null
    or nullif(trim(commission_accrue.source_id), '') is null or coalesce(commission_accrue.basis, 0) <= 0
    or v_currency !~ '^[A-Z]{3}$' then
    ${invalid("a commission needs a seller, a source, a positive basis and a currency code")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended(commission_accrue.tenant::text || commission_accrue.seller_id::text, 0));
  select * into v_entry from ${entries} x
  where x.${c("tenant")} = commission_accrue.tenant and x.${c("sourceType")} = commission_accrue.source_type
    and x.${c("sourceId")} = commission_accrue.source_id and x.${c("seller")} = commission_accrue.seller_id;
  if found then
    return ${json.entry("v_entry")};
  end if;
  select y.* into v_plan from ${plans} y
  where y.${p("id")} = ${fn("commission_plan_for")}(commission_accrue.tenant, commission_accrue.seller_id, commission_accrue.subject_type, commission_accrue.subject_id, v_on);
  if not found then
    return null;
  end if;
  select coalesce(sum(x.${c("basis")}), 0) into v_prior from ${entries} x
  where x.${c("tenant")} = commission_accrue.tenant and x.${c("seller")} = commission_accrue.seller_id
    and x.${c("plan")} = v_plan.${p("id")} and x.${c("currency")} = v_currency and x.${c("status")} = 'accrued'
    and date_trunc('month', x.${c("occurredOn")}::timestamp) = date_trunc('month', v_on::timestamp);
  v_amount := ${fn("commission_amount")}(v_plan.${p("kind")}, v_plan.${p("rateBps")}, v_plan.${p("tiers")}, v_prior, commission_accrue.basis);
  if v_amount <= 0 then
    return null;
  end if;
  v_tx := ${ledger.fn("ledger_post")}(commission_accrue.tenant, 'commission.accrual',
    jsonb_build_array(
      jsonb_build_object('account', ${commissionAccount(k, "commission_accrue.tenant", "expense", "v_currency")}, 'amount', (-v_amount)::text),
      jsonb_build_object('account', ${commissionAccount(k, "commission_accrue.tenant", "payable", "v_currency", "commission_accrue.seller_id")}, 'amount', v_amount::text)),
    'commissions', commission_accrue.source_type || '/' || commission_accrue.source_id, null,
    'commission:' || commission_accrue.source_type || ':' || commission_accrue.source_id || ':' || commission_accrue.seller_id::text,
    v_on::timestamptz,
    jsonb_build_object('sellerId', commission_accrue.seller_id, 'planId', v_plan.${p("id")}));
  insert into ${entries} (${c("tenant")}, ${c("plan")}, ${c("seller")}, ${c("sourceType")}, ${c("sourceId")}, ${c("basis")}, ${c("amount")}, ${c("currency")}, ${c("occurredOn")}, ${c("ledgerTransaction")})
  values (commission_accrue.tenant, v_plan.${p("id")}, commission_accrue.seller_id, commission_accrue.source_type, commission_accrue.source_id,
    commission_accrue.basis, v_amount, v_currency, v_on, v_tx)
  returning * into v_entry;
  ${records.entry("commission.accrued")}
  return ${json.entry("v_entry")};
end;
$$;
${serviceGrant(`${fn("commission_accrue")}(${idType}, uuid, text, text, bigint, text, date, text, text)`)}

-- Accrues a commission for a seller on a record the app sold, such as an order
-- or a payment the invoice trigger does not see. basis is the amount in minor
-- units the plan takes its percentage of. Calling it again for the same seller
-- and record returns the first commission. Needs commissions.write.
create or replace function ${fn("accrue_commission")}(tenant ${idType}, seller_id uuid, source_type text, source_id text, basis bigint, currency text, occurred_on date default null, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not ${k.allowed("accrue_commission.tenant", k.write)} then
    ${forbidden("not allowed to accrue commissions")}
  end if;
  return ${fn("commission_accrue")}(accrue_commission.tenant, accrue_commission.seller_id, accrue_commission.source_type, accrue_commission.source_id,
    accrue_commission.basis, accrue_commission.currency, accrue_commission.occurred_on, accrue_commission.subject_type, accrue_commission.subject_id);
end;
$$;
${userGrant(`${fn("accrue_commission")}(${idType}, uuid, text, text, bigint, text, date, text, text)`)}

-- Reverses an accrued commission, for example after a refund. The ledger gets
-- the opposite transaction. A commission on a finalized or paid statement
-- can't be reversed. Needs commissions.manage.
create or replace function ${fn("reverse_commission")}(commission_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_entry ${entries};
  v_status text;
begin
  select * into v_entry from ${entries} x where x.${c("id")} = reverse_commission.commission_id for update;
  if not found or not ${k.allowed(`v_entry.${c("tenant")}`, k.read)} then
    ${fail("COMMISSION_NOT_FOUND", "no such commission", "P0002")}
  end if;
  if not ${k.allowed(`v_entry.${c("tenant")}`, k.manage)} then
    ${forbidden("not allowed to reverse commissions")}
  end if;
  if v_entry.${c("status")} = 'reversed' then
    return ${json.entry("v_entry")};
  end if;
  if v_entry.${c("statement")} is not null then
    select y.${s("status")} into v_status from ${statements} y where y.${s("id")} = v_entry.${c("statement")};
    if v_status <> 'open' then
      ${fail("COMMISSION_STATEMENT_LOCKED", "the commission is on a statement that is no longer open", "55000")}
    end if;
  end if;
  perform ${ledger.fn("ledger_post")}(v_entry.${c("tenant")}, 'commission.reversal',
    (select jsonb_agg(jsonb_build_object('account', e.${le("account")}, 'amount', (-e.${le("amount")})::text) order by e.${le("createdAt")}, e.${le("id")})
      from ${ledgerEntries} e where e.${le("transaction")} = v_entry.${c("ledgerTransaction")}),
    'commissions', v_entry.${c("sourceType")} || '/' || v_entry.${c("sourceId")}, nullif(trim(reverse_commission.reason), ''),
    'commission-reversal:' || v_entry.${c("id")}::text, null,
    jsonb_build_object('reversal', true, 'reason', nullif(trim(reverse_commission.reason), '')),
    v_entry.${c("ledgerTransaction")});
  update ${entries} x set ${c("status")} = 'reversed', ${c("reversedAt")} = now()
  where x.${c("id")} = v_entry.${c("id")} returning * into v_entry;
  if v_entry.${c("statement")} is not null then
    update ${statements} y set ${s("total")} = coalesce((select sum(x.${c("amount")}) from ${entries} x where x.${c("statement")} = y.${s("id")} and x.${c("status")} = 'accrued'), 0)
    where y.${s("id")} = v_entry.${c("statement")};
  end if;
  ${records.entry("commission.reversed")}
  return ${json.entry("v_entry")};
end;
$$;
${userGrant(`${fn("reverse_commission")}(uuid, text)`)}
`;
}
