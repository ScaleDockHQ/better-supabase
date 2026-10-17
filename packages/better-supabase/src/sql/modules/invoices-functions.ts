import type { ExtraColumn, ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { lineItemsSql } from "../line-items-sql.ts";
import { assignNumberSql } from "../numbering-sql.ts";
import { fail, userGrant, writeExtraColumns } from "../shared.ts";
import { subjectInTenant } from "../subject-check-sql.ts";
import { createdFromLink } from "./quotes-functions.ts";

export interface InvoiceNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly company: string;
  readonly contact: string;
  readonly prefix: string;
  readonly creditPrefix: string;
  /** Days from issue to due date by default. */
  readonly termsDays: number;
  readonly service: string;
  /** `options.extraColumns`, which `create_invoice` writes by name. */
  readonly extras: readonly ExtraColumn[];
}

export function invoiceFunctions(ctx: ModuleContext, n: InvoiceNames): string {
  const { fn, t, c } = n;
  const i = (column: string): string => c("invoices", column);
  const l = (column: string): string => c("lines", column);
  const p = (column: string): string => c("payments", column);
  const can = (alias: string, permission: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${i("tenant")}`, permission)})`;
  const balance = (alias: string): string =>
    `(${alias}.${i("total")} - ${alias}.${i("creditedTotal")} - ${alias}.${i("paidTotal")})`;
  const row = (alias: string): string =>
    `to_jsonb(${alias}) || jsonb_build_object(
      'balance', ${balance(alias)}::text,
      'overdue', ${alias}.${i("status")} in ('issued', 'partially_paid') and ${alias}.${i("dueOn")} < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il.${l("description")}, 'quantity', il.${l("quantity")}, 'unitAmount', il.${l("unitAmount")}::text, 'discountBps', il.${l("discountBps")}, 'taxRateBps', il.${l("taxRateBps")}, 'taxCode', il.${l("taxCode")}) order by il.${l("position")}) from ${t("lines")} il where il.${l("parent")} = ${alias}.${i("id")}), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip.${p("id")}, 'amount', ip.${p("amount")}::text, 'paidAt', ip.${p("paidAt")}, 'method', ip.${p("method")}, 'reference', ip.${p("reference")}) order by ip.${p("paidAt")}) from ${t("payments")} ip where ip.${p("invoice")} = ${alias}.${i("id")}), '[]'::jsonb))`;
  const record = (
    type: string,
    alias: string,
    extra = "",
    audit = false,
  ): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${alias}.${i("tenant")}, 'invoiceId', ${alias}.${i("id")}, 'subjectType', 'invoice', 'subjectId', ${alias}.${i("id")}::text, 'identifier', ${alias}.${i("identifier")}${extra})`,
      subject: `'invoices/' || ${alias}.${i("id")}::text`,
      tenant: `${alias}.${i("tenant")}::text`,
      audit: audit
        ? {
            category: "billing",
            targetType: "invoice",
            recordId: `${alias}.${i("id")}::text`,
            targetLabel: `${alias}.${i("identifier")}`,
            summary: sqlString(type.replace("invoice.", "invoice ")),
          }
        : false,
    });
  const checkParty = (
    kind: "COMPANY" | "CONTACT",
    type: string,
    id: string,
    tenant: string,
  ): string => `
  if ${id} is not null and not ${subjectInTenant(ctx, type, id, tenant)} then
    ${fail(`INVOICE_${kind}_FORBIDDEN`, `the ${kind.toLowerCase()} is unknown or not readable in this organization`, "42501")}
  end if;`;
  const settle = (alias: string): string => `
  update ${t("invoices")} x set
    ${i("paidTotal")} = coalesce((select sum(y.${p("amount")}) from ${t("payments")} y where y.${p("invoice")} = x.${i("id")}), 0),
    ${i("updatedAt")} = now()
  where x.${i("id")} = ${alias}.${i("id")}
  returning * into ${alias};
  update ${t("invoices")} x set
    ${i("status")} = case
      when ${balance("x")} <= 0 then 'paid'
      when x.${i("paidTotal")} > 0 or x.${i("creditedTotal")} > 0 then 'partially_paid'
      else 'issued' end,
    ${i("paidAt")} = case when ${balance("x")} <= 0 then coalesce(x.${i("paidAt")}, now()) end
  where x.${i("id")} = ${alias}.${i("id")} and x.${i("status")} in ('issued', 'partially_paid', 'paid')
  returning * into ${alias};`;
  const quotes = ctx.installed("quotes") ? ctx.of("quotes") : undefined;
  const fromQuote =
    quotes === undefined
      ? ""
      : (() => {
          const q = (column: string): string => quotes.col("quotes", column);
          const ql = (column: string): string => quotes.col("lines", column);
          return `
-- An invoice from an accepted quote. With deposit_bps (2000 for 20%) it is
-- a deposit invoice for that share of the quote; without, the full invoice,
-- which subtracts the deposits already issued and is made once per quote.
create or replace function ${fn("invoice_from_quote")}(quote uuid, deposit_bps integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote ${quotes.table("quotes")};
  v_row ${t("invoices")};
  v_lines jsonb;
begin
  select * into v_quote from ${quotes.table("quotes")} x where x.${q("id")} = invoice_from_quote.quote;
  if v_quote.${q("id")} is null or not (${n.service} or ${ctx.scope.can(`v_quote.${q("tenant")}`, n.write)}) then
    ${fail("INVOICE_ORIGIN_NOT_FOUND", "no such quote you can invoice", "P0002")}
  end if;
  if v_quote.${q("status")} <> 'accepted' then
    ${fail("INVOICE_QUOTE_NOT_ACCEPTED", "only an accepted quote is invoiced", "55000")}
  end if;
  if invoice_from_quote.deposit_bps is not null and (invoice_from_quote.deposit_bps <= 0 or invoice_from_quote.deposit_bps >= 10000) then
    ${fail("INVOICE_DEPOSIT_INVALID", "a deposit is between 0 and 100 percent", "22023")}
  end if;
  if invoice_from_quote.deposit_bps is null then
    select * into v_row from ${t("invoices")} x
    where x.${i("originType")} = 'quote' and x.${i("originId")} = v_quote.${q("id")}::text
      and x.${i("depositBps")} is null and x.${i("status")} <> 'void' and x.${i("kind")} = 'invoice'
    limit 1;
    if v_row.${i("id")} is not null then
      return ${row("v_row")};
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('description', x.${ql("description")}, 'quantity', x.${ql("quantity")}, 'unitAmount', x.${ql("unitAmount")}::text,
        'discountBps', x.${ql("discountBps")}, 'taxRateBps', x.${ql("taxRateBps")}, 'taxCode', x.${ql("taxCode")},
        'product', case when x.${ql("productType")} is null then null else jsonb_build_object('type', x.${ql("productType")}, 'id', x.${ql("productId")}) end
      ) order by x.${ql("position")}), '[]'::jsonb) into v_lines
    from ${quotes.table("lines")} x where x.${ql("parent")} = v_quote.${q("id")};
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', 'Deposit ' || d.${i("identifier")}, 'quantity', 1, 'unitAmount', (-d.${i("subtotal")})::text,
        'taxRateBps', case when d.${i("subtotal")} = 0 then 0 else round(d.${i("taxTotal")} * 10000.0 / d.${i("subtotal")})::integer end)), '[]'::jsonb)
      into v_lines
    from ${t("invoices")} d
    where d.${i("originType")} = 'quote' and d.${i("originId")} = v_quote.${q("id")}::text and d.${i("depositBps")} is not null and d.${i("status")} not in ('draft', 'void');
  else
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit ' || (invoice_from_quote.deposit_bps / 100.0)::text || '% of ' || v_quote.${q("identifier")},
      'quantity', 1,
      'unitAmount', round(v_quote.${q("subtotal")} * invoice_from_quote.deposit_bps / 10000.0)::bigint::text,
      'taxRateBps', case when v_quote.${q("subtotal")} = 0 then 0 else round(v_quote.${q("taxTotal")} * 10000.0 / v_quote.${q("subtotal")})::integer end));
  end if;
  v_row := null;
  return ${fn("create_invoice")}(v_quote.${q("tenant")}, jsonb_build_object(
    'title', v_quote.${q("title")}, 'currency', v_quote.${q("currency")}, 'depositBps', invoice_from_quote.deposit_bps,
    'company', case when v_quote.${q("companyId")} is null then null else jsonb_build_object('type', v_quote.${q("companyType")}, 'id', v_quote.${q("companyId")}) end,
    'contact', case when v_quote.${q("contactId")} is null then null else jsonb_build_object('type', v_quote.${q("contactType")}, 'id', v_quote.${q("contactId")}) end,
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote.${q("id")}::text)), v_lines);
end;
$$;
${userGrant(`${fn("invoice_from_quote")}(uuid, integer)`)}
`;
        })();
  const kindTable = (kind: string): string =>
    `(select * from ${t("invoices")} k where k.${i("kind")} = ${kind})`;
  return `
