import type { BlockSqlContext } from "../context.ts";
import type { Parts } from "./document-templates-parts.ts";

import {
  countedLine,
  declared,
  lineAmount,
  lineColumn,
  lineDiscount,
} from "../line-items-sql.ts";
import { fail, userGrant } from "../shared.ts";
import {
  EMPTY_ADDRESS,
  column,
  hasEntityColumn,
  header,
  isoDate,
  isoInstant,
  money,
  notFound,
  payload,
  qualified,
  quantity,
  source,
  terms,
  totals,
} from "./document-templates-parts.ts";
import { DOCUMENT_TYPES } from "./document-templates-values.ts";

/** The module a document type reads, for the error that names it. */
const SOURCE: Readonly<Record<string, string>> = {
  invoice: "invoices",
  credit_note: "invoices",
  quote: "quotes",
  order: "orders",
  delivery_note: "shipments",
  dunning_letter: "invoices",
  statement: "invoices",
};

/**
 * Whether the caller can read the row a document is made from, as the caller:
 * the policy of a snapshot uses it, so a snapshot shows only to someone who
 * could read the document itself. A statement has no row of its own and shows
 * to the organization's template managers only (the policy adds that).
 */
function visibleFunction(parts: Parts): string {
  const { ctx, fn, idType } = parts;

  const branches: string[] = [];

  const add = (
    types: readonly string[],
    module: string,
    table: string,
  ): void => {
    const own = source(ctx, module);

    if (own === undefined || !own.hasTable(table)) {
      return;
    }

    branches.push(`    when ${types.map((type) => `'${type}'`).join(", ")} then
      return exists (select 1 from ${own.table(table)} x where x.${own.col(table, "id")} = document_visible.document_id and x.${own.col(table, "tenant")} = document_visible.tenant);`);
  };

  add(["invoice", "credit_note"], "invoices", "invoices");
  add(["quote"], "quotes", "quotes");
  add(["order"], "orders", "orders");
  add(["delivery_note"], "shipments", "shipments");
  add(["dunning_letter"], "invoices", "dunningRunItems");

  return `
-- Whether the caller can read the source row of a document.
create or replace function ${fn("document_visible")}(tenant ${idType}, document_type text, document_id uuid)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
${
  branches.length === 0
    ? "  return false;"
    : `  case document_visible.document_type
${branches.join("\n")}
    else
      return false;
  end case;`
}
end;
$$;
${userGrant(`${fn("document_visible")}(${idType}, text, uuid)`)}
`;
}

