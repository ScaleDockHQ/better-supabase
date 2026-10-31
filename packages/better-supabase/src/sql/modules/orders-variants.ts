import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { fail, userGrant } from "../shared.ts";
import { columns, guard } from "./orders-shared.ts";

const VARIANT_COLUMNS = ["variantOf", "variantLabel", "isSelected"] as const;

/** Whether the orders table can group variants of one order. */
function hasOrderVariants(ctx: BlockSqlContext): boolean {
  return VARIANT_COLUMNS.every((column) => ctx.has("orders", column));
}

/** The variant functions for the orders contract. */
export function orderVariantContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  if (!hasOrderVariants(ctx)) {
    return [];
  }

  return [
    {
      name: "set_order_variant",
      args: ["uuid", "uuid", "text"],
      returns: "jsonb",
    },
    { name: "select_order_variant", args: ["uuid"], returns: "jsonb" },
    { name: "list_order_variants", args: ["uuid"], returns: "jsonb" },
  ];
}

/**
 * `set_order_variant`, `select_order_variant` and `list_order_variants`:
 * alternative orders of one scope, one of which is the selected one.
 */
export function orderVariantFunctions(
  ctx: BlockSqlContext,
  n: OrdersNames,
): string {
  if (!hasOrderVariants(ctx)) {
    return "";
  }

  const { fn } = n;
  const orders = ctx.table("orders");
  const o = columns(ctx, "orders");

  const cancelled = ctx.is("orders", "status", `v_order.${o("status")}`, [
    "cancelled",
    "refunded",
  ]);

  const group = (row: string): string =>
    `coalesce(${row}.${o("variantOf")}, ${row}.${o("id")})`;

  const rowJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${o("id")}, 'number', ${alias}.${o("number")}, 'variantOf', ${alias}.${o("variantOf")}, 'variantLabel', ${alias}.${o("variantLabel")}, 'isSelected', ${alias}.${o("isSelected")}, 'total', ${alias}.${o("total")}::text, 'currency', ${alias}.${o("currency")})`;

  return `
-- Puts an order into the variant group of another order (variant_of is the
-- group's first order), or takes it out of its group when variant_of is null.
-- Both orders belong to the same organization and use the same currency.
create or replace function ${fn("set_order_variant")}(id uuid, variant_of uuid, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_root record;
begin
  select * into v_order from ${orders} x where x.${o("id")} = set_order_variant.id for update;
  if not found then
    ${fail("ORDER_NOT_FOUND", "no such order", "P0002")}
  end if;
  ${guard(ctx.scope, n.manage, `v_order.${o("tenant")}`)}
  if set_order_variant.variant_of is null then
    update ${orders} x set ${o("variantOf")} = null, ${o("variantLabel")} = null, ${o("isSelected")} = true
    where x.${o("id")} = v_order.${o("id")};
  else
    select * into v_root from ${orders} x where x.${o("id")} = set_order_variant.variant_of for update;
    if not found or v_root.${o("tenant")} <> v_order.${o("tenant")} then
      ${fail("ORDER_NOT_FOUND", "no such order to group with", "P0002")}
    end if;
    if v_root.${o("variantOf")} is not null or v_root.${o("id")} = v_order.${o("id")} or exists (
      select 1 from ${orders} s where s.${o("variantOf")} = v_order.${o("id")}) then
      ${fail("ORDER_VARIANT_INVALID", "group with the first order of a group, and not an order that has variants itself", "22023")}
    end if;
    if v_root.${o("currency")} <> v_order.${o("currency")} then
      ${fail("ORDER_VARIANT_INVALID", "variants share one currency", "22023")}
    end if;
    update ${orders} x set ${o("variantOf")} = v_root.${o("id")},
      ${o("variantLabel")} = coalesce(nullif(trim(set_order_variant.label), ''), x.${o("variantLabel")}),
      ${o("isSelected")} = false
    where x.${o("id")} = v_order.${o("id")};
    update ${orders} x set ${o("variantLabel")} = coalesce(nullif(x.${o("variantLabel")}, ''), 'Original')
    where x.${o("id")} = v_root.${o("id")};
  end if;
  return (select ${rowJson("x")} from ${orders} x where x.${o("id")} = v_order.${o("id")});
end;
$$;
${userGrant(`${fn("set_order_variant")}(uuid, uuid, text)`)}

-- Makes an order the selected one of its variant group and unselects the others.
create or replace function ${fn("select_order_variant")}(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
begin
  select * into v_order from ${orders} x where x.${o("id")} = select_order_variant.id;
  if not found then
    ${fail("ORDER_NOT_FOUND", "no such order", "P0002")}
  end if;
  ${guard(ctx.scope, n.manage, `v_order.${o("tenant")}`)}
  if ${group("v_order")} = v_order.${o("id")} and not exists (
    select 1 from ${orders} s where s.${o("variantOf")} = v_order.${o("id")}) then
    ${fail("ORDER_VARIANT_INVALID", "this order has no variants", "22023")}
  end if;
  if ${cancelled} then
    ${fail("ORDER_VARIANT_NOT_SELECTABLE", "a cancelled or refunded order can't be selected", "55000")}
  end if;
  perform 1 from ${orders} x where ${group("x")} = ${group("v_order")} order by x.${o("id")} for update;
  update ${orders} x set ${o("isSelected")} = (x.${o("id")} = v_order.${o("id")})
  where ${group("x")} = ${group("v_order")};
  return jsonb_build_object('order', (select ${rowJson("x")} from ${orders} x where x.${o("id")} = v_order.${o("id")}),
    'variants', (select coalesce(jsonb_agg(${rowJson("x")} order by x.${o("placedAt")}, x.${o("id")}), '[]'::jsonb)
      from ${orders} x where ${group("x")} = ${group("v_order")}));
end;
$$;
${userGrant(`${fn("select_order_variant")}(uuid)`)}

-- The orders of one variant group: the first order and its variants.
create or replace function ${fn("list_order_variants")}(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order record;
begin
  select * into v_order from ${orders} x where x.${o("id")} = list_order_variants.id;
  if not found then
    ${fail("ORDER_NOT_FOUND", "no such order", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can(`v_order.${o("tenant")}`, n.read)}) then
    ${fail("ORDERS_FORBIDDEN", "not allowed to read these orders")}
  end if;
  return (select coalesce(jsonb_agg(${rowJson("x")} order by x.${o("placedAt")}, x.${o("id")}), '[]'::jsonb)
    from ${orders} x where ${group("x")} = ${group("v_order")});
end;
$$;
${userGrant(`${fn("list_order_variants")}(uuid)`)}
`;
}
