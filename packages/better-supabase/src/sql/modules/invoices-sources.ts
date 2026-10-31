import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlTableSpec,
} from "../context.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/** The source kinds `invoice_from_sources` takes. */
const SOURCE_TYPES = ["order", "shipment", "time"] as const;

/** The order statuses whose delivered lines can be invoiced. */
const ORDER_STATUSES = ["confirmed", "paid", "fulfilled", "completed"];

/**
 * The `invoice_line_sources` table: which order line, shipment line or time
 * entry an invoice line bills, and how much of it.
 */
export const LINE_SOURCES_TABLE: BlockSqlTableSpec = {
  name: "invoice_line_sources",
  app: {},
  optionalTable: true,
  lifecycle: { tenant: "tenant", export: true },
  columns: {
    id: "id",
    tenant: "tenant_id",
    invoice: "invoice_id",
    position: "position",
    source: "source",
    sourceId: "source_id",
    sourceLine: "source_line_id",
    orderLine: "order_line_id",
    quantity: "quantity",
    createdAt: "created_at",
  },
  optional: ["sourceLine", "orderLine"],
};

/** Whether this invoices layout can invoice sources. */
function hasSources(ctx: BlockSqlContext): boolean {
  return ctx.hasTable("lineSources") && ctx.installed("orders");
}

/** The sources table, its indexes and its read policy. */
export function lineSourcesTableSql(
  ctx: BlockSqlContext,
  invoices: string,
  invoiceId: string,
  read: string,
): string {
  if (!hasSources(ctx)) {
    return "";
  }

  const table = ctx.table("lineSources");
  const s = (column: string): string => ctx.col("lineSources", column);

  const optional = (logical: string, definition: string): string =>
    ctx.has("lineSources", logical) ? `\n  ${s(logical)} ${definition},` : "";

  return `
-- What each invoice line of invoice_from_sources bills: the order line,
-- shipment line or time entry and the quantity. A voided invoice releases its
-- rows, so the same source can be invoiced again.
create table if not exists ${table} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("invoice")} uuid not null references ${invoices} (${invoiceId}) on delete cascade,
  ${s("position")} integer not null,
  ${s("source")} text not null check (${s("source")} in (${SOURCE_TYPES.map(sqlString).join(", ")})),
  ${s("sourceId")} uuid not null,${optional("sourceLine", "uuid")}${optional("orderLine", "uuid")}
  ${s("quantity")} numeric(18, 4) not null check (${s("quantity")} > 0),
  ${s("createdAt")} timestamptz not null default now()
);
create index if not exists ${ctx.naming.rename("invoice_line_sources_invoice_idx")} on ${table} (${s("invoice")});
create index if not exists ${ctx.naming.rename("invoice_line_sources_source_idx")} on ${table} (${s("tenant")}, ${s("source")}, ${s("sourceId")});${ctx.has("lineSources", "orderLine") ? `\ncreate index if not exists ${ctx.naming.rename("invoice_line_sources_order_line_idx")} on ${table} (${s("orderLine")}) where ${s("orderLine")} is not null;` : ""}${ctx.has("lineSources", "sourceLine") ? `\ncreate index if not exists ${ctx.naming.rename("invoice_line_sources_line_idx")} on ${table} (${s("source")}, ${s("sourceLine")}) where ${s("sourceLine")} is not null;` : ""}
${lockModuleTable(ctx, "lineSources", { read: true })}
${renderPolicy(
  makePolicy({
    table,
    name: ctx.naming.rename("invoice_line_sources_read"),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(s("tenant"), read),
  }),
  { drop: true, target: table },
)}
`;
}

