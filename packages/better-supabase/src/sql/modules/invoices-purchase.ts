import type { BlockSqlContext } from "../context.ts";
import type { InvoiceNames } from "./invoices-functions.ts";
import type { BlockSqlOperations } from "./permissions-model.ts";

import { sqlString } from "../../core/template.ts";
import { lineAmount, lineColumn } from "../line-items-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { linked } from "./manufacturing-sql.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { creditLimitSql } from "./procurement-sql.ts";

/** The invoice columns purchase bills add. */
export const PURCHASE_COLUMNS: readonly string[] = [
  "direction",
  "supplierReference",
  "purchaseOrder",
  "dimensions",
];

/** The purchase columns `create_invoice` writes, with their values. */
export const PURCHASE_VALUES = [
  ["direction", "coalesce(create_invoice.attrs ->> 'direction', 'sales')"],
  [
    "supplierReference",
    "nullif(trim(create_invoice.attrs ->> 'supplierReference'), '')",
  ],
  ["purchaseOrder", "(create_invoice.attrs ->> 'purchaseOrderId')::uuid"],
  [
    "dimensions",
    "coalesce(nullif(create_invoice.attrs -> 'dimensions', 'null'::jsonb), '{}'::jsonb)",
  ],
] as const;

/** What purchase bills add to the invoice names. */
export interface PurchaseNames {
  /** `invoices.purchase`: what every write on a purchase bill needs. */
  readonly purchase: string;
  /** `invoices.override_match`: pays a bill that doesn't match. */
  readonly overrideMatch: string;
  /** `orders.override_credit`: issues an invoice over the credit limit. */
  readonly overrideCredit: string;
  readonly purchasePrefix: string;
  readonly purchaseCreditPrefix: string;
  /** `options.matchTolerance`: the price difference a match accepts. */
  readonly tolerance: { readonly bps: number; readonly amount: number };
}

function matchTolerance(ctx: BlockSqlContext): PurchaseNames["tolerance"] {
  const value: unknown = ctx.option("matchTolerance") ?? {};
  const at = "blocks.invoices.options.matchTolerance";

  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(`${at} must be an object`);
  }

  const count = (key: string, number: unknown): number => {
    if (typeof number !== "number" || !Number.isInteger(number) || number < 0) {
      throw new TypeError(`${at}.${key} must be 0 or a positive integer`);
    }

    return number;
  };

  return {
    bps: count("bps", "bps" in value ? value.bps : 100),
    amount: count("amount", "amount" in value ? value.amount : 500),
  };
}

export function purchaseNames(
  ctx: BlockSqlContext,
  keys: BlockSqlOperations<"invoices">,
): PurchaseNames {
  const orders = ctx.installed("orders") ? ctx.of("orders") : undefined;

  return {
    purchase: ctx.permission("purchase", keys.purchase),
    overrideMatch: ctx.permission("overrideMatch", keys.overrideMatch),
    overrideCredit: sqlString(
      ctx.config.permissions["overrideCredit"] ??
        orders?.permissionKey(
          "overrideCredit",
          OPERATIONS["orders.overrideCredit"],
        ) ??
        OPERATIONS["orders.overrideCredit"],
    ),
    purchasePrefix: ctx.text("purchasePrefix", "BILL-"),
    purchaseCreditPrefix: ctx.text("purchaseCreditPrefix", "BCN-"),
    tolerance: matchTolerance(ctx),
  };
}

/** The helpers of `invoiceFunctions` the purchase SQL builds on. */
export interface PurchaseHelpers {
  readonly i: (column: string) => string;
  readonly balance: (alias: string) => string;
  readonly st: (value: string, labels: readonly string[]) => string;
  readonly kd: (value: string, labels: readonly string[]) => string;
  readonly record: (type: string, alias: string, extra?: string) => string;
}

/**
 * Purchase bills on the invoices table: the permission a write needs by
 * direction, the purchase order check, numbering per direction, the credit
 * limit on issue, the three-way match and the payment gate on it.
 */