/** Helpers every builder calls: address, entity, party and the tax summary. */
function helpers({ ctx, fn, idType }: Parts): string {
  const legal = ctx.of("legal-entities");
  const entities = legal.table("entities");
  const e = (logical: string): string => legal.col("entities", logical);
  const contacts = source(ctx, "contacts");

  const company = contacts?.hasTable("companies") ? contacts : undefined;
  const person = contacts?.hasTable("people") ? contacts : undefined;

  const companyBlock =
    company === undefined
      ? ""
      : `select * into v_company from ${company.table("companies")} x where x.${company.col("companies", "id")}::text = document_party.company_id and x.${company.col("companies", "tenant")} = document_party.tenant;`;

  const personBlock =
    person === undefined
      ? ""
      : `select * into v_person from ${person.table("people")} x where x.${person.col("people", "id")}::text = coalesce(document_party.contact_id, document_party.company_id) and x.${person.col("people", "tenant")} = document_party.tenant;`;

  const field = (
    ctxOf: BlockSqlContext | undefined,
    table: string,
    row: string,
    logical: string,
  ): string =>
    ctxOf !== undefined && declared(ctxOf, table, logical)
      ? `${row}.${ctxOf.col(table, logical)}::text`
      : "null::text";

  return `
-- One address in the contract's six keys, from the key names addresses use.
create or replace function ${fn("document_address")}(address jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'line1', nullif(btrim(coalesce(a.j ->> 'line1', a.j ->> 'street', a.j ->> 'address1')), ''),
    'line2', nullif(btrim(coalesce(a.j ->> 'line2', a.j ->> 'address2')), ''),
    'postalCode', nullif(btrim(coalesce(a.j ->> 'postalCode', a.j ->> 'postal_code', a.j ->> 'zip')), ''),
    'city', nullif(btrim(a.j ->> 'city'), ''),
    'region', nullif(btrim(coalesce(a.j ->> 'region', a.j ->> 'state')), ''),
    'country', nullif(btrim(a.j ->> 'country'), '')
  )
  from (select case when jsonb_typeof(document_address.address) = 'object' then document_address.address else '{}'::jsonb end as j) a
$$;
${userGrant(`${fn("document_address")}(jsonb)`)}

-- The legal entity that issues a document: the given one, else the
-- organization's default. All null when the organization has none.
create or replace function ${fn("document_entity")}(tenant ${idType}, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_row ${entities}%rowtype;
begin
  v_id := ${legal.fn("legal_entity_of")}(document_entity.tenant, document_entity.legal_entity);
  if v_id is not null then
    select * into v_row from ${entities} x where x.${e("id")} = v_id;
  end if;
  if v_row.${e("id")} is null then
    return jsonb_build_object('id', null::text, 'code', null::text, 'name', null::text, 'address', ${EMPTY_ADDRESS}, 'vatNumber', null::text, 'cocNumber', null::text, 'iban', null::text, 'bic', null::text, 'logoAttachmentId', null::text, 'defaultCurrency', null::text);
  end if;
  return jsonb_build_object('id', v_row.${e("id")}, 'code', v_row.${e("code")}, 'name', v_row.${e("name")}, 'address', ${fn("document_address")}(v_row.${e("address")}), 'vatNumber', v_row.${e("vatNumber")}, 'cocNumber', v_row.${e("cocNumber")}, 'iban', v_row.${e("iban")}, 'bic', v_row.${e("bic")}, 'logoAttachmentId', v_row.${e("logoAttachment")}, 'defaultCurrency', v_row.${e("defaultCurrency")});
end;
$$;
${userGrant(`${fn("document_entity")}(${idType}, uuid)`)}

-- The customer of a document. The buyer the document stored comes first, then
-- the company, then the person; address is the fallback address.
create or replace function ${fn("document_party")}(tenant ${idType}, company_id text, contact_id text, buyer jsonb default null, email text default null, address jsonb default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_company ${company === undefined ? "record" : `${company.table("companies")}%rowtype`};
  v_person ${person === undefined ? "record" : `${person.table("people")}%rowtype`};
  v_buyer jsonb := case when jsonb_typeof(document_party.buyer) = 'object' then document_party.buyer else '{}'::jsonb end;
  v_company_found boolean := false;
  v_person_found boolean := false;
begin
  ${companyBlock === "" ? "" : `${companyBlock}\n  v_company_found := found;`}
  ${personBlock === "" ? "" : `${personBlock}\n  v_person_found := found;`}
  return jsonb_build_object(
    'id', case when v_company_found then document_party.company_id when v_person_found then coalesce(document_party.contact_id, document_party.company_id) else null end,
    'type', case when v_company_found then 'company' when v_person_found then 'person' else null end,
    'name', coalesce(nullif(v_buyer ->> 'name', ''), ${company === undefined ? "null::text" : `case when v_company_found then ${field(company, "companies", "v_company", "name")} end`}, ${person === undefined ? "null::text" : `case when v_person_found then ${field(person, "people", "v_person", "name")} end`}),
    'email', coalesce(nullif(v_buyer ->> 'email', ''), ${person === undefined ? "null::text" : `case when v_person_found then ${field(person, "people", "v_person", "email")} end`}, nullif(document_party.email, '')),
    'vatNumber', coalesce(nullif(coalesce(v_buyer ->> 'vatNumber', v_buyer ->> 'vat_number', v_buyer ->> 'vatId'), ''), ${company === undefined ? "null::text" : `case when v_company_found then ${field(company, "companies", "v_company", "vatId")} end`}),
    'language', coalesce(nullif(v_buyer ->> 'language', ''), ${company === undefined ? "null::text" : `case when v_company_found then ${field(company, "companies", "v_company", "language")} end`}, ${person === undefined ? "null::text" : `case when v_person_found then ${field(person, "people", "v_person", "language")} end`}),
    'address', ${fn("document_address")}(coalesce(case when jsonb_typeof(v_buyer -> 'address') = 'object' then v_buyer -> 'address' end, ${company !== undefined && declared(company, "companies", "address") ? `case when v_company_found then v_company.${company.col("companies", "address")} end, ` : ""}document_party.address))
  );
end;
$$;
${userGrant(`${fn("document_party")}(${idType}, text, text, jsonb, text, jsonb)`)}

-- The tax per rate and code of a lines array, counted from the line amounts.
create or replace function ${fn("document_tax_summary")}(lines jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'taxRateBps', g.rate,
    'taxCode', g.code,
    'net', g.net::text,
    'tax', round(g.net * g.rate / 10000.0)::bigint::text,
    'gross', (g.net + round(g.net * g.rate / 10000.0)::bigint)::text
  ) order by g.rate, g.code), '[]'::jsonb)
  from (
    select coalesce((l ->> 'taxRateBps')::integer, 0) as rate, l ->> 'taxCode' as code, sum((l ->> 'amount')::bigint) as net
    from jsonb_array_elements(document_tax_summary.lines) l
    group by 1, 2
  ) g
$$;
${userGrant(`${fn("document_tax_summary")}(jsonb)`)}
`;
}

