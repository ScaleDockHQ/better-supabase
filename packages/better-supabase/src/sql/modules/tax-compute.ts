import type { BlockSqlContext } from "../context.ts";

import { countedLine, declared, lineColumn } from "../line-items-sql.ts";
import { hasLegalEntityColumn } from "../numbering-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { linked } from "./banking-sql.ts";
import { invoiceOptIn } from "./invoices-functions.ts";
import { taxSql } from "./tax-sql.ts";

/**
 * `compute_document_tax`: the tax of a document's lines per code.
 *
 * Every line rounds once to its amount after the line discount. With prices
 * that include tax, the tax is the part of an amount at `rate / (10000 +
 * rate)`; otherwise it is added on top. The document discount (basis points of
 * the net plus a fixed amount, at most the net) is spread over the groups in
 * proportion, the last group taking the rounding, and each group's tax drops by
 * the tax on its share.
 *
 * - Margin scheme (type `margin`): the price is always tax inclusive and the tax
 *   is due on the margin, price less cost (`quantity * unitCost`, never below
 *   zero): `round(margin * rate / (10000 + rate))`. The document shows no tax
 *   amount (`showTaxAmount` is false).
 * - Credit restriction: `credit_restriction_bps` is the part of each base the tax
 *   doesn't apply to, so the tax is computed on `base * (10000 - bps) /
 *   10000`.
 * - Codes that charge no rate (exempt, zero, reverse charge, intra-EU, export)
 *   count 0%.
 */
export function taxCompute(ctx: BlockSqlContext): string {
  const q = taxSql(ctx);
  const { c, fn } = q;

  const denominator = (rate: string): string =>
    `(case when v_inclusive then 10000.0 + ${rate} else 10000.0 end)`;

  return `
-- The tax of lines [{ quantity?, unitAmount, discountBps?, taxCodeId?,
-- taxRateBps?, unitCost? }] on a day: { groups: [{ taxCodeId, code, type,
-- rateBps, net, tax, gross, discount, showTax }], subtotal, taxTotal, total,
-- discountTotal, showTaxAmount }, amounts as text. A line's rate is its tax
-- code's rate on on_date; taxRateBps stands in when no rate covers the day or
-- the line has no code. It runs as the caller, so a caller only prices lines with
-- the tax codes they can read; compute_document_tax and the invoice issue call it.
create or replace function ${fn("tax_compute_lines")}(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    ${q.computeInvalid("lines must be a list")}
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    ${q.computeInvalid("a credit restriction is 0 to 10000 basis points")}
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    ${q.computeInvalid("every line must be an object")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from ${q.codes} y where y.${c("id")}::text = x.value ->> 'taxCodeId')
  ) then
    ${q.codeMissing}
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join ${q.codes} y on y.${c("id")}::text = x.value ->> 'taxCodeId'
    where y.${c("type")} = 'margin' and x.value ->> 'unitCost' is null
  ) then
    ${fail("TAX_MARGIN_COST_REQUIRED", "a margin scheme line needs the unitCost of what it was bought for", "22023")}
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y.${c("id")} as code_id,
      y.${c("code")} as code,
      coalesce(y.${c("type")}, 'sales') as type,
      case
        when y.${c("id")} is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y.${c("type")} not in (${q.rateTypeList}) then 0
        else coalesce(${fn("tax_rate_on")}(y.${c("id")}, v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join ${q.codes} y on y.${c("id")}::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, round(p.amount * p.disc_bps / 10000.0) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * ${denominator("n.rate")}))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    ${q.rateInvalid("no rate of a line's tax code covers the date, and the line gives no taxRateBps")}
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * ${denominator("s.rate")}))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    ${q.computeInvalid("quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid")}
end;
$$;
${userGrant(`${fn("tax_compute_lines")}(jsonb, date, boolean, integer, integer, bigint)`)}

-- The tax of a document's lines: see tax_compute_lines for the lines and the
-- result. The codes are the caller's (row level security applies).
create or replace function ${fn("compute_document_tax")}(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${fn("tax_compute_lines")}(compute_document_tax.lines, compute_document_tax.on_date, compute_document_tax.prices_include_tax, compute_document_tax.credit_restriction_bps, 0, 0)
$$;
${userGrant(`${fn("compute_document_tax")}(jsonb, date, boolean, integer)`)}
${issueInvoiceTax(ctx)}`;
}

/**
 * `issue_invoice_tax`: resolves an invoice's lines to tax codes, then writes
 * the tax per code into `invoice_tax_lines`. The invoice block calls it from
 * `issue_invoice`, before the invoice freezes.
 */