export function invoicePurchase(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: PurchaseHelpers,
): {
  /** The permission a write on the row `alias` needs. */
  readonly routed: (alias: string, permission: string) => string;
  /** The permission creating an invoice from `attrs` needs. */
  readonly create: (attrs: string) => string;
  /** PL/pgSQL that checks the purchase keys of `attrs`. */
  readonly check: (attrs: string, tenant: string, direction: string) => string;
  /** PL/pgSQL that takes `sales` for a sales invoice, `purchase` for a bill. */
  readonly byDirection: (
    alias: string,
    sales: string,
    purchase: string,
  ) => string;
  /** PL/pgSQL run before an invoice is issued: the credit limit. */
  readonly issue: (alias: string) => string;
  /** PL/pgSQL run before a payment: the three-way match. */
  readonly payment: (alias: string, amount: string) => string;
  /** `invoice_aging`, by direction when the table has one. */
  readonly aging: string;
  readonly functions: string;
} {
  const { i, fn, t } = { ...h, fn: n.fn, t: n.t };
  const enabled = ctx.has("invoices", "direction");
  const inventory = linked(ctx, "inventory");

  const linesOk =
    inventory !== undefined &&
    inventory.hasTable("purchaseOrders") &&
    inventory.hasTable("purchaseOrderLines") &&
    ctx.has("invoices", "purchaseOrder");

  // The party a credit limit belongs to: the company, else the contact.
  const party = (alias: string): string => {
    const ids = (["company", "contact"] as const)
      .filter((each) => ctx.has("invoices", `${each}Id`))
      .map((each) => `${alias}.${i(`${each}Id`)}::text`);

    return ids.length === 0 ? "null" : `coalesce(${ids.join(", ")})`;
  };

  const isPurchase = (alias: string): string =>
    `${alias}.${i("direction")} = 'purchase'`;

  const routed = (alias: string, permission: string): string =>
    enabled && permission !== n.read
      ? `case when ${isPurchase(alias)} then ${n.purchase} else ${permission} end`
      : permission;

  const create = (attrs: string): string =>
    enabled
      ? `case when ${attrs} ->> 'direction' = 'purchase' then ${n.purchase} else ${n.create} end`
      : n.create;

  const orderExists = (id: string, tenant: string): string => {
    if (!linesOk) {
      return fail(
        "INVOICE_PURCHASE_ORDER_UNSUPPORTED",
        "purchase orders need the inventory block",
        "22023",
      );
    }

    const po = (column: string): string =>
      inventory.col("purchaseOrders", column);

    return `if not exists (select 1 from ${inventory.table("purchaseOrders")} y where y.${po("id")}::text = ${id} and y.${po("tenant")} = ${tenant}) then
      ${fail("INVOICE_PURCHASE_ORDER_NOT_FOUND", "no such purchase order in this organization", "P0002")}
    end if;`;
  };

  const check = (attrs: string, tenant: string, direction: string): string =>
    enabled
      ? `
  if ${attrs} ->> 'purchaseOrderId' is not null then
    if ${direction} is distinct from 'purchase' then
      ${fail("INVOICE_PURCHASE_ORDER_INVALID", "only a purchase bill refers to a purchase order", "22023")}
    end if;
    ${orderExists(`(${attrs} ->> 'purchaseOrderId')`, tenant)}
  end if;
  if ${attrs} ? 'dimensions' and jsonb_typeof(${attrs} -> 'dimensions') not in ('object', 'null') then
    ${fail("INVOICE_ATTRS_INVALID", "dimensions is an object of dimension keys and value codes", "22023")}
  end if;`
      : `
  if ${attrs} ->> 'direction' = 'purchase' or ${attrs} ->> 'purchaseOrderId' is not null then
    ${fail("INVOICE_DIRECTION_UNSUPPORTED", "this invoices table has no direction column for purchase bills", "22023")}
  end if;`;

  const byDirection = (alias: string, sales: string, purchase: string) =>
    enabled
      ? `if ${isPurchase(alias)} then
      ${purchase}
    else
      ${sales}
    end if;`
      : sales;

  const credit = creditLimitSql(ctx, {
    party: party("v_row"),
    tenant: `v_row.${i("tenant")}`,
    currency: `v_row.${i("currency")}`,
    amount: `v_row.${i("total")}`,
    open: `select coalesce(sum(${h.balance("o")}), 0) from ${t("invoices")} o
      where o.${i("tenant")} = v_row.${i("tenant")} and o.${i("id")} <> v_row.${i("id")} and o.${i("currency")} = v_row.${i("currency")}
        and ${party("o")} = ${party("v_row")}${enabled ? ` and not ${isPurchase("o")}` : ""}
        and ${h.kd(`o.${i("kind")}`, ["invoice"])} and ${h.st(`o.${i("status")}`, ["issued", "partially_paid"])}`,
    override: `${n.service} or ${ctx.scope.can(`v_row.${i("tenant")}`, n.overrideCredit)}`,
    hint: "INVOICE_CREDIT_LIMIT_EXCEEDED",
    what: "this invoice",
  });

  const issue = (alias: string): string =>
    credit === ""
      ? ""
      : `
  if ${h.kd(`${alias}.${i("kind")}`, ["invoice"])}${enabled ? ` and not ${isPurchase(alias)}` : ""} and ${party(alias)} is not null then${credit.replaceAll("\n", "\n  ")}
  end if;`;

  const payment = (alias: string, amount: string): string =>
    enabled && linesOk
      ? `
  if ${isPurchase(alias)} and ${alias}.${i("purchaseOrder")} is not null and ${amount} > 0
    and ${fn("invoice_match_result")}(${alias}.${i("id")}) ->> 'status' <> 'matched'
    and not (${n.service} or ${ctx.scope.can(`${alias}.${i("tenant")}`, n.overrideMatch)}) then
    ${fail("INVOICE_MATCH_FAILED", "the bill doesn't match its purchase order and receipts; someone with invoices.override_match can pay it", "55000")}
  end if;`
      : "";

  const aging = `
-- What a tenant is owed in one currency on as_of, by days past due:
-- not yet due, 1 to 30, 31 to 60, 61 to 90 and over 90. Amounts are text.${
    enabled
      ? `
-- direction: sales (what customers owe) or purchase (what it owes suppliers).
drop function if exists ${fn("invoice_aging")}(${ctx.idType}, text, date);`
      : ""
  }
create or replace function ${fn("invoice_aging")}(tenant ${ctx.idType}, currency text, as_of date${enabled ? ", direction text default 'sales'" : ""})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with open as (
    select ${h.balance("x")} as balance, coalesce(invoice_aging.as_of, current_date) - x.${i("dueOn")} as late
    from ${t("invoices")} x
    where x.${i("tenant")} = invoice_aging.tenant and x.${i("currency")} = upper(invoice_aging.currency)
      and ${h.kd(`x.${i("kind")}`, ["invoice"])} and ${h.st(`x.${i("status")}`, ["issued", "partially_paid"])}${enabled ? ` and x.${i("direction")} = coalesce(invoice_aging.direction, 'sales')` : ""}
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
${userGrant(`${fn("invoice_aging")}(${ctx.idType}, text, date${enabled ? ", text" : ""})`)}
`;

  return {
    routed,
    create,
    check,
    byDirection,
    issue,
    payment,
    aging,
    functions: enabled ? matchFunctions(ctx, n, h, linesOk) : "",
  };
}