/** The JSON of one line of a document with a line table (invoices, quotes). */
function salesLine(own: BlockSqlContext): string {
  const l = (logical: string): string => `l.${own.col("lines", logical)}`;
  const amount = lineAmount(own, "lines", "l");
  const percent = lineColumn(own, "lines", "l", "discountBps");
  const discount = lineDiscount(own, "lines", "l", amount, percent);

  return `jsonb_build_object(
      'position', l.n,
      'description', ${l("description")},
      'sku', null::text,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', ${quantity(l("quantity"))},
      'unitAmount', ${money(l("unitAmount"))},
      'discountBps', ${percent},
      'discountAmount', ${declared(own, "lines", "discountAmount") ? money(l("discountAmount")) : "null::text"},
      'taxRateBps', ${lineColumn(own, "lines", "l", "taxRateBps")},
      'taxCode', ${lineColumn(own, "lines", "l", "taxCode")},
      'amount', ${money(`${amount} - ${discount}`)}
    )`;
}

/** The select that numbers the lines of a parent row `v_row.id`. */
function salesLines(own: BlockSqlContext, parent: string): string {
  const lines = own.table("lines");
  const l = (logical: string): string => `x.${own.col("lines", logical)}`;

  return `(select coalesce(jsonb_agg(${salesLine(own)} order by l.n), '[]'::jsonb)
      from (
        select x.*, row_number() over (order by ${l("position")}, ${l("id")}) as n
        from ${lines} x
        where x.${own.col("lines", "parent")} = ${parent}
      ) l
      where ${countedLine(own, "lines", "l")})`;
}

/** `v_lines`'s tax summary: the tax block's rows when it has them, else counted. */
function taxLines(
  ctx: BlockSqlContext,
  fn: (name: string) => string,
  table: { readonly module: string; readonly table: string },
  parent: string,
): string {
  const own = source(ctx, table.module);
  const tax = own?.hasTable(table.table) ? own : undefined;

  if (tax === undefined) {
    return `${fn("document_tax_summary")}(v_lines)`;
  }

  const t = (logical: string): string => `x.${tax.col(table.table, logical)}`;

  return `(select case when count(*) = 0 then ${fn("document_tax_summary")}(v_lines) else jsonb_agg(jsonb_build_object(
      'taxRateBps', ${t("taxRateBps")},
      'taxCode', ${t("taxCode")},
      'net', ${money(t("net"))},
      'tax', ${money(t("tax"))},
      'gross', ${money(t("gross"))}
    ) order by ${t("taxRateBps")}, ${t("taxCode")}) end
    from ${tax.table(table.table)} x
    where ${t("parent")} = ${parent})`;
}

/**
 * The payment terms of a document that keeps terms: the terms row and what the
 * document stored.
 */
function invoiceTerms(
  inv: BlockSqlContext,
  contacts: BlockSqlContext | undefined,
): string {
  const row = (logical: string, type: string): string =>
    column(inv, "invoices", "v_row", logical, type);

  const paymentTerms =
    contacts?.hasTable("terms") === true &&
    declared(inv, "invoices", "paymentTermsId")
      ? contacts
      : undefined;

  const term = (logical: string): string =>
    paymentTerms === undefined
      ? "null::text"
      : `(select ${paymentTerms.col("terms", logical)}::text from ${paymentTerms.table("terms")} x where x.${paymentTerms.col("terms", "id")} = ${row("paymentTermsId", "uuid")})`;

  const discountBps = (): string =>
    paymentTerms === undefined
      ? "null::integer"
      : `(select ${paymentTerms.col("terms", "discountBps")} from ${paymentTerms.table("terms")} x where x.${paymentTerms.col("terms", "id")} = ${row("paymentTermsId", "uuid")})`;

  const discountDays = (): string =>
    paymentTerms === undefined
      ? "null::integer"
      : `(select ${paymentTerms.col("terms", "discountDays")} from ${paymentTerms.table("terms")} x where x.${paymentTerms.col("terms", "id")} = ${row("paymentTermsId", "uuid")})`;

  return terms({
    code: term("code"),
    name: term("name"),
    days: row("termsDays", "integer"),
    dueOn: isoDate(row("dueOn", "date")),
    discountBps: discountBps(),
    discountDays: discountDays(),
    discountDueOn: isoDate(row("discountDueOn", "date")),
    discountAmount: money(row("discountAmountEarly", "bigint")),
  });
}

