import type { BlockSqlContext } from "../context.ts";

import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { linked } from "./banking-sql.ts";
import { taxSql } from "./tax-sql.ts";

/**
 * `prepare_tax_return`, `file_tax_return` and `list_tax_returns`: the box
 * totals and the EU sales list (ICP) of a period, from the tax lines the issued
 * invoices of the period carry.
 *
 * A credit note counts negative. A purchase bill counts toward the boxes of its
 * tax code like a sales invoice and toward `purchaseTax` instead of `salesTax`.
 * Lines whose code names no return box, or that have no code, add to
 * `unassigned`, so a period always adds up to the invoices.
 */
export function taxReturns(ctx: BlockSqlContext): string {
  const inv = linked(ctx, "invoices");

  const q = taxSql(ctx);
  const { c, l, t, e, fn } = q;
  const i = (column: string): string => inv?.col("invoices", column) ?? column;
  const idType = ctx.idType;

  const direction = inv?.has("invoices", "direction")
    ? `coalesce(x.${i("direction")}::text, 'sales')`
    : `'sales'`;

  const entity =
    inv !== undefined && hasLegalEntityColumn(inv, "invoices")
      ? "x.legal_entity_id"
      : "null::uuid";

  const recordReturn = (row: string): string =>
    ctx.record({
      type: "tax_return.prepared",
      payload: `jsonb_build_object('organizationId', ${row}.${t("tenant")}, 'id', ${row}.${t("id")}, 'period', ${row}.${t("period")}, 'periodStart', ${row}.${t("periodStart")}, 'periodEnd', ${row}.${t("periodEnd")}, 'legalEntityId', ${row}.${t("legalEntity")}, 'netTax', ${row}.${t("boxes")} ->> 'netTax', 'currency', ${row}.${t("currency")})`,
      subject: `'tax-returns/' || ${row}.${t("id")}::text`,
      tenant: `${row}.${t("tenant")}`,
      audit: {
        category: "billing",
        targetType: "tax_return",
        recordId: `${row}.${t("id")}::text`,
        targetLabel: `${row}.${t("period")}`,
        summary: "'Prepared a tax return'",
      },
    });

  const source =
    inv === undefined
      ? "  select '[]'::jsonb"
      : `  select coalesce(jsonb_agg(jsonb_build_object(
    'currency', x.${i("currency")}, 'sign', case when x.${i("kind")}::text = 'credit_note' then -1 else 1 end,
    'direction', ${direction}, 'invoiceId', x.${i("id")}, 'codeType', y.${c("type")},
    'boxes', coalesce(to_jsonb(y.${c("returnBoxes")}), '[]'::jsonb), 'net', z.${l("net")}, 'tax', z.${l("tax")},
    'vat', z.${l("customerVat")})), '[]'::jsonb)
  from ${q.lines} z
  join ${inv.table("invoices")} x on x.${i("id")} = z.${l("parent")}
  left join ${q.codes} y on y.${c("id")} = z.${l("taxCodeId")}
  where z.${l("tenant")} = tax_return_source.tenant
    and x.${i("status")}::text not in ('draft', 'void')
    and x.${i("issuedOn")} >= tax_return_source.since and x.${i("issuedOn")} <= tax_return_source.until
    and (tax_return_source.legal_entity_id is null or ${entity} = tax_return_source.legal_entity_id)`;

  return `
-- Prepares the tax return of a period from the tax lines of the issued
-- invoices (not drafts or void ones) dated in it: the totals per return box,
-- what no box takes, the sales and purchase tax, and the EU sales list of
-- intra-EU sales per customer VAT number. A draft return of the same period
-- (and legal entity) is prepared again; a filed one is refused. currency is
-- needed only when invoices of several currencies fall in the period.
create or replace function ${fn("prepare_tax_return")}(tenant ${idType}, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
  v_currencies text[];
  v_currency text;
  v_boxes jsonb;
  v_issues jsonb;
  v_sales bigint;
  v_purchase bigint;
  v_row ${q.returns}%rowtype;
begin
  if not ${q.allowed("prepare_tax_return.tenant", q.manage)} then
    ${q.forbidden("not allowed to prepare tax returns")}
  end if;
  if prepare_tax_return.since is null or prepare_tax_return.until is null or prepare_tax_return.until < prepare_tax_return.since then
    ${q.returnInvalid("a return needs a period with a start on or before its end")}
  end if;
  if prepare_tax_return.currency is not null and upper(prepare_tax_return.currency) !~ '^[A-Z]{3}$' then
    ${q.returnInvalid("currency must be a three letter code")}
  end if;
  select ${fn("tax_return_source")}(prepare_tax_return.tenant, prepare_tax_return.since, prepare_tax_return.until, prepare_tax_return.legal_entity_id) into v_rows;
  select coalesce(array_agg(distinct r.currency order by r.currency), '{}') into v_currencies
  from jsonb_to_recordset(v_rows) r(currency text);
  v_currency := upper(prepare_tax_return.currency);
  if v_currency is null then
    if cardinality(v_currencies) > 1 then
      ${fail("TAX_RETURN_CURRENCY_MIXED", "invoices of several currencies fall in the period; name the currency to prepare the return for", "22023")}
    end if;
    v_currency := v_currencies[1];
  end if;
  select * into v_row from ${q.returns} y
  where y.${t("tenant")} = prepare_tax_return.tenant
    and y.${t("legalEntity")} is not distinct from prepare_tax_return.legal_entity_id
    and y.${t("periodStart")} = prepare_tax_return.since and y.${t("periodEnd")} = prepare_tax_return.until
  for update;
  if v_row.${t("id")} is not null and v_row.${t("status")} = 'filed' then
    ${fail("TAX_RETURN_FILED", "a filed tax return can't be prepared again", "55000")}
  end if;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency
  ), boxed as (
    select b.box, sum(s.sign * s.net) as base, sum(s.sign * s.tax) as tax
    from src s cross join lateral jsonb_array_elements_text(case when jsonb_array_length(s.boxes) = 0 then '[]'::jsonb else s.boxes end) b(box)
    group by b.box
  ), loose as (
    select coalesce(sum(s.sign * s.net), 0) as base, coalesce(sum(s.sign * s.tax), 0) as tax, count(*) as lines
    from src s where jsonb_array_length(s.boxes) = 0
  )
  select jsonb_build_object(
      'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box) from boxed x), '[]'::jsonb),
      'unassigned', (select jsonb_build_object('base', u.base::text, 'tax', u.tax::text, 'lines', u.lines) from loose u)
    ),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'sales'), 0),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'purchase'), 0)
  into v_boxes, v_sales, v_purchase
  from src s;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency and r.direction = 'sales' and r."codeType" in ('intra_eu_goods', 'intra_eu_services')
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', 'EU_SALES_VAT_INVALID', 'invoiceId', s."invoiceId", 'message', 'an intra-EU sale needs the customer''s VAT number, starting with a country code') order by s."invoiceId"), '[]'::jsonb)
  into v_issues
  from src s
  where s.vat is null or upper(s.vat) !~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$';
  v_boxes := v_boxes || jsonb_build_object(
    'salesTax', v_sales::text,
    'purchaseTax', v_purchase::text,
    'netTax', (v_sales - v_purchase)::text,
    'currency', v_currency,
    'issues', v_issues
  );
  if v_row.${t("id")} is null then
    insert into ${q.returns} (${t("tenant")}, ${t("legalEntity")}, ${t("period")}, ${t("periodStart")}, ${t("periodEnd")}, ${t("currency")}, ${t("boxes")}, ${t("preparedBy")})
    values (prepare_tax_return.tenant, prepare_tax_return.legal_entity_id,
      coalesce(nullif(trim(prepare_tax_return.period), ''), to_char(prepare_tax_return.since, 'YYYY-MM-DD') || '/' || to_char(prepare_tax_return.until, 'YYYY-MM-DD')),
      prepare_tax_return.since, prepare_tax_return.until, v_currency, v_boxes, (select auth.uid()))
    returning * into v_row;
  else
    delete from ${q.euLines} y where y.${e("taxReturn")} = v_row.${t("id")};
    update ${q.returns} y set ${t("period")} = coalesce(nullif(trim(prepare_tax_return.period), ''), y.${t("period")}),
      ${t("currency")} = v_currency, ${t("boxes")} = v_boxes, ${t("preparedBy")} = (select auth.uid()),
      ${t("preparedAt")} = now(), ${t("updatedAt")} = now()
    where y.${t("id")} = v_row.${t("id")}
    returning * into v_row;
  end if;
  insert into ${q.euLines} (${e("tenant")}, ${e("taxReturn")}, ${e("customerVat")}, ${e("country")}, ${e("kind")}, ${e("amount")}, ${e("currency")}, ${e("invoiceCount")})
  select v_row.${t("tenant")}, v_row.${t("id")}, upper(regexp_replace(s.vat, '[ .-]', '', 'g')), left(upper(s.vat), 2),
    case when s."codeType" = 'intra_eu_goods' then 'goods' else 'services' end,
    sum(s.sign * s.net), v_currency, count(distinct s."invoiceId")::integer
  from jsonb_to_recordset(v_rows) s(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, vat text, net bigint)
  where s.currency is not distinct from v_currency and s.direction = 'sales' and s."codeType" in ('intra_eu_goods', 'intra_eu_services')
    and s.vat is not null and upper(s.vat) ~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$'
  group by 3, 4, 5
  having count(*) > 0;
  ${recordReturn("v_row")}
  return ${q.returnJson("v_row")};
end;
$$;
${userGrant(`${fn("prepare_tax_return")}(${idType}, date, date, uuid, text, text)`)}

-- The tax lines of the issued invoices dated in a period, one object per line.
-- Internal: prepare_tax_return reads it.
create or replace function ${fn("tax_return_source")}(tenant ${idType}, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
${source}
$$;
revoke execute on function ${fn("tax_return_source")}(${idType}, date, date, uuid) from public, anon, authenticated;
grant execute on function ${fn("tax_return_source")}(${idType}, date, date, uuid) to service_role;

-- Files a prepared return: its figures no longer change.
create or replace function ${fn("file_tax_return")}(return_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${q.returns}%rowtype;
begin
  select * into v_row from ${q.returns} y where y.${t("id")} = file_tax_return.return_id for update;
  if v_row.${t("id")} is null then
    ${q.returnMissing}
  end if;
  if not ${q.allowed(`v_row.${t("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to file tax returns")}
  end if;
  if v_row.${t("status")} = 'filed' then
    return ${q.returnJson("v_row")};
  end if;
  update ${q.returns} y set ${t("status")} = 'filed', ${t("filedAt")} = now(), ${t("updatedAt")} = now()
  where y.${t("id")} = v_row.${t("id")}
  returning * into v_row;
  return ${q.returnJson("v_row")};
end;
$$;
${userGrant(`${fn("file_tax_return")}(uuid)`)}

create or replace function ${fn("list_tax_returns")}(tenant ${idType})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not ${q.allowed("list_tax_returns.tenant", q.read)} then
    ${q.forbidden("not allowed to read tax returns")}
  end if;
  return (
    select coalesce(jsonb_agg(${q.returnJson("x")} order by x.${t("periodStart")} desc, x.${t("periodEnd")} desc), '[]'::jsonb)
    from ${q.returns} x where x.${t("tenant")} = list_tax_returns.tenant
  );
end;
$$;
${userGrant(`${fn("list_tax_returns")}(${idType})`)}
`;
}