/**
 * `invoice_match_result`, the three-way match the payment gate reads, and
 * `purchase_bill_match`, which runs it for a reader and records
 * `invoice.match_checked`.
 */
function matchFunctions(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  h: PurchaseHelpers,
  linesOk: boolean,
): string {
  const { fn, t } = n;
  const { i } = h;
  const inventory = linked(ctx, "inventory");
  const l = (column: string): string => ctx.col("lines", column);
  const amount = lineAmount(ctx, "lines", "il");
  const product = lineColumn(ctx, "lines", "il", "productId");

  const order = ctx.has("invoices", "purchaseOrder")
    ? `v_row.${i("purchaseOrder")}`
    : "null::uuid";

  const discount = `round(${amount} * ${lineColumn(ctx, "lines", "il", "discountBps")} / 10000.0)`;
  const rate = lineColumn(ctx, "lines", "il", "taxRateBps");

  const inclusive = ctx.has("invoices", "pricesIncludeTax")
    ? `b.${i("pricesIncludeTax")}`
    : "false";

  const { bps, amount: slack } = n.tolerance;

  const body =
    linesOk && inventory !== undefined
      ? (() => {
          const pl = (column: string): string =>
            inventory.col("purchaseOrderLines", column);

          return `  with billed as (
    select il.${l("parent")} as bill, (${product})::text as variant, sum(il.${l("quantity")}) as quantity,
      sum(case when ${inclusive} then round((${amount} - ${discount}) * 10000.0 / (10000 + ${rate})) else ${amount} - ${discount} end) as net
    from ${t("lines")} il join ${t("invoices")} b on b.${i("id")} = il.${l("parent")}
    where b.${i("purchaseOrder")} = v_row.${i("purchaseOrder")} and b.${i("direction")} = 'purchase'
      and ${h.kd(`b.${i("kind")}`, ["invoice"])} and (b.${i("id")} = v_row.${i("id")} or ${h.st(`b.${i("status")}`, ["issued", "partially_paid", "paid"])})
      and ${product} is not null
    group by 1, 2
  ),
  ordered as (
    select y.${pl("variant")}::text as variant, sum(y.${pl("quantity")}) as ordered, sum(y.${pl("received")}) as received,
      sum(y.${pl("quantity")} * y.${pl("unitCost")}) / nullif(sum(y.${pl("quantity")}), 0) as unit_cost
    from ${inventory.table("purchaseOrderLines")} y where y.${pl("order")} = v_row.${i("purchaseOrder")}
    group by 1
  ),
  checked as (
    select x.variant, x.quantity, x.net, coalesce(o.ordered, 0) as ordered, coalesce(o.received, 0) as received,
      round(x.quantity * coalesce(o.unit_cost, 0)) as expected,
      (select coalesce(sum(e.quantity), 0) from billed e where e.variant = x.variant) as billed_total
    from billed x left join ordered o on o.variant = x.variant
    where x.bill = v_row.${i("id")}
  ),
  rated as (
    select c.*, case
      when c.received <= 0 then 'not_received'
      when c.billed_total > c.received then 'quantity_variance'
      when abs(c.net - c.expected) > greatest(round(c.expected * ${bps} / 10000.0), ${slack}) then 'price_variance'
      else 'matched' end as status
    from checked c
  )
  select jsonb_build_object('invoiceId', v_row.${i("id")}, 'currency', v_row.${i("currency")}, 'purchaseOrderId', v_row.${i("purchaseOrder")},
    'status', coalesce((select r.status from rated r order by array_position(array['not_received', 'quantity_variance', 'price_variance', 'matched'], r.status) limit 1), 'matched'),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('variantId', r.variant, 'quantity', r.quantity::text, 'billedQuantity', r.billed_total::text,
      'orderedQuantity', r.ordered::text, 'receivedQuantity', r.received::text, 'amount', r.net::bigint::text, 'expectedAmount', r.expected::bigint::text, 'status', r.status) order by r.variant) from rated r), '[]'::jsonb))
  into v_result;`;
        })()
      : `  v_result := jsonb_build_object('invoiceId', v_row.${i("id")}, 'currency', v_row.${i("currency")}, 'purchaseOrderId', null, 'status', 'matched', 'lines', '[]'::jsonb);`;

  return `
-- The three-way match of a purchase bill: each product line against its
-- purchase order line (by variant) and what was received. A variant billed
-- beyond what arrived, across the order's bills, is a quantity variance; a
-- line whose amount differs from the order's unit cost by more than
-- options.matchTolerance (${bps} basis points or ${slack} minor units, whichever
-- is larger) is a price variance; nothing received is not_received. The
-- worst line decides. A bill without a purchase order is not_applicable.
create or replace function ${fn("invoice_match_result")}(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_result jsonb;
begin
  select * into v_row from ${t("invoices")} x where x.${i("id")} = invoice_match_result.invoice;
  if ${order} is null then
    return jsonb_build_object('invoiceId', v_row.${i("id")}, 'currency', v_row.${i("currency")}, 'purchaseOrderId', null, 'status', 'not_applicable', 'lines', '[]'::jsonb);
  end if;
${body}
  return v_result;
end;
$$;
revoke all on function ${fn("invoice_match_result")}(uuid) from public, anon, authenticated;

-- Runs the three-way match of a purchase bill the caller can read and
-- records invoice.match_checked with its result.
create or replace function ${fn("purchase_bill_match")}(invoice uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("invoices")};
  v_result jsonb;
begin
  select * into v_row from ${t("invoices")} x
  where x.${i("id")} = purchase_bill_match.invoice and (${n.service} or ${ctx.scope.can(`x.${i("tenant")}`, n.read)});
  if v_row.${i("id")} is null then
    ${fail("INVOICE_NOT_FOUND", "no such invoice you can read", "P0002")}
  end if;
  if v_row.${i("direction")} <> 'purchase' or (${h.kd(`v_row.${i("kind")}`, ["invoice"])}) is not true then
    ${fail("INVOICE_NOT_PURCHASE_BILL", "only a purchase bill is matched", "22023")}
  end if;
  v_result := ${fn("invoice_match_result")}(v_row.${i("id")});
  ${h.record("invoice.match_checked", "v_row", `, 'purchaseOrderId', ${order}, 'status', v_result ->> 'status'`)}
  return v_result;
end;
$$;
${userGrant(`${fn("purchase_bill_match")}(uuid)`)}
`;
}