function invoiceFunction(parts: Parts, inv: BlockSqlContext): string {
  const { ctx, fn, idType } = parts;
  const t = inv.table("invoices");
  const i = (logical: string): string => inv.col("invoices", logical);

  const row = (logical: string, type: string): string =>
    column(inv, "invoices", "v_row", logical, type);

  const contacts = source(ctx, "contacts");

  const entity = hasEntityColumn(ctx, "invoices")
    ? "v_row.legal_entity_id"
    : "null::uuid";

  const credit = inv.is("invoices", "kind", `v_row.${i("kind")}`, [
    "credit_note",
  ]);

  const original = declared(inv, "invoices", "original")
    ? `(select coalesce(o.${i("identifier")}, o.${i("number")}::text) from ${t} o where o.${i("id")} = v_row.${i("original")})`
    : "null::text";

  return `
create or replace function ${fn("document_variables_invoice")}(tenant ${idType}, document_id uuid, credit_note boolean)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t}%rowtype;
  v_lines jsonb;
begin
  select * into v_row from ${t} x
    where x.${i("id")} = document_variables_invoice.document_id and x.${i("tenant")} = tenant;
  if not found or ${credit} is distinct from document_variables_invoice.credit_note then
    ${notFound}
  end if;
  v_lines := ${salesLines(inv, `v_row.${i("id")}`)};
  return ${payload({
    document: header({
      id: `v_row.${i("id")}::text`,
      type: "case when document_variables_invoice.credit_note then 'credit_note' else 'invoice' end",
      number: `coalesce(v_row.${i("identifier")}, v_row.${i("number")}::text)`,
      title: `v_row.${i("title")}`,
      status: `v_row.${i("status")}::text`,
      date: isoDate(row("issuedOn", "date")),
      currency: `trim(v_row.${i("currency")})`,
      note: row("note", "text"),
      dueOn: isoDate(row("dueOn", "date")),
      originalNumber: `case when document_variables_invoice.credit_note then ${original} end`,
    }),
    entity: `${fn("document_entity")}(tenant, ${entity})`,
    buyer: `${fn("document_party")}(tenant, ${row("companyId", "text")}::text, ${row("contactId", "text")}::text, ${row("buyer", "jsonb")})`,
    lines: "v_lines",
    taxLines: taxLines(
      ctx,
      fn,
      { module: "tax", table: "invoiceTaxLines" },
      `v_row.${i("id")}`,
    ),
    totals: totals({
      listTotal: money(row("listTotal", "bigint")),
      discountTotal: money(row("discountTotal", "bigint")),
      subtotal: money(row("subtotal", "bigint")),
      taxTotal: money(row("taxTotal", "bigint")),
      total: money(row("total", "bigint")),
      paidTotal: money(row("paidTotal", "bigint")),
      creditedTotal: money(row("creditedTotal", "bigint")),
      balance: `case when document_variables_invoice.credit_note then null else ${money(`${row("total", "bigint")} - ${row("paidTotal", "bigint")} - ${row("creditedTotal", "bigint")}`)} end`,
    }),
    paymentTerms: invoiceTerms(inv, contacts),
  })};
end;
$$;
${userGrant(`${fn("document_variables_invoice")}(${idType}, uuid, boolean)`)}
`;
}

function quoteFunction(parts: Parts, quotes: BlockSqlContext): string {
  const { ctx, fn, idType } = parts;
  const t = quotes.table("quotes");
  const q = (logical: string): string => quotes.col("quotes", logical);

  const row = (logical: string, type: string): string =>
    column(quotes, "quotes", "v_row", logical, type);

  const entity = hasEntityColumn(ctx, "quotes")
    ? "v_row.legal_entity_id"
    : "null::uuid";

  return `
create or replace function ${fn("document_variables_quote")}(tenant ${idType}, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t}%rowtype;
  v_lines jsonb;
begin
  select * into v_row from ${t} x
    where x.${q("id")} = document_variables_quote.document_id and x.${q("tenant")} = tenant;
  if not found then
    ${notFound}
  end if;
  v_lines := ${salesLines(quotes, `v_row.${q("id")}`)};
  return ${payload({
    document: header({
      id: `v_row.${q("id")}::text`,
      type: "'quote'",
      number: `coalesce(v_row.${q("identifier")}, v_row.${q("number")}::text)`,
      title: `v_row.${q("title")}`,
      status: `v_row.${q("status")}::text`,
      date: isoInstant(
        `coalesce(v_row.${q("sentAt")}, v_row.${q("createdAt")})`,
      ),
      currency: `trim(v_row.${q("currency")})`,
      note: row("note", "text"),
      validUntil: isoDate(row("validUntil", "date")),
      revision: `v_row.${q("revision")}`,
    }),
    entity: `${fn("document_entity")}(tenant, ${entity})`,
    buyer: `${fn("document_party")}(tenant, ${row("companyId", "text")}::text, ${row("contactId", "text")}::text, ${row("buyer", "jsonb")})`,
    lines: "v_lines",
    taxLines: taxLines(
      ctx,
      fn,
      { module: "quotes", table: "taxLines" },
      `v_row.${q("id")}`,
    ),
    totals: totals({
      listTotal: money(row("listTotal", "bigint")),
      discountTotal: money(row("discountTotal", "bigint")),
      subtotal: money(row("subtotal", "bigint")),
      taxTotal: money(row("taxTotal", "bigint")),
      total: money(row("total", "bigint")),
    }),
    paymentTerms: terms({ name: row("terms", "text") }),
  })};
end;
$$;
${userGrant(`${fn("document_variables_quote")}(${idType}, uuid)`)}
`;
}