function issueInvoiceTax(ctx: BlockSqlContext): string {
  const inv = linked(ctx, "invoices");

  if (inv === undefined) {
    return "";
  }

  const q = taxSql(ctx);
  const { c, l, fn } = q;
  const i = (column: string): string => inv.col("invoices", column);
  const il = (column: string): string => inv.col("lines", column);
  const ids = declared(inv, "lines", "taxCodeId");
  const costs = declared(inv, "lines", "unitCost");
  const lineCode = declared(inv, "lines", "taxCode");

  const parentOf = (column: string, otherwise: string): string =>
    inv.has("invoices", column) ? `v_inv.${i(column)}` : otherwise;

  const optIn = (column: string, otherwise: string): string =>
    invoiceOptIn(inv, column) ? `v_inv.${i(column)}` : otherwise;

  const entity = hasLegalEntityColumn(inv, "invoices")
    ? "v_inv.legal_entity_id"
    : "null::uuid";

  const contacts = linked(ctx, "contacts");

  const vat =
    contacts !== undefined &&
    inv.has("invoices", "companyId") &&
    contacts.has("companies", "vatId")
      ? `(select nullif(trim(z.${contacts.col("companies", "vatId")}), '') from ${contacts.table("companies")} z where z.${contacts.col("companies", "id")}::text = v_inv.${i("companyId")}::text)`
      : "null::text";

  const resolve = ids
    ? `
  -- A line that names a code by text takes the code's id and keeps its rate.
  ${
    lineCode
      ? `update ${inv.table("lines")} x set ${il("taxCodeId")} = ${fn("resolve_tax_code")}(v_inv.${i("tenant")}, x.${il("taxCode")}, ${entity})
  where x.${il("parent")} = v_inv.${i("id")} and x.${il("taxCodeId")} is null and x.${il("taxCode")} is not null
    and ${fn("resolve_tax_code")}(v_inv.${i("tenant")}, x.${il("taxCode")}, ${entity}) is not null;`
      : ""
  }
  -- A line that names a code by id takes the code's text and its rate on the
  -- issue date; a margin scheme line charges nothing on top of its price.
  update ${inv.table("lines")} x set
    ${lineCode ? `${il("taxCode")} = y.${c("code")},` : ""}
    ${il("taxRateBps")} = case when y.${c("type")} = 'margin' then 0 else coalesce(${fn("tax_rate_on")}(y.${c("id")}, issue_invoice_tax.on_date), x.${il("taxRateBps")}) end
  from ${q.codes} y
  where x.${il("parent")} = v_inv.${i("id")} and x.${il("taxCodeId")} = y.${c("id")};`
    : "";

  const quantity = declared(inv, "lines", "periods")
    ? `x.${il("quantity")} * coalesce(x.${il("periods")}, 1)`
    : `x.${il("quantity")}`;

  const line = `jsonb_build_object('quantity', ${quantity}, 'unitAmount', x.${il("unitAmount")}::text, 'discountBps', ${lineColumn(inv, "lines", "x", "discountBps")}, 'taxRateBps', ${lineColumn(inv, "lines", "x", "taxRateBps")}${ids ? `, 'taxCodeId', x.${il("taxCodeId")}` : ""}${costs ? `, 'unitCost', x.${il("unitCost")}::text` : ""})`;

  return `
-- Writes the tax of an invoice per rate and tax code for its issue date, after
-- the lines have taken their tax codes. Internal: issue_invoice calls it.
create or replace function ${fn("issue_invoice_tax")}(invoice uuid, on_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv ${inv.table("invoices")}%rowtype;
  v_result jsonb;
begin
  select * into v_inv from ${inv.table("invoices")} x where x.${i("id")} = issue_invoice_tax.invoice;
  if not found then
    return;
  end if;${resolve}
  select ${fn("tax_compute_lines")}(
    coalesce((select jsonb_agg(${line} order by x.${il("position")}) from ${inv.table("lines")} x
      where x.${il("parent")} = v_inv.${i("id")} and ${countedLine(inv, "lines", "x")}), '[]'::jsonb),
    issue_invoice_tax.on_date, ${parentOf("pricesIncludeTax", "false")}, 0,
    ${optIn("discountBps", "0")}, ${optIn("discountAmount", "0")})
  into v_result;
  delete from ${q.lines} x where x.${l("parent")} = v_inv.${i("id")};
  insert into ${q.lines} (${l("tenant")}, ${l("parent")}, ${l("taxRateBps")}, ${l("taxCode")}, ${l("taxCodeId")}, ${l("net")}, ${l("tax")}, ${l("gross")}, ${l("discount")}, ${l("customerVat")}, ${l("showTax")})
  select v_inv.${i("tenant")}, v_inv.${i("id")}, g."rateBps", g.code, g."taxCodeId", g.net, g.tax, g.gross, g.discount, ${vat}, g."showTax"
  from jsonb_to_recordset(v_result -> 'groups') g("rateBps" integer, code text, "taxCodeId" uuid, net bigint, tax bigint, gross bigint, discount bigint, "showTax" boolean);
end;
$$;
revoke execute on function ${fn("issue_invoice_tax")}(uuid, date) from public, anon, authenticated;`;
}