-- Creates a draft invoice. attrs: title (required), currency, company and
-- contact ({ type, id }), termsDays, note, origin ({ type, id }) and the
-- extra columns by name.
create or replace function ${fn("create_invoice")}(tenant ${ctx.idType}, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_company_type text := coalesce(create_invoice.attrs -> 'company' ->> 'type', ${sqlString(n.company)});
  v_company_id text := create_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_invoice.attrs -> 'contact' ->> 'type', ${sqlString(n.contact)});
  v_contact_id text := create_invoice.attrs -> 'contact' ->> 'id';
begin
  if not (${n.service} or ${ctx.scope.can("create_invoice.tenant", n.write)}) then
    ${fail("INVOICE_FORBIDDEN", "not allowed to change invoices")}
  end if;
  if nullif(trim(create_invoice.attrs ->> 'title'), '') is null then
    ${fail("INVOICE_ATTRS_INVALID", "an invoice needs a title", "23502")}
  end if;${checkParty("COMPANY", "v_company_type", "v_company_id", "create_invoice.tenant")}${checkParty("CONTACT", "v_contact_type", "v_contact_id", "create_invoice.tenant")}
  begin
    insert into ${t("invoices")} (${i("tenant")}, ${i("title")}, ${i("companyType")}, ${i("companyId")}, ${i("contactType")}, ${i("contactId")}, ${i("currency")},
      ${i("termsDays")}, ${i("note")}, ${i("originType")}, ${i("originId")}, ${i("depositBps")}, ${i("createdBy")})
    values (create_invoice.tenant, trim(create_invoice.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR')), coalesce((create_invoice.attrs ->> 'termsDays')::integer, ${String(n.termsDays)}),
      create_invoice.attrs ->> 'note', create_invoice.attrs -> 'origin' ->> 'type', create_invoice.attrs -> 'origin' ->> 'id',
      (create_invoice.attrs ->> 'depositBps')::integer, auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation then
    ${fail("INVOICE_ATTRS_INVALID", "an invoice field has an invalid value", "22023")}
  end;${writeExtraColumns(t("invoices"), n.extras, "create_invoice.attrs", `x.${i("id")} = v_row.${i("id")}`)}
  if create_invoice.lines is not null then
    perform ${fn("set_invoice_lines")}(v_row.${i("id")}, create_invoice.lines);
  end if;
  if v_row.${i("originId")} is not null then
    ${createdFromLink(ctx, { tenant: `v_row.${i("tenant")}`, sourceType: "'invoice'", sourceId: `v_row.${i("id")}::text`, originType: `v_row.${i("originType")}`, originId: `v_row.${i("originId")}` })}
  end if;
  ${record("invoice.created", "v_row")}
  return (select ${row("x")} from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")});
end;
$$;
${userGrant(`${fn("create_invoice")}(${ctx.idType}, jsonb, jsonb)`)}
${lineItemsSql(
  ctx,
  { lines: "lines", parent: "invoices", frozen: `p.${i("status")} <> 'draft'` },
  {
    setter: "set_invoice_lines",
    guard: `if not exists (select 1 from ${t("invoices")} x where x.${i("id")} = v_parent and ${can("x", n.write)}) then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;`,
  },
)}
-- Issues a draft: it gets the next number of its kind (gapless, so a
-- number is only taken when the invoice is final), its issue and due date,
-- and its lines freeze. A credit note reduces the balance of its original.
create or replace function ${fn("issue_invoice")}(invoice uuid, issued_on date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_original ${t("invoices")};
  v_seq bigint;
  v_identifier text;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = issue_invoice.invoice and ${can("x", n.write)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if v_row.${i("status")} <> 'draft' then
    ${fail("INVOICE_NOT_DRAFT", "the invoice was already issued", "55000")}
  end if;
  if not exists (select 1 from ${t("lines")} x where x.${l("parent")} = v_row.${i("id")}) then
    ${fail("INVOICE_EMPTY", "an invoice needs a line before it is issued", "23514")}
  end if;
  ${ctx.hook("before_invoice_issue", [["uuid", `v_row.${i("id")}`]])}
  if v_row.${i("kind")} = 'credit_note' then
    select * into v_original from ${t("invoices")} x where x.${i("id")} = v_row.${i("original")} for update;
    if v_row.${i("total")} > ${balance("v_original")} then
      ${fail("INVOICE_CREDIT_TOO_LARGE", "a credit note can't exceed what is still owed", "23514")}
    end if;
    ${assignNumberSql(ctx, "credit_note", `v_row.${i("tenant")}`, { seq: "v_seq", identifier: "v_identifier" }, { table: kindTable("'credit_note'"), seq: i("number"), tenant: i("tenant"), prefix: n.creditPrefix })}
  else
    ${assignNumberSql(ctx, "invoice", `v_row.${i("tenant")}`, { seq: "v_seq", identifier: "v_identifier" }, { table: kindTable("'invoice'"), seq: i("number"), tenant: i("tenant"), prefix: n.prefix })}
  end if;
  update ${t("invoices")} x set ${i("status")} = 'issued', ${i("number")} = v_seq, ${i("identifier")} = v_identifier,
    ${i("issuedOn")} = coalesce(issue_invoice.issued_on, current_date),
    ${i("dueOn")} = coalesce(issue_invoice.issued_on, current_date) + x.${i("termsDays")},
    ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")}
  returning * into v_row;
  ${record("invoice.issued", "v_row", `, 'total', v_row.${i("total")}::text, 'currency', v_row.${i("currency")}, 'dueOn', v_row.${i("dueOn")}`)}
  if v_row.${i("kind")} = 'credit_note' then
    update ${t("invoices")} x set ${i("creditedTotal")} = x.${i("creditedTotal")} + v_row.${i("total")}, ${i("updatedAt")} = now()
    where x.${i("id")} = v_original.${i("id")}
    returning * into v_original;${settle("v_original")}
    ${record("invoice.credited", "v_original", `, 'creditNoteId', v_row.${i("id")}, 'amount', v_row.${i("total")}::text`)}
    if v_original.${i("status")} = 'paid' then
      ${record("invoice.paid", "v_original", `, 'total', v_original.${i("total")}::text`)}
    end if;
  end if;
  ${ctx.hook("after_invoice_issue", [["uuid", `v_row.${i("id")}`]])}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("issue_invoice")}(uuid, date)`)}

-- Records a payment (a negative amount is a refund). A reference, such as
-- a bank or payment provider id, is unique per organization, so recording
-- the same payment twice adds it once.
create or replace function ${fn("record_invoice_payment")}(invoice uuid, amount bigint, paid_at timestamptz, method text, reference text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_payment uuid;
  v_was text;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = record_invoice_payment.invoice and ${can("x", n.write)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if v_row.${i("kind")} <> 'invoice' or v_row.${i("status")} not in ('issued', 'partially_paid', 'paid') then
    ${fail("INVOICE_NOT_PAYABLE", "only an issued invoice takes payments", "55000")}
  end if;
  if coalesce(record_invoice_payment.amount, 0) = 0 then
    ${fail("INVOICE_PAYMENT_INVALID", "a payment has an amount", "22023")}
  end if;
  ${ctx.hook("before_invoice_payment", [
    ["uuid", `v_row.${i("id")}`],
    ["bigint", "record_invoice_payment.amount"],
  ])}
  v_was := v_row.${i("status")};
  insert into ${t("payments")} (${p("tenant")}, ${p("invoice")}, ${p("amount")}, ${p("paidAt")}, ${p("method")}, ${p("reference")}, ${p("recordedBy")})
  values (v_row.${i("tenant")}, v_row.${i("id")}, record_invoice_payment.amount, coalesce(record_invoice_payment.paid_at, now()),
    record_invoice_payment.method, nullif(trim(record_invoice_payment.reference), ''), auth.uid())
  on conflict do nothing
  returning ${p("id")} into v_payment;
  if v_payment is null then
    return ${row("v_row")};
  end if;${settle("v_row")}
  ${record("invoice.payment_recorded", "v_row", `, 'paymentId', v_payment, 'amount', record_invoice_payment.amount::text, 'balance', ${balance("v_row")}::text`)}
  if v_row.${i("status")} = 'paid' and v_was <> 'paid' then
    ${record("invoice.paid", "v_row", `, 'total', v_row.${i("total")}::text`)}
  end if;
  ${ctx.hook("after_invoice_payment", [
    ["uuid", `v_row.${i("id")}`],
    ["uuid", "v_payment"],
  ])}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("record_invoice_payment")}(uuid, bigint, timestamptz, text, text)`)}

-- A draft credit note against an issued invoice: its lines, or the given
-- lines for a partial credit. Issue it to apply it.
create or replace function ${fn("credit_invoice")}(invoice uuid, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_original ${t("invoices")};
  v_row ${t("invoices")};
begin
  select * into v_original from ${t("invoices")} x where x.${i("id")} = credit_invoice.invoice and ${can("x", n.write)};
  if v_original.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can edit", "P0002")}
  end if;
  if v_original.${i("kind")} <> 'invoice' or v_original.${i("status")} not in ('issued', 'partially_paid', 'paid') then
    ${fail("INVOICE_NOT_CREDITABLE", "only an issued invoice is credited", "55000")}
  end if;
  insert into ${t("invoices")} (${i("tenant")}, ${i("kind")}, ${i("original")}, ${i("title")}, ${i("companyType")}, ${i("companyId")}, ${i("contactType")}, ${i("contactId")},
    ${i("currency")}, ${i("termsDays")}, ${i("note")}, ${i("createdBy")})
  values (v_original.${i("tenant")}, 'credit_note', v_original.${i("id")}, 'Credit for ' || coalesce(v_original.${i("identifier")}, v_original.${i("title")}),
    v_original.${i("companyType")}, v_original.${i("companyId")}, v_original.${i("contactType")}, v_original.${i("contactId")},
    v_original.${i("currency")}, 0, nullif(trim(credit_invoice.note), ''), auth.uid())
  returning * into v_row;
  if credit_invoice.lines is null then
    insert into ${t("lines")} (${l("tenant")}, ${l("parent")}, ${l("productType")}, ${l("productId")}, ${l("description")}, ${l("quantity")}, ${l("unitAmount")}, ${l("discountBps")}, ${l("taxRateBps")}, ${l("taxCode")}, ${l("position")})
    select x.${l("tenant")}, v_row.${i("id")}, x.${l("productType")}, x.${l("productId")}, x.${l("description")}, x.${l("quantity")}, x.${l("unitAmount")}, x.${l("discountBps")}, x.${l("taxRateBps")}, x.${l("taxCode")}, x.${l("position")}
    from ${t("lines")} x where x.${l("parent")} = v_original.${i("id")};
  else
    perform ${fn("set_invoice_lines")}(v_row.${i("id")}, credit_invoice.lines);
  end if;
  ${record("invoice.created", "v_row")}
  return (select ${row("x")} from ${t("invoices")} x where x.${i("id")} = v_row.${i("id")});
end;
$$;
${userGrant(`${fn("credit_invoice")}(uuid, jsonb, text)`)}

-- Voids an invoice without payments: a draft, or an issued one sent in
-- error. Its number stays taken. Needs invoices.manage.
create or replace function ${fn("void_invoice")}(invoice uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = void_invoice.invoice and ${can("x", n.manage)} for update;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can manage", "P0002")}
  end if;
  if v_row.${i("status")} not in ('draft', 'issued') or v_row.${i("paidTotal")} <> 0 or v_row.${i("creditedTotal")} <> 0 then
    ${fail("INVOICE_NOT_VOIDABLE", "an invoice with payments or credits is credited, not voided", "55000")}
  end if;
  update ${t("invoices")} x set ${i("status")} = 'void', ${i("voidedAt")} = now(),
    ${i("voidReason")} = nullif(trim(void_invoice.reason), ''), ${i("updatedAt")} = now()
  where x.${i("id")} = v_row.${i("id")} returning * into v_row;
  ${record("invoice.voided", "v_row", `, 'reason', v_row.${i("voidReason")}`, true)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("void_invoice")}(uuid, text)`)}

-- Writes an open invoice off as uncollectible. Needs invoices.manage.
create or replace function ${fn("write_off_invoice")}(invoice uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
begin
  update ${t("invoices")} x set ${i("status")} = 'uncollectible', ${i("updatedAt")} = now()
  where x.${i("id")} = write_off_invoice.invoice and ${can("x", n.manage)} and x.${i("status")} in ('issued', 'partially_paid')
  returning * into v_row;
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_OPEN", "only an open invoice you can manage is written off", "55000")}
  end if;
  ${record("invoice.uncollected", "v_row", `, 'balance', ${balance("v_row")}::text`, true)}
  return ${row("v_row")};
end;
$$;
${userGrant(`${fn("write_off_invoice")}(uuid)`)}

-- What a tenant is owed in one currency on as_of, by days past due:
-- not yet due, 1 to 30, 31 to 60, 61 to 90 and over 90. Amounts are text.
create or replace function ${fn("invoice_aging")}(tenant ${ctx.idType}, currency text, as_of date)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with open as (
    select ${balance("x")} as balance, coalesce(invoice_aging.as_of, current_date) - x.${i("dueOn")} as late
    from ${t("invoices")} x
    where x.${i("tenant")} = invoice_aging.tenant and x.${i("currency")} = upper(invoice_aging.currency)
      and x.${i("kind")} = 'invoice' and x.${i("status")} in ('issued', 'partially_paid')
  )
  select jsonb_build_object(
    'currency', upper(invoice_aging.currency),
    'current', coalesce(sum(balance) filter (where late <= 0), 0)::text,
    'days1To30', coalesce(sum(balance) filter (where late between 1 and 30), 0)::text,
    'days31To60', coalesce(sum(balance) filter (where late between 31 and 60), 0)::text,
    'days61To90', coalesce(sum(balance) filter (where late between 61 and 90), 0)::text,
    'over90', coalesce(sum(balance) filter (where late > 90), 0)::text,
    'outstanding', coalesce(sum(balance), 0)::text,
    'overdueCount', count(*) filter (where late > 0)
  )
  from open
$$;
${userGrant(`${fn("invoice_aging")}(${ctx.idType}, text, date)`)}
${fromQuote}`;
}