/** The latest fulfillment's carrier and tracking number of order row `v_row`. */
function fulfillment(orders: BlockSqlContext, logical: string): string {
  if (!orders.hasTable("fulfillments")) {
    return "null::text";
  }

  const f = (name: string): string => orders.col("fulfillments", name);

  return `(select x.${f(logical)}::text from ${orders.table("fulfillments")} x where x.${f("order")} = v_row.${orders.col("orders", "id")} order by x.${f("createdAt")} desc limit 1)`;
}

function orderFunction(parts: Parts, orders: BlockSqlContext): string {
  const { ctx, fn, idType } = parts;
  const t = orders.table("orders");
  const o = (logical: string): string => orders.col("orders", logical);
  const ol = (logical: string): string => orders.col("orderLines", logical);

  const row = (logical: string, type: string): string =>
    column(orders, "orders", "v_row", logical, type);

  const entity = hasEntityColumn(ctx, "orders")
    ? "v_row.legal_entity_id"
    : "null::uuid";

  const billing = declared(orders, "orders", "billingAddress")
    ? `v_row.${o("billingAddress")}`
    : "null::jsonb";

  return `
create or replace function ${fn("document_variables_order")}(tenant ${idType}, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t}%rowtype;
  v_lines jsonb;
begin
  select * into v_row from ${t} x
    where x.${o("id")} = document_variables_order.document_id and x.${o("tenant")} = tenant;
  if not found then
    ${notFound}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', l.n,
      'description', l.${ol("title")},
      'sku', l.${ol("sku")},
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', l.${ol("quantity")}::text,
      'unitAmount', ${money(`l.${ol("unitAmount")}`)},
      'discountBps', null::integer,
      'discountAmount', ${money(`l.${ol("discount")}`)},
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', ${money(`l.${ol("subtotal")} - l.${ol("discount")}`)}
    ) order by l.n), '[]'::jsonb) into v_lines
  from (
    select x.*, row_number() over (order by x.${ol("position")}, x.${ol("id")}) as n
    from ${orders.table("orderLines")} x
    where x.${ol("order")} = v_row.${o("id")}
  ) l;
  return ${payload({
    document: header({
      id: `v_row.${o("id")}::text`,
      type: "'order'",
      number: `v_row.${o("number")}::text`,
      status: `v_row.${o("status")}::text`,
      date: isoInstant(`v_row.${o("placedAt")}`),
      currency: `trim(v_row.${o("currency")})`,
    }),
    entity: `${fn("document_entity")}(tenant, ${entity})`,
    buyer: `${fn("document_party")}(tenant, v_row.${o("customer")}::text, v_row.${o("customer")}::text, ${row("buyer", "jsonb")}, ${row("email", "text")}, ${billing})`,
    lines: "v_lines",
    taxLines: "'[]'::jsonb",
    totals: totals({
      discountTotal: money(`v_row.${o("discountTotal")}`),
      subtotal: money(`v_row.${o("subtotal")}`),
      taxTotal: money(`v_row.${o("taxTotal")}`),
      total: money(`v_row.${o("total")}`),
      paidTotal: money(`v_row.${o("paidTotal")}`),
      creditedTotal: money(`v_row.${o("refundedTotal")}`),
      shippingTotal: money(`v_row.${o("shippingTotal")}`),
      balance: money(
        `v_row.${o("total")} - v_row.${o("paidTotal")} + v_row.${o("refundedTotal")}`,
      ),
    }),
    paymentTerms: terms({}),
    shipping: `jsonb_build_object('address', ${fn("document_address")}(v_row.${o("shippingAddress")}), 'carrier', ${fulfillment(orders, "carrier")}, 'trackingNumber', ${fulfillment(orders, "trackingNumber")})`,
  })};
end;
$$;
${userGrant(`${fn("document_variables_order")}(${idType}, uuid)`)}
`;
}

