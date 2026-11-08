import type { BlockSqlContext } from "../context.ts";
import type { Parts } from "./document-templates-parts.ts";

import { declared } from "../line-items-sql.ts";
import { userGrant } from "../shared.ts";
import {
  header,
  isoInstant,
  money,
  notFound,
  payload,
  quantity,
  source,
  terms,
  totals,
} from "./document-templates-parts.ts";

/**
 * Inventory's context when it has purchase orders with their lines, and the
 * catalog to name them.
 */
export function purchaseOrders(
  ctx: BlockSqlContext,
): BlockSqlContext | undefined {
  const stock = source(ctx, "inventory");

  return stock !== undefined &&
    stock.hasTable("purchaseOrders") &&
    stock.hasTable("purchaseOrderLines") &&
    source(ctx, "catalog") !== undefined
    ? stock
    : undefined;
}

export function purchaseOrderFunction(
  parts: Parts,
  stock: BlockSqlContext,
): string {
  const { ctx, fn, idType } = parts;
  const catalog = ctx.of("catalog");
  const t = stock.table("purchaseOrders");
  const o = (logical: string): string => stock.col("purchaseOrders", logical);

  const l = (logical: string): string =>
    stock.col("purchaseOrderLines", logical);

  const cv = (logical: string): string => catalog.col("variants", logical);

  // The ship-to address of a drop-ship order; an empty address otherwise.
  const shipTo = declared(stock, "purchaseOrders", "shipTo")
    ? `${fn("document_address")}(v_row.${o("shipTo")})`
    : `${fn("document_address")}(null::jsonb)`;

  return `
-- A purchase order as a document: the supplier is the document's party, the
-- amounts are the ordered quantities at their unit cost, with no tax.
create or replace function ${fn("document_variables_purchase_order")}(tenant ${idType}, document_id uuid)
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
  v_subtotal bigint;
begin
  select * into v_row from ${t} x
    where x.${o("id")} = document_variables_purchase_order.document_id and x.${o("tenant")} = tenant;
  if not found then
    ${notFound}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', n.sku,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', ${quantity("n.quantity")},
      'unitAmount', ${money("n.unit_cost")},
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', ${money("n.amount")}
    ) order by n.n), '[]'::jsonb), coalesce(sum(n.amount), 0)::bigint into v_lines, v_subtotal
  from (
    select row_number() over (order by cv.${cv("sku")}, x.${l("id")}) as n,
      coalesce(cv.${cv("title")}, cv.${cv("sku")}) as description,
      cv.${cv("sku")} as sku,
      x.${l("quantity")} as quantity,
      x.${l("unitCost")} as unit_cost,
      round(x.${l("quantity")} * x.${l("unitCost")})::bigint as amount
    from ${stock.table("purchaseOrderLines")} x
    join ${catalog.table("variants")} cv on cv.${cv("id")} = x.${l("variant")}
    where x.${l("order")} = v_row.${o("id")}
  ) n;
  return ${payload({
    document: header({
      id: `v_row.${o("id")}::text`,
      type: "'purchase_order'",
      number: `'PO-' || upper(substr(replace(v_row.${o("id")}::text, '-', ''), 1, 8))`,
      status: `v_row.${o("status")}::text`,
      date: isoInstant(
        `coalesce(v_row.${o("placedAt")}, v_row.${o("createdAt")})`,
      ),
      currency: `trim(v_row.${o("currency")})`,
      note: declared(stock, "purchaseOrders", "note")
        ? `v_row.${o("note")}`
        : "null::text",
    }),
    entity: `${fn("document_entity")}(tenant, null::uuid)`,
    buyer: `${fn("document_party")}(tenant, case when v_row.${o("supplierType")} = 'company' then v_row.${o("supplierId")} end, case when v_row.${o("supplierType")} = 'person' then v_row.${o("supplierId")} end, null::jsonb, null::text, null::jsonb)`,
    lines: "v_lines",
    taxLines: "'[]'::jsonb",
    totals: totals({ subtotal: "v_subtotal::text", total: "v_subtotal::text" }),
    paymentTerms: terms({}),
    shipping: `jsonb_build_object('address', ${shipTo}, 'carrier', null::text, 'trackingNumber', null::text)`,
  })};
end;
$$;
${userGrant(`${fn("document_variables_purchase_order")}(${idType}, uuid)`)}
`;
}