/** The functions of source invoicing for the module contract. */
export function sourceContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!hasSources(ctx)) {
    return [];
  }

  return [
    {
      name: "invoice_from_sources",
      args: ["{id}", "jsonb", "jsonb", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "sources_ready_to_invoice",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
  ];
}

/** How the candidate query reads its sources. */
interface Scope {
  /** The orders and their lines, restricted to the refs or to a tenant. */
  readonly orders: string;
  readonly shipments: string;
}

/**
 * `invoice_from_sources` and `sources_ready_to_invoice`: one invoice per
 * billing party and currency from several delivered orders, delivered shipments
 * and unbilled time.
 */
export function sourceFunctions(ctx: BlockSqlContext, n: InvoiceNames): string {
  if (!hasSources(ctx)) {
    return "";
  }

  const { fn, t } = n;
  const orders = ctx.of("orders");
  const catalog = ctx.of("catalog");
  const i = (column: string): string => ctx.col("invoices", column);
  const s = (column: string): string => ctx.col("lineSources", column);
  const o = (column: string): string => orders.col("orders", column);
  const l = (column: string): string => orders.col("orderLines", column);
  const oHas = (column: string): boolean => orders.has("orders", column);
  const lHas = (column: string): boolean => orders.has("orderLines", column);

  const ship = ctx.installed("shipments") ? ctx.of("shipments") : undefined;

  const shipments =
    ship !== undefined &&
    ship.has("shipments", "subjectType") &&
    ship.has("shipments", "subjectId")
      ? ship
      : undefined;

  const time = ctx.installed("billable-time")
    ? ctx.of("billable-time")
    : undefined;

  const variantType = sqlString(catalog.naming.rename("product_variant"));

  const live = (alias: string): string =>
    ctx.is("invoices", "status", `${alias}.${i("status")}`, ["void"], true);

  const orderOk = (alias: string): string =>
    `${orders.is("orders", "status", `${alias}.${o("status")}`, ORDER_STATUSES)}${oHas("invoicedAt") ? ` and ${alias}.${o("invoicedAt")} is null` : ""}${oHas("isSelected") ? ` and ${alias}.${o("isSelected")}` : ""}`;

  const column = (has: boolean, expression: string, otherwise: string) =>
    has ? expression : otherwise;

  // Quantity of order line `line` already on a live invoice.
  const invoicedOf = (line: string): string =>
    `coalesce((select sum(z.${s("quantity")}) from ${t("lineSources")} z join ${t("invoices")} zi on zi.${i("id")} = z.${s("invoice")}
      where z.${s("orderLine")} = ${line} and ${live("zi")}), 0)`;

  const doneJoin = `cross join lateral (select ${invoicedOf(`l.${l("id")}`)}::numeric as done) d`;

  const raw = (scope: Scope): string => {
    const orderPart = `
    select 'order'::text as source_type, o.${o("id")} as source_id, l.${l("id")} as source_line, l.${l("id")} as order_line,
      o.${o("number")}::text as ref, l.${l("position")} as pos, l.${l("title")} as title,
      greatest(case when l.${l("requiresShipping")} then l.${l("fulfilled")} else l.${l("quantity")} end - l.${l("returned")}, 0)::numeric - d.done as avail,
      want.qty as requested, d.done, l.${l("quantity")}::numeric as order_quantity, l.${l("unitAmount")} as unit_amount,
      l.${l("discount")} as discount, l.${l("total")} as total, l.${l("tax")} as tax, o.${o("taxInclusive")} as tax_inclusive,
      ${column(lHas("taxCodeId"), `l.${l("taxCodeId")}`, "null::uuid")} as tax_code_id, l.${l("variant")} as variant,
      ${column(lHas("billingParty"), `l.${l("billingParty")}`, "'customer'::text")} as billing_party,
      ${column(lHas("billingPartyId"), `l.${l("billingPartyId")}`, "null::text")} as billing_party_id,
      ${column(lHas("billingAccountId"), `l.${l("billingAccountId")}`, "null::uuid")} as billing_account_id,
      ${column(lHas("unitCost"), `l.${l("unitCost")}`, "null::bigint")} as unit_cost,
      o.${o("currency")}::text as currency, ${column(oHas("buyer"), `o.${o("buyer")}`, "null::jsonb")} as buyer
    ${scope.orders}`;

    const shipmentPart =
      shipments === undefined
        ? ""
        : `
    union all
    select 'shipment'::text, sh.${shipments.col("shipments", "id")}, sl.${shipments.col("lines", "id")}, l.${l("id")},
      coalesce(sh.${shipments.col("shipments", "reference")}, sh.${shipments.col("shipments", "id")}::text), l.${l("position")}, l.${l("title")},
      least(sl.${shipments.col("lines", "quantity")}::numeric - coalesce((select sum(z.${s("quantity")}) from ${t("lineSources")} z join ${t("invoices")} zi on zi.${i("id")} = z.${s("invoice")}
        where z.${s("source")} = 'shipment' and z.${s("sourceLine")} = sl.${shipments.col("lines", "id")} and ${live("zi")}), 0),
        greatest(l.${l("quantity")} - l.${l("returned")}, 0)::numeric - d.done),
      null::numeric, d.done, l.${l("quantity")}::numeric, l.${l("unitAmount")},
      l.${l("discount")}, l.${l("total")}, l.${l("tax")}, o.${o("taxInclusive")},
      ${column(lHas("taxCodeId"), `l.${l("taxCodeId")}`, "null::uuid")}, l.${l("variant")},
      ${column(lHas("billingParty"), `l.${l("billingParty")}`, "'customer'::text")},
      ${column(lHas("billingPartyId"), `l.${l("billingPartyId")}`, "null::text")},
      ${column(lHas("billingAccountId"), `l.${l("billingAccountId")}`, "null::uuid")},
      ${column(lHas("unitCost"), `l.${l("unitCost")}`, "null::bigint")},
      o.${o("currency")}::text, ${column(oHas("buyer"), `o.${o("buyer")}`, "null::jsonb")}
    ${scope.shipments}`;

    return `${orderPart}${shipmentPart}`;
  };

  // The lines still to invoice: quantity now, the discount of that share and the
  // tax rate the order's tax implies.
  const candidates = (scope: Scope): string => `
  select r.source_type as "sourceType", r.source_id as "sourceId", r.source_line as "sourceLine", r.order_line as "orderLine",
    r.ref, r.pos, r.title || ' (' || r.ref || ')' as description, q.qty, r.avail, r.requested,
    r.unit_amount as "unitAmount",
    (round(r.discount::numeric * (r.done + q.qty) / r.order_quantity) - round(r.discount::numeric * r.done / r.order_quantity))::bigint as "discountAmount",
    case when n.net > 0 then round(r.tax * 10000.0 / n.net)::integer else 0 end as "taxRateBps",
    r.tax_code_id as "taxCodeId", r.variant, r.billing_party as "billingParty", r.billing_party_id as "billingPartyId",
    r.billing_account_id as "billingAccountId", r.unit_cost as "unitCost", r.currency, r.tax_inclusive as "taxInclusive", r.buyer
  from (${raw(scope)}) r
  cross join lateral (select case when r.requested is null then r.avail else least(r.requested, r.avail) end as qty) q
  cross join lateral (select case when r.tax_inclusive then r.total - r.tax else r.total end as net) n
  where q.qty > 0 or r.avail <= 0 or r.requested is not null`;

  const wantedLine = (alias: string, ref: string): string =>
    `left join lateral (select (w ->> 'quantity')::numeric as qty from jsonb_array_elements(${ref} -> 'lines') w
      where (w ->> 'id')::uuid = ${alias}.${l("id")} limit 1) want on true`;

  const refScope: Scope = {
    orders: `from jsonb_array_elements(v_refs) r0(ref)
    join ${orders.table("orders")} o on r0.ref ->> 'type' = 'order' and o.${o("id")} = (r0.ref ->> 'id')::uuid and o.${o("tenant")} = invoice_from_sources.tenant and ${orderOk("o")}
    join ${orders.table("orderLines")} l on l.${l("order")} = o.${o("id")}
    ${wantedLine("l", "r0.ref")}
    ${doneJoin}
    where r0.ref -> 'lines' is null or want.qty is not null`,
    shipments:
      shipments === undefined
        ? ""
        : `from jsonb_array_elements(v_refs) r0(ref)
    join ${shipments.table("shipments")} sh on r0.ref ->> 'type' = 'shipment' and sh.${shipments.col("shipments", "id")} = (r0.ref ->> 'id')::uuid and sh.${shipments.col("shipments", "tenant")} = invoice_from_sources.tenant
      and ${shipments.is("shipments", "status", `sh.${shipments.col("shipments", "status")}`, ["delivered"])} and sh.${shipments.col("shipments", "subjectType")} = 'order'
    join ${shipments.table("lines")} sl on sl.${shipments.col("lines", "shipment")} = sh.${shipments.col("shipments", "id")} and sl.${shipments.col("lines", "direction")} = 'outbound'
    join ${orders.table("orders")} o on o.${o("id")}::text = sh.${shipments.col("shipments", "subjectId")} and o.${o("tenant")} = sh.${shipments.col("shipments", "tenant")} and ${orderOk("o")}
    join lateral (select x.* from ${orders.table("orderLines")} x where x.${l("order")} = o.${o("id")} and x.${l("variant")} = sl.${shipments.col("lines", "variant")}
      order by x.${l("position")}, x.${l("id")} limit 1) l on true
    left join lateral (select null::numeric as qty) want on true
    ${doneJoin}`,
  };

  const partyFilter = `(list_party is null or (${oHas("buyer") ? `o.${o("buyer")} @> list_party` : "false"}))`;

  const allScope: Scope = {
    orders: `from ${orders.table("orders")} o
    join ${orders.table("orderLines")} l on l.${l("order")} = o.${o("id")}
    left join lateral (select null::numeric as qty) want on true
    ${doneJoin}
    where o.${o("tenant")} = sources_ready_to_invoice.tenant and ${orderOk("o")}
      and ${partyFilter.replaceAll("list_party", "sources_ready_to_invoice.party")}`,
    shipments:
      shipments === undefined
        ? ""
        : `from ${shipments.table("shipments")} sh
    join ${shipments.table("lines")} sl on sl.${shipments.col("lines", "shipment")} = sh.${shipments.col("shipments", "id")} and sl.${shipments.col("lines", "direction")} = 'outbound'
    join ${orders.table("orders")} o on o.${o("id")}::text = sh.${shipments.col("shipments", "subjectId")} and o.${o("tenant")} = sh.${shipments.col("shipments", "tenant")} and ${orderOk("o")}
    join lateral (select x.* from ${orders.table("orderLines")} x where x.${l("order")} = o.${o("id")} and x.${l("variant")} = sl.${shipments.col("lines", "variant")}
      order by x.${l("position")}, x.${l("id")} limit 1) l on true
    left join lateral (select null::numeric as qty) want on true
    ${doneJoin}
    where sh.${shipments.col("shipments", "tenant")} = sources_ready_to_invoice.tenant and sh.${shipments.col("shipments", "subjectType")} = 'order'
      and ${shipments.is("shipments", "status", `sh.${shipments.col("shipments", "status")}`, ["delivered"])}
      and ${partyFilter.replaceAll("list_party", "sources_ready_to_invoice.party")}`,
  };

  // The candidate rows of the orders and shipments among the refs. A shipment
  // line's quantity is capped by what its order line still has.
  const lineJson = (value: string): string =>
    `jsonb_strip_nulls(jsonb_build_object(
        'description', ${value} ->> 'description', 'quantity', (${value} ->> 'qty')::numeric,
        'unitAmount', (${value} ->> 'unitAmount'), 'discountAmount', (${value} ->> 'discountAmount'),
        'taxRateBps', (${value} ->> 'taxRateBps')::integer, 'taxCodeId', ${value} ->> 'taxCodeId',
        'billingParty', ${value} ->> 'billingParty', 'billingPartyId', ${value} ->> 'billingPartyId',
        'billingAccountId', ${value} ->> 'billingAccountId', 'unitCost', ${value} ->> 'unitCost',
        'product', case when ${value} ->> 'variant' is null then null else jsonb_build_object('type', ${variantType}, 'id', ${value} ->> 'variant') end))`;

  const timeLines = (scopeSql: string): string =>
    time === undefined
      ? "'[]'::jsonb"
      : `${time.fn("time_lines_for_invoice")}(invoice_from_sources.tenant, ${scopeSql}, coalesce(${scopeSql} ->> 'groupBy', 'subject'))`;

  const readTimeLines =
    time === undefined
      ? "'[]'::jsonb"
      : `${time.fn("time_lines_for_invoice")}(sources_ready_to_invoice.tenant, case when sources_ready_to_invoice.party is null then null else jsonb_build_object('subject', sources_ready_to_invoice.party) end, 'subject')`;

  const claimTime =
    time === undefined
      ? ""
      : `
    if jsonb_array_length(v_time_ids) > 0 then
      v_claimed := ${time.fn("claim_time_for_invoice")}(invoice_from_sources.tenant, (v_invoice ->> ${sqlString(ctx.colName("invoices", "id"))})::uuid, v_time_ids);
      insert into ${t("lineSources")} (${s("tenant")}, ${s("invoice")}, ${s("position")}, ${s("source")}, ${s("sourceId")}, ${s("quantity")})
      select invoice_from_sources.tenant, (v_invoice ->> ${sqlString(ctx.colName("invoices", "id"))})::uuid, g.ordinality, 'time', (x.value)::uuid,
        greatest(round(((c.value ->> 'seconds')::numeric) / 3600.0, 4), 0.0001)
      from jsonb_array_elements(v_group_rows) with ordinality g(value, ordinality)
      cross join lateral jsonb_array_elements_text(coalesce(g.value -> 'entryIds', '[]'::jsonb)) x(value)
      join jsonb_array_elements(v_claimed) c(value) on c.value ->> 'entryId' = x.value
      where g.value ->> 'sourceType' = 'time';
    end if;`;

  const timeGather =
    time === undefined
      ? ""
      : `
  for v_ref in select e.value from jsonb_array_elements(v_refs) e where e.value ->> 'type' = 'time' loop
    v_time := ${timeLines("coalesce(v_ref -> 'scope', '{}'::jsonb)")};
    v_cand := v_cand || coalesce((select jsonb_agg(jsonb_build_object(
        'sourceType', 'time', 'sourceId', null, 'description', x.value ->> 'description', 'qty', (x.value ->> 'quantity')::numeric,
        'avail', (x.value ->> 'quantity')::numeric, 'unitAmount', (x.value ->> 'unitAmount')::bigint, 'discountAmount', 0, 'taxRateBps', 0,
        'billingParty', 'customer', 'currency', x.value ->> 'currency', 'taxInclusive', false, 'entryIds', x.value -> 'entryIds')
        order by x.ordinality) from jsonb_array_elements(v_time) with ordinality x(value, ordinality)), '[]'::jsonb);
    v_time_seen := v_time_seen + 1;
  end loop;`;

  const refCheck = `
  for v_ref in select e.value from jsonb_array_elements(v_refs) e loop
    if jsonb_typeof(v_ref) is distinct from 'object' or (v_ref ->> 'type') is null or (v_ref ->> 'type') not in (${SOURCE_TYPES.map(sqlString).join(", ")}) then
      ${fail("INVOICE_SOURCE_INVALID", "each source is an object with a type of order, shipment or time", "22023")}
    end if;
    if (v_ref ->> 'type') = 'time' then
      ${time === undefined ? fail("INVOICE_SOURCE_UNSUPPORTED", "install billable-time to invoice time", "22023") : "null;"}
    elsif (v_ref ->> 'id') is null or (v_ref ->> 'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      ${fail("INVOICE_SOURCE_INVALID", "an order or shipment source needs an id", "22023")}
    elsif (v_ref ->> 'type') = 'shipment' and ${shipments === undefined ? "true" : "false"} then
      ${fail("INVOICE_SOURCE_UNSUPPORTED", "this layout has no shipments with a subject to invoice", "22023")}
    elsif v_ref -> 'lines' is not null and (jsonb_typeof(v_ref -> 'lines') is distinct from 'array' or (v_ref ->> 'type') <> 'order'
      or exists (select 1 from jsonb_array_elements(v_ref -> 'lines') w where jsonb_typeof(w) is distinct from 'object' or (w ->> 'id') is null
        or (w ->> 'quantity') is null or (w ->> 'quantity') !~ '^[0-9]{1,10}$' or (w ->> 'quantity')::numeric <= 0)) then
      ${fail("INVOICE_SOURCE_INVALID", "lines is a list of { id, quantity } with a whole positive quantity, on an order source", "22023")}
    end if;
  end loop;`;

  const foundCheck = `
  for v_ref in select e.value from jsonb_array_elements(v_refs) e where e.value ->> 'type' in ('order', 'shipment') loop
    if (v_ref ->> 'type') = 'order' then
      if not exists (select 1 from ${orders.table("orders")} o where o.${o("id")} = (v_ref ->> 'id')::uuid and o.${o("tenant")} = invoice_from_sources.tenant) then
        ${fail("INVOICE_SOURCE_NOT_FOUND", "no such order in this organization", "P0002")}
      end if;
      if not exists (select 1 from ${orders.table("orders")} o where o.${o("id")} = (v_ref ->> 'id')::uuid and ${orderOk("o")}) then
        ${fail("INVOICE_SOURCE_NOT_READY", "an order is invoiced once it is confirmed or paid and wasn't invoiced at checkout", "55000")}
      end if;
    else${
      shipments === undefined
        ? ""
        : `
      if not exists (select 1 from ${shipments.table("shipments")} sh where sh.${shipments.col("shipments", "id")} = (v_ref ->> 'id')::uuid and sh.${shipments.col("shipments", "tenant")} = invoice_from_sources.tenant) then
        ${fail("INVOICE_SOURCE_NOT_FOUND", "no such shipment in this organization", "P0002")}
      end if;
      if not exists (select 1 from ${shipments.table("shipments")} sh where sh.${shipments.col("shipments", "id")} = (v_ref ->> 'id')::uuid
        and ${shipments.is("shipments", "status", `sh.${shipments.col("shipments", "status")}`, ["delivered"])} and sh.${shipments.col("shipments", "subjectType")} = 'order') then
        ${fail("INVOICE_SOURCE_NOT_READY", "a shipment is invoiced once it is delivered and belongs to an order", "55000")}
      end if;`
    }
      null;
    end if;
  end loop;`;

  const readable = `(${n.service} or ${ctx.scope.can("sources_ready_to_invoice.tenant", n.read)})`;

  return `
-- Invoices several delivered sources for one billing party. party is { type, id }
-- (the company or contact invoiced). source_refs is a list of
--   { type: "order", id, lines?: [{ id, quantity }] }  the delivered, unreturned quantity of
--     the order's lines, or of the listed lines up to the quantity given,
--   { type: "shipment", id }  a delivered shipment of an order: its outbound lines at
--     the order lines' prices, and
--   { type: "time", scope?: { subject, userId, starts, ends, entryIds, groupBy } }  unbilled
--     billable time at its rates.
-- The sources split into one draft invoice per billing party and currency (and prices
-- with or without tax); invoice_line_sources keeps what each line bills, so a source is
-- invoiced once: calling again returns it in skipped and writes nothing. A voided invoice
-- releases its sources. options: title, attrs (to create_invoice: termsDays, note,
-- legalEntityId and the extra columns; payment terms follow the party's). Not in import mode.
create or replace function ${fn("invoice_from_sources")}(tenant ${ctx.idType}, party jsonb, source_refs jsonb, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refs jsonb := invoice_from_sources.source_refs;
  v_options jsonb := coalesce(invoice_from_sources.options, '{}'::jsonb);
  v_cand jsonb := '[]'::jsonb;
  v_time jsonb;
  v_time_seen integer := 0;
  v_time_ids jsonb;
  v_claimed jsonb;
  v_ref jsonb;
  v_group record;
  v_group_rows jsonb;
  v_lines jsonb;
  v_attrs jsonb;
  v_company jsonb;
  v_invoice jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  if ${ctx.importing()} then
    ${fail("INVOICE_SOURCES_IMPORTING", "sources are not invoiced in import mode; import the invoices instead", "55000")}
  end if;
  if not (${n.service} or ${ctx.scope.can("invoice_from_sources.tenant", n.create)}) then
    ${fail("INVOICE_FORBIDDEN", "not allowed to change invoices")}
  end if;
  if jsonb_typeof(invoice_from_sources.party) is distinct from 'object' or nullif(trim(invoice_from_sources.party ->> 'type'), '') is null
    or nullif(trim(invoice_from_sources.party ->> 'id'), '') is null then
    ${fail("INVOICE_SOURCE_INVALID", "party is { type, id }", "22023")}
  end if;
  if jsonb_typeof(v_refs) is distinct from 'array' or jsonb_array_length(v_refs) not between 1 and 200 then
    ${fail("INVOICE_SOURCE_INVALID", "source_refs is a list of 1 to 200 sources", "22023")}
  end if;
  if jsonb_typeof(v_options) is distinct from 'object' then
    ${fail("INVOICE_SOURCE_INVALID", "options is an object", "22023")}
  end if;${refCheck}
  perform pg_advisory_xact_lock(hashtextextended('invoice_sources:' || invoice_from_sources.tenant::text, 0));${foundCheck}
  select coalesce(jsonb_agg(to_jsonb(c) order by c."sourceType", c.ref, c."sourceId", c.pos), '[]'::jsonb) into v_cand
  from (${candidates(refScope)}) c;${timeGather}
  if exists (select 1 from jsonb_array_elements(v_cand) e where e.value ->> 'requested' is not null
    and (e.value ->> 'requested')::numeric > (e.value ->> 'avail')::numeric and (e.value ->> 'avail')::numeric > 0) then
    ${fail("INVOICE_SOURCE_QUANTITY", "a line is invoiced for more than is delivered and not yet invoiced", "22023")}
  end if;
  if exists (select 1 from jsonb_array_elements(v_cand) e where jsonb_typeof(e.value -> 'buyer') = 'object' and e.value -> 'buyer' ->> 'id' is not null
    and (e.value -> 'buyer' ->> 'id') is distinct from (invoice_from_sources.party ->> 'id')
    and (e.value ->> 'qty')::numeric > 0) then
    ${fail("INVOICE_SOURCE_PARTY", "an order was placed by another buyer than the party", "22023")}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('type', r.value ->> 'type', 'id', r.value ->> 'id', 'reason', 'invoiced')), '[]'::jsonb) into v_skipped
  from jsonb_array_elements(v_refs) r
  where r.value ->> 'type' in ('order', 'shipment') and not exists (
    select 1 from jsonb_array_elements(v_cand) e where e.value ->> 'sourceId' = r.value ->> 'id' and (e.value ->> 'qty')::numeric > 0);
  for v_group in
    select distinct e.value ->> 'billingParty' as billing_party, e.value ->> 'billingPartyId' as billing_party_id,
      e.value ->> 'currency' as currency, (e.value ->> 'taxInclusive')::boolean as tax_inclusive
    from jsonb_array_elements(v_cand) e where (e.value ->> 'qty')::numeric > 0
    order by 1, 2 nulls first, 3, 4
  loop
    select jsonb_agg(${lineJson("e.value")} order by e.ordinality), jsonb_agg(e.value order by e.ordinality),
      coalesce(jsonb_agg(e.value -> 'entryIds') filter (where e.value ->> 'sourceType' = 'time'), '[]'::jsonb)
      into v_lines, v_group_rows, v_time_ids
    from jsonb_array_elements(v_cand) with ordinality e(value, ordinality)
    where (e.value ->> 'qty')::numeric > 0 and e.value ->> 'billingParty' = v_group.billing_party
      and e.value ->> 'billingPartyId' is not distinct from v_group.billing_party_id
      and e.value ->> 'currency' = v_group.currency and (e.value ->> 'taxInclusive')::boolean = v_group.tax_inclusive;
    select coalesce(jsonb_agg(z.id), '[]'::jsonb) into v_time_ids from (
      select distinct x.value as id from jsonb_array_elements(v_time_ids) g, jsonb_array_elements(g.value) x(value)) z;
    v_company := case when v_group.billing_party <> 'customer' and v_group.billing_party_id is not null
      then jsonb_build_object('type', invoice_from_sources.party ->> 'type', 'id', v_group.billing_party_id)
      else jsonb_build_object('type', invoice_from_sources.party ->> 'type', 'id', invoice_from_sources.party ->> 'id') end;
    v_attrs := (coalesce(v_options -> 'attrs', '{}'::jsonb) - 'origin' - 'currency' - 'company' - 'pricesIncludeTax')
      || jsonb_build_object('company', v_company, 'currency', v_group.currency,
        'title', coalesce(nullif(trim(v_options ->> 'title'), ''), nullif(trim(v_options -> 'attrs' ->> 'title'), ''), 'Delivered goods and services'))
      || case when v_group.tax_inclusive then jsonb_build_object('pricesIncludeTax', true) else '{}'::jsonb end;
    v_invoice := ${fn("create_invoice")}(invoice_from_sources.tenant, v_attrs, v_lines);
    insert into ${t("lineSources")} (${s("tenant")}, ${s("invoice")}, ${s("position")}, ${s("source")}, ${s("sourceId")}${ctx.has("lineSources", "sourceLine") ? `, ${s("sourceLine")}` : ""}${ctx.has("lineSources", "orderLine") ? `, ${s("orderLine")}` : ""}, ${s("quantity")})
    select invoice_from_sources.tenant, (v_invoice ->> ${sqlString(ctx.colName("invoices", "id"))})::uuid, g.ordinality, g.value ->> 'sourceType', (g.value ->> 'sourceId')::uuid${ctx.has("lineSources", "sourceLine") ? ", (g.value ->> 'sourceLine')::uuid" : ""}${ctx.has("lineSources", "orderLine") ? ", (g.value ->> 'orderLine')::uuid" : ""}, (g.value ->> 'qty')::numeric
    from jsonb_array_elements(v_group_rows) with ordinality g(value, ordinality)
    where g.value ->> 'sourceType' <> 'time';${claimTime}
    v_invoices := v_invoices || jsonb_build_array(v_invoice);
  end loop;
  return jsonb_build_object('invoices', v_invoices, 'skipped', v_skipped);
end;
$$;
${userGrant(`${fn("invoice_from_sources")}(${ctx.idType}, jsonb, jsonb, jsonb)`)}

-- The sources an organization can invoice now: delivered order lines and
-- shipments with quantity left, and unbilled time, each with the amount before
-- tax. party is { type, id } and keeps the orders whose buyer matches it and the
-- time on that subject; without it every source is listed.
create or replace function ${fn("sources_ready_to_invoice")}(tenant ${ctx.idType}, party jsonb default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${readable} then
    ${fail("INVOICE_FORBIDDEN", "not allowed to read invoices")}
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('type', g."sourceType", 'id', g."sourceId", 'reference', g.ref, 'currency', g.currency,
      'lines', g.lines, 'quantity', g.quantity::text, 'amount', g.amount::text) order by g."sourceType", g.ref, g."sourceId")
    from (select c."sourceType", c."sourceId", min(c.ref) as ref, min(c.currency) as currency, count(*) as lines, sum(c.qty) as quantity,
        sum(round(c.qty * c."unitAmount") - c."discountAmount")::bigint as amount
      from (${candidates(allScope)}) c where c.qty > 0
      group by c."sourceType", c."sourceId") g), '[]'::jsonb)
    || coalesce((select jsonb_agg(jsonb_build_object('type', 'time', 'id', null, 'reference', x.value ->> 'description', 'currency', x.value ->> 'currency',
        'lines', 1, 'quantity', x.value ->> 'quantity', 'amount', round((x.value ->> 'quantity')::numeric * (x.value ->> 'unitAmount')::numeric)::bigint::text,
        'entryIds', x.value -> 'entryIds') order by x.ordinality)
      from jsonb_array_elements(${readTimeLines}) with ordinality x(value, ordinality)), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("sources_ready_to_invoice")}(${ctx.idType}, jsonb)`)}
`;
}