function deliveryNoteFunction(
  parts: Parts,
  shipments: BlockSqlContext,
  orders: BlockSqlContext | undefined,
): string {
  const { fn, idType } = parts;
  const t = shipments.table("shipments");
  const h = (logical: string): string => shipments.col("shipments", logical);
  const sl = (logical: string): string => shipments.col("lines", logical);

  const subject =
    declared(shipments, "shipments", "subjectType") &&
    declared(shipments, "shipments", "subjectId");

  const ordersJoin =
    orders !== undefined && subject
      ? `left join ${orders.table("orderLines")} ol on v_row.${h("subjectType")} = 'order' and ol.${orders.col("orderLines", "order")}::text = v_row.${h("subjectId")} and ol.${orders.col("orderLines", "variant")} = x.${sl("variant")}`
      : "";

  const description =
    orders !== undefined && subject
      ? `coalesce(ol.${orders.col("orderLines", "title")}, x.${sl("variant")}::text)`
      : `x.${sl("variant")}::text`;

  const sku =
    orders !== undefined && subject
      ? `ol.${orders.col("orderLines", "sku")}`
      : "null::text";

  const buyer =
    orders !== undefined && subject
      ? `${fn("document_party")}(tenant, v_customer, v_customer, v_buyer, v_email, v_row.${h("toAddress")})`
      : `${fn("document_party")}(tenant, null, null, null, null, v_row.${h("toAddress")})`;

  const customer =
    orders !== undefined && subject
      ? `
  if v_row.${h("subjectType")} = 'order' then
    select o.${orders.col("orders", "customer")}::text, ${declared(orders, "orders", "buyer") ? `o.${orders.col("orders", "buyer")}` : "null::jsonb"}, ${declared(orders, "orders", "email") ? `o.${orders.col("orders", "email")}` : "null::text"}
      into v_customer, v_buyer, v_email
      from ${orders.table("orders")} o
      where o.${orders.col("orders", "id")}::text = v_row.${h("subjectId")} and o.${orders.col("orders", "tenant")} = tenant;
  end if;`
      : "";

  const entity =
    orders !== undefined && subject && hasEntityColumn(parts.ctx, "orders")
      ? `(select o.legal_entity_id from ${orders.table("orders")} o where v_row.${h("subjectType")} = 'order' and o.${orders.col("orders", "id")}::text = v_row.${h("subjectId")})`
      : "null::uuid";

  return `
create or replace function ${fn("document_variables_delivery_note")}(tenant ${idType}, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${t}%rowtype;
  v_lines jsonb;
  v_customer text;
  v_buyer jsonb;
  v_email text;
begin
  select * into v_row from ${t} x
    where x.${h("id")} = document_variables_delivery_note.document_id and x.${h("tenant")} = tenant;
  if not found then
    ${notFound}
  end if;${customer}
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', n.sku,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', n.quantity,
      'unitAmount', null::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', null::text
    ) order by n.n), '[]'::jsonb) into v_lines
  from (
    select row_number() over (order by x.${sl("position")}, x.${sl("id")}) as n,
      ${description} as description,
      ${sku} as sku,
      ${quantity(`x.${sl("quantity")}`)} as quantity
    from ${shipments.table("lines")} x
    ${ordersJoin}
    where x.${sl("shipment")} = v_row.${h("id")} and x.${sl("direction")} = 'outbound'
  ) n;
  return ${payload({
    document: header({
      id: `v_row.${h("id")}::text`,
      type: "'delivery_note'",
      number: `v_row.${h("reference")}`,
      status: `v_row.${h("status")}::text`,
      date: isoInstant(
        `coalesce(v_row.${h("labeledAt")}, v_row.${h("createdAt")})`,
      ),
      currency: "null::text",
      reference: `v_row.${h("trackingNumber")}`,
    }),
    entity: `${fn("document_entity")}(tenant, ${entity})`,
    buyer,
    lines: "v_lines",
    taxLines: "'[]'::jsonb",
    totals: totals({}),
    paymentTerms: terms({}),
    shipping: `jsonb_build_object('address', ${fn("document_address")}(v_row.${h("toAddress")}), 'carrier', v_row.${h("carrier")}, 'trackingNumber', v_row.${h("trackingNumber")})`,
  })};
end;
$$;
${userGrant(`${fn("document_variables_delivery_note")}(${idType}, uuid)`)}
`;
}

function dunningFunction(parts: Parts, inv: BlockSqlContext): string {
  const { ctx, fn, idType } = parts;
  const t = inv.table("invoices");
  const i = (logical: string): string => inv.col("invoices", logical);
  const it = (logical: string): string => inv.col("dunningRunItems", logical);
  const r = (logical: string): string => inv.col("dunningRuns", logical);

  const entity = hasEntityColumn(ctx, "invoices")
    ? `(select x.legal_entity_id from ${t} x where x.${i("id")} = v_item.${it("invoice")})`
    : "null::uuid";

  return `
create or replace function ${fn("document_variables_dunning_letter")}(tenant ${idType}, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item ${inv.table("dunningRunItems")}%rowtype;
  v_as_of date;
  v_lines jsonb;
  v_fee bigint;
  v_balance bigint;
  v_level integer;
  v_due date;
  v_currency text;
begin
  select * into v_item from ${inv.table("dunningRunItems")} x
    where x.${it("id")} = document_variables_dunning_letter.document_id and x.${it("tenant")} = tenant;
  if not found then
    ${notFound}
  end if;
  select x.${r("asOf")} into v_as_of from ${inv.table("dunningRuns")} x where x.${r("id")} = v_item.${it("run")};
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', null::text,
      'reference', n.number,
      'date', n.issued_on,
      'dueOn', n.due_on,
      'quantity', '1',
      'unitAmount', n.balance::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', n.balance::text
    ) order by n.n), '[]'::jsonb),
    coalesce(sum(n.fee), 0), coalesce(sum(n.balance), 0), max(n.level), min(n.due), max(n.currency)
  into v_lines, v_fee, v_balance, v_level, v_due, v_currency
  from (
    select row_number() over (order by x.${it("dueOn")}, x.${it("id")}) as n,
      coalesce(i.${i("title")}, i.${i("identifier")}) as description,
      coalesce(i.${i("identifier")}, i.${i("number")}::text) as number,
      ${isoDate(`i.${i("issuedOn")}`)} as issued_on,
      ${isoDate(`x.${it("dueOn")}`)} as due_on,
      x.${it("dueOn")} as due,
      x.${it("balance")} as balance,
      x.${it("fee")} as fee,
      x.${it("level")} as level,
      trim(i.${i("currency")}) as currency
    from ${inv.table("dunningRunItems")} x
    join ${t} i on i.${i("id")} = x.${it("invoice")}
    where x.${it("run")} = v_item.${it("run")}
      and ${declared(inv, "dunningRunItems", "party") ? `x.${it("party")} is not distinct from v_item.${it("party")}` : "true"}
  ) n;
  return ${payload({
    document: header({
      id: `v_item.${it("id")}::text`,
      type: "'dunning_letter'",
      date: isoDate("v_as_of"),
      currency: "v_currency",
      dueOn: isoDate("v_due"),
      level: "v_level",
      asOf: isoDate("v_as_of"),
      textKey: column(inv, "dunningRunItems", "v_item", "textKey", "text"),
    }),
    entity: `${fn("document_entity")}(tenant, ${entity})`,
    buyer: declared(inv, "dunningRunItems", "party")
      ? `${fn("document_party")}(tenant, v_item.${it("party")}::text, null)`
      : `${fn("document_party")}(tenant, null, null)`,
    lines: "v_lines",
    taxLines: "'[]'::jsonb",
    totals: totals({
      total: money("v_balance + v_fee"),
      fee: money("v_fee"),
      balance: money("v_balance + v_fee"),
    }),
    paymentTerms: terms({}),
  })};
end;
$$;
${userGrant(`${fn("document_variables_dunning_letter")}(${idType}, uuid)`)}
`;
}

function statementFunction(parts: Parts, inv: BlockSqlContext): string {
  const { ctx, fn, idType } = parts;
  const t = inv.table("invoices");
  const i = (logical: string): string => inv.col("invoices", logical);

  const open = inv.is("invoices", "status", `x.${i("status")}`, [
    "issued",
    "partially_paid",
  ]);

  const kind = inv.is("invoices", "kind", `x.${i("kind")}`, ["invoice"]);

  const direction = declared(inv, "invoices", "direction")
    ? ` and ${inv.is("invoices", "direction", `x.${i("direction")}`, ["sales"])}`
    : "";

  const owner = [
    declared(inv, "invoices", "companyId")
      ? `x.${i("companyId")}::text = document_variables_statement.document_id::text`
      : undefined,
    declared(inv, "invoices", "contactId")
      ? `x.${i("contactId")}::text = document_variables_statement.document_id::text`
      : undefined,
  ].filter((part): part is string => part !== undefined);

  const entity = hasEntityColumn(ctx, "invoices")
    ? `(select x.legal_entity_id from ${
        t
      } x where (${owner.join(" or ") || "false"}) order by x.${i("issuedOn")} desc limit 1)`
    : "null::uuid";

  const balance = `x.${i("total")} - x.${i("paidTotal")} - x.${i("creditedTotal")}`;

  return `
create or replace function ${fn("document_variables_statement")}(tenant ${idType}, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_lines jsonb;
  v_total bigint;
  v_paid bigint;
  v_credited bigint;
  v_balance bigint;
  v_currency text;
  v_party jsonb;
begin
  v_party := ${fn("document_party")}(tenant, document_variables_statement.document_id::text, document_variables_statement.document_id::text);
  if v_party ->> 'id' is null then
    ${notFound}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', null::text,
      'reference', n.number,
      'date', n.issued_on,
      'dueOn', n.due_on,
      'quantity', '1',
      'unitAmount', n.balance::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', n.balance::text
    ) order by n.n), '[]'::jsonb),
    coalesce(sum(n.total), 0), coalesce(sum(n.paid), 0), coalesce(sum(n.credited), 0), coalesce(sum(n.balance), 0), max(n.currency)
  into v_lines, v_total, v_paid, v_credited, v_balance, v_currency
  from (
    select row_number() over (order by x.${i("dueOn")}, x.${i("id")}) as n,
      coalesce(x.${i("title")}, x.${i("identifier")}) as description,
      coalesce(x.${i("identifier")}, x.${i("number")}::text) as number,
      ${isoDate(`x.${i("issuedOn")}`)} as issued_on,
      ${isoDate(`x.${i("dueOn")}`)} as due_on,
      x.${i("total")} as total,
      x.${i("paidTotal")} as paid,
      x.${i("creditedTotal")} as credited,
      ${balance} as balance,
      trim(x.${i("currency")}) as currency
    from ${t} x
    where x.${i("tenant")} = tenant and (${owner.join(" or ") || "false"})
      and ${open} and ${kind}${direction}
      and ${balance} > 0
  ) n;
  return ${payload({
    document: header({
      id: "document_variables_statement.document_id::text",
      type: "'statement'",
      date: isoDate("current_date"),
      currency: "v_currency",
      asOf: isoDate("current_date"),
    }),
    entity: `${fn("document_entity")}(tenant, ${entity})`,
    buyer: "v_party",
    lines: "v_lines",
    taxLines: "'[]'::jsonb",
    totals: totals({
      total: money("v_total"),
      paidTotal: money("v_paid"),
      creditedTotal: money("v_credited"),
      balance: money("v_balance"),
    }),
    paymentTerms: terms({}),
  })};
end;
$$;
${userGrant(`${fn("document_variables_statement")}(${idType}, uuid)`)}
`;
}

/** What each document type builds from, and the module it needs. */
function availableTypes(ctx: BlockSqlContext): readonly string[] {
  const inv = source(ctx, "invoices");
  const orders = source(ctx, "orders");

  return DOCUMENT_TYPES.filter((type) => {
    switch (type) {
      case "invoice":
      case "credit_note":
      case "statement": {
        return inv !== undefined;
      }

      case "quote": {
        return source(ctx, "quotes") !== undefined;
      }

      case "order": {
        return orders !== undefined;
      }

      case "delivery_note": {
        return source(ctx, "shipments") !== undefined;
      }

      case "dunning_letter": {
        return (
          inv !== undefined &&
          inv.hasTable("dunningRuns") &&
          inv.hasTable("dunningRunItems")
        );
      }

      default: {
        const never: never = type;

        return never;
      }
    }
  });
}

/**
 * The functions that build the variable payload of each document type the
 * installed blocks can read, and the `document_variables` dispatcher.
 */
export function documentVariableFunctions(ctx: BlockSqlContext): string {
  const parts: Parts = { ctx, fn: (name) => ctx.fn(name), idType: ctx.idType };
  const { fn } = parts;
  const available = new Set(availableTypes(ctx));
  const inv = source(ctx, "invoices");
  const quotes = source(ctx, "quotes");
  const orders = source(ctx, "orders");
  const shipments = source(ctx, "shipments");

  const builders = [
    helpers(parts),
    visibleFunction(parts),
    inv === undefined
      ? ""
      : qualified(invoiceFunction(parts, inv), "document_variables_invoice"),
    quotes === undefined
      ? ""
      : qualified(quoteFunction(parts, quotes), "document_variables_quote"),
    orders === undefined
      ? ""
      : qualified(orderFunction(parts, orders), "document_variables_order"),
    shipments === undefined
      ? ""
      : qualified(
          deliveryNoteFunction(parts, shipments, orders),
          "document_variables_delivery_note",
        ),
    inv !== undefined && available.has("dunning_letter")
      ? qualified(
          dunningFunction(parts, inv),
          "document_variables_dunning_letter",
        )
      : "",
    inv === undefined
      ? ""
      : qualified(
          statementFunction(parts, inv),
          "document_variables_statement",
        ),
  ];

  const branch = (type: string, call: string): string =>
    available.has(type)
      ? `when '${type}' then return ${call};`
      : `when '${type}' then ${fail("DOCUMENT_TYPE_UNAVAILABLE", `${type.replaceAll("_", " ")} documents need the ${SOURCE[type] ?? "source"} block`, "22023")}`;

  const dispatcher = `
-- The variable payload of one document, in the shape of the contract. The
-- caller reads the source rows through row level security. The document
-- language and the template are added by render_document.
create or replace function ${fn("document_variables")}(tenant ${ctx.idType}, document_type text, document_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  case document_variables.document_type
    ${branch("invoice", `${fn("document_variables_invoice")}(tenant, document_id, false)`)}
    ${branch("credit_note", `${fn("document_variables_invoice")}(tenant, document_id, true)`)}
    ${branch("quote", `${fn("document_variables_quote")}(tenant, document_id)`)}
    ${branch("order", `${fn("document_variables_order")}(tenant, document_id)`)}
    ${branch("delivery_note", `${fn("document_variables_delivery_note")}(tenant, document_id)`)}
    ${branch("dunning_letter", `${fn("document_variables_dunning_letter")}(tenant, document_id)`)}
    ${branch("statement", `${fn("document_variables_statement")}(tenant, document_id)`)}
    else
      ${fail("DOCUMENT_TYPE_INVALID", "unknown document type", "22023")}
  end case;
end;
$$;
${userGrant(`${fn("document_variables")}(${ctx.idType}, text, uuid)`)}
`;

  return `${builders.join("")}${qualified(dispatcher, "document_variables")}`;
}
