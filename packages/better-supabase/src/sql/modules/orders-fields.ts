import type { BlockSqlContext, ExtraColumn } from "../context.ts";
import type { ListSortKey } from "../list-template.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  filterAny,
  filterFirst,
  filterSet,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { columns } from "./orders-shared.ts";

/** The most decimals `options.quantityScale` allows. */
const MAX_QUANTITY_SCALE = 6;

/** How staff orders are invoiced: when the order is placed, or as it ships. */
export const INVOICING_POLICIES = ["on_order", "on_delivery"] as const;

/** What an order line is. */
export const LINE_TYPES = ["item", "service", "fee"] as const;

/**
 * The keys `order_json` returns for a line; an extra line column can't shadow
 * them.
 */
const LINE_KEYS = [
  "id",
  "variantId",
  "productId",
  "sku",
  "title",
  "quantity",
  "unitAmount",
  "subtotal",
  "discount",
  "tax",
  "total",
  "requiresShipping",
  "locationId",
  "reservationId",
  "fulfilled",
  "returned",
  "backordered",
  "unit",
  "description",
  "lineType",
  "fields",
];

const SLUG = "'^[a-z][a-z0-9_]{0,62}$'";

/** The decimals of an order line quantity (`options.quantityScale`). Default 0. */
export function quantityScale(ctx: BlockSqlContext): number {
  const scale = ctx.number("quantityScale", 0);

  if (!Number.isInteger(scale) || scale < 0 || scale > MAX_QUANTITY_SCALE) {
    throw new TypeError(
      `blocks.orders.options.quantityScale must be a whole number from 0 to ${String(MAX_QUANTITY_SCALE)}`,
    );
  }

  return scale;
}

/** The SQL type of an order line, fulfillment or return quantity. */
export const quantityType = (ctx: BlockSqlContext): string =>
  `numeric(18, ${String(quantityScale(ctx))})`;

/**
 * A SQL condition: `text` is a quantity above zero with at most `quantityScale`
 * decimals. It never casts a text that doesn't match.
 */
export function quantityValid(ctx: BlockSqlContext, text: string): string {
  const scale = quantityScale(ctx);

  const pattern =
    scale === 0
      ? "^[0-9]{1,12}$"
      : `^[0-9]{1,12}(\\.[0-9]{1,${String(scale)}})?$`;

  return `(case when coalesce(${text}, '') ~ '${pattern}' then (${text})::numeric > 0 else false end)`;
}

/** The message of `ORDERS_QUANTITY_INVALID`. */
export function quantityRule(ctx: BlockSqlContext): string {
  const scale = quantityScale(ctx);

  return scale === 0
    ? "each quantity is a whole number above zero"
    : `each quantity is above zero with at most ${String(scale)} decimals`;
}

/** The columns your schema files add to the order lines table. */
export const lineExtrasOf = (ctx: BlockSqlContext): readonly ExtraColumn[] =>
  ctx.extraColumns("orderLines", LINE_KEYS);

/** A column definition when `table` maps `logical`, else nothing. */
function optional(
  ctx: BlockSqlContext,
  table: string,
  logical: string,
  definition: (name: string) => string,
): string {
  return ctx.has(table, logical)
    ? `\n  ${definition(ctx.col(table, logical))},`
    : "";
}

/** The staff order columns of the orders table (ADR 1219). */
export function staffOrderColumns(ctx: BlockSqlContext): string {
  const add = (logical: string, definition: (name: string) => string): string =>
    optional(ctx, "orders", logical, definition);

  return [
    add("channel", (n) => `${n} text check (${n} ~ ${SLUG})`),
    add("source", (n) => `${n} text check (${n} ~ ${SLUG})`),
    add(
      "externalId",
      (n) => `${n} text check (length(${n}) between 1 and 200)`,
    ),
    add(
      "invoicingPolicy",
      (n) =>
        `${n} text not null default 'on_order' check (${n} in (${INVOICING_POLICIES.map((p) => `'${p}'`).join(", ")}))`,
    ),
    add("deliveryMethod", (n) => `${n} text check (${n} ~ ${SLUG})`),
    add("quote", (n) => `${n} uuid`),
    add(
      "orderDiscount",
      (n) => `${n} bigint not null default 0 check (${n} >= 0)`,
    ),
    add("promotion", (n) => `${n} uuid`),
    add("paymentRequired", (n) => `${n} boolean not null default false`),
    add("deposit", (n) => `${n} bigint check (${n} >= 0)`),
    add("partyType", (n) => `${n} text check (${n} ~ ${SLUG})`),
    add("partyId", (n) => `${n} text check (length(${n}) between 1 and 200)`),
  ].join("");
}

/** The indexes and checks over the staff order columns. */
export function staffOrderIndexes(ctx: BlockSqlContext): string {
  const o = columns(ctx, "orders");
  const table = ctx.table("orders");
  const has = (logical: string): boolean => ctx.has("orders", logical);

  const index = (name: string, list: string, where = ""): string =>
    `\ncreate index if not exists ${ctx.naming.rename(name)} on ${table} (${list})${where};`;

  return [
    has("source") && has("externalId")
      ? `\ncreate unique index if not exists ${ctx.naming.rename("orders_external_idx")} on ${table} (${o("tenant")}, ${o("source")}, ${o("externalId")}) where ${o("externalId")} is not null;`
      : "",
    has("source") && has("externalId")
      ? `\nalter table ${table} drop constraint if exists ${sqlIdent(`${ctx.tableName("orders").name}_external_source_check`)};
alter table ${table} add constraint ${sqlIdent(`${ctx.tableName("orders").name}_external_source_check`)} check (${o("externalId")} is null or ${o("source")} is not null);`
      : "",
    has("channel")
      ? index(
          "orders_channel_idx",
          `${o("tenant")}, ${o("channel")}, ${o("placedAt")}`,
        )
      : "",
    has("quote")
      ? index(
          "orders_quote_idx",
          o("quote"),
          ` where ${o("quote")} is not null`,
        )
      : "",
    has("partyType") && has("partyId")
      ? `${index("orders_party_idx", `${o("tenant")}, ${o("partyType")}, ${o("partyId")}`, ` where ${o("partyId")} is not null`)}
alter table ${table} drop constraint if exists ${sqlIdent(`${ctx.tableName("orders").name}_party_pair_check`)};
alter table ${table} add constraint ${sqlIdent(`${ctx.tableName("orders").name}_party_pair_check`)} check ((${o("partyType")} is null) = (${o("partyId")} is null));`
      : "",
  ].join("");
}

/** The unit, description and line type columns of the order lines table. */
export function lineColumns(ctx: BlockSqlContext): string {
  const add = (logical: string, definition: (name: string) => string): string =>
    optional(ctx, "orderLines", logical, definition);

  return [
    add("unit", (n) => `${n} text check (length(${n}) between 1 and 32)`),
    add("description", (n) => `${n} text check (length(${n}) <= 4000)`),
    add(
      "lineType",
      (n) =>
        `${n} text not null default 'item' check (${n} in (${LINE_TYPES.map((t) => `'${t}'`).join(", ")}))`,
    ),
  ].join("");
}

/** `, 'key', alias.column` for each logical column the table maps, else `null`. */
function jsonPairs(
  ctx: BlockSqlContext,
  table: string,
  alias: string,
  pairs: readonly (readonly [string, string, string?])[],
): string {
  return pairs
    .map(([key, logical, cast = ""]) =>
      ctx.has(table, logical)
        ? `, '${key}', ${alias}.${ctx.col(table, logical)}${cast}`
        : `, '${key}', null`,
    )
    .join("");
}

/**
 * The staff order keys over order row `alias`, as their own object: the order
 * object would pass `jsonb_build_object`'s 100 argument limit with them.
 */
export function staffOrderJson(ctx: BlockSqlContext, alias: string): string {
  const o = (logical: string): string =>
    `${alias}.${ctx.col("orders", logical)}`;

  const party =
    ctx.has("orders", "partyType") && ctx.has("orders", "partyId")
      ? `case when ${o("partyId")} is not null then jsonb_build_object('type', ${o("partyType")}, 'id', ${o("partyId")}) end`
      : "null";

  return `jsonb_build_object('party', ${party}${jsonPairs(
    ctx,
    "orders",
    alias,
    [
      ["channel", "channel"],
      ["source", "source"],
      ["externalId", "externalId"],
      ["invoicingPolicy", "invoicingPolicy"],
      ["deliveryMethod", "deliveryMethod"],
      ["quoteId", "quote"],
      ["orderDiscount", "orderDiscount", "::text"],
      ["promotionId", "promotion"],
      ["paymentRequired", "paymentRequired"],
      ["deposit", "deposit", "::text"],
    ],
  )})`;
}

/** The line keys of `order_json` over line row `alias`. */
export const lineJson = (ctx: BlockSqlContext, alias: string): string =>
  jsonPairs(ctx, "orderLines", alias, [
    ["unit", "unit"],
    ["description", "description"],
    ["lineType", "lineType"],
  ]);

/**
 * The staff order columns `order_from_document` writes, read from `p_attrs`:
 * `columns` and `values` are `, a, b` lists for the insert.
 */
export function staffOrderInsert(ctx: BlockSqlContext): {
  readonly columns: string;
  readonly values: string;
} {
  const entries: readonly (readonly [string, string])[] = [
    ["channel", "nullif(p_attrs ->> 'channel', '')"],
    ["source", "nullif(p_attrs ->> 'source', '')"],
    ["externalId", "nullif(p_attrs ->> 'externalId', '')"],
    [
      "invoicingPolicy",
      "coalesce(nullif(p_attrs ->> 'invoicingPolicy', ''), 'on_order')",
    ],
    ["deliveryMethod", "nullif(p_attrs ->> 'deliveryMethod', '')"],
    ["quote", "nullif(p_attrs ->> 'quoteId', '')::uuid"],
    ["orderDiscount", "coalesce((p_attrs ->> 'orderDiscount')::bigint, 0)"],
    ["promotion", "nullif(p_attrs ->> 'promotionId', '')::uuid"],
    [
      "paymentRequired",
      "coalesce((p_attrs ->> 'paymentRequired')::boolean, false)",
    ],
    ["deposit", "nullif(p_attrs ->> 'deposit', '')::bigint"],
    ["partyType", "nullif(p_attrs #>> '{party,type}', '')"],
    ["partyId", "nullif(p_attrs #>> '{party,id}', '')"],
  ];

  const present = entries.filter(([logical]) => ctx.has("orders", logical));

  return {
    columns: present
      .map(([logical]) => `, ${ctx.col("orders", logical)}`)
      .join(""),
    values: present.map(([, value]) => `, ${value}`).join(""),
  };
}

/**
 * PL/pgSQL that refuses staff order attributes the orders table can't store or
 * that break a rule, before anything is written. Reads `v_attrs`.
 */
export function staffOrderChecks(ctx: BlockSqlContext): string {
  const has = (logical: string): boolean => ctx.has("orders", logical);

  const unsupported = (key: string, logical: string): string =>
    has(logical)
      ? ""
      : `
  if nullif(v_attrs ->> '${key}', '') is not null then
    ${fail("ORDERS_FIELD_UNSUPPORTED", `this orders table has no column for attrs.${key}`, "22023")}
  end if;`;

  const amount = (key: string): string =>
    `(v_attrs ? '${key}' and coalesce(v_attrs ->> '${key}', '') !~ '^[0-9]{1,18}$')`;

  return `${[
    ["channel", "channel"],
    ["source", "source"],
    ["externalId", "externalId"],
    ["invoicingPolicy", "invoicingPolicy"],
    ["deliveryMethod", "deliveryMethod"],
    ["quoteId", "quote"],
    ["orderDiscount", "orderDiscount"],
    ["promotionId", "promotion"],
    ["paymentRequired", "paymentRequired"],
    ["deposit", "deposit"],
  ]
    .map(([key, logical]) => unsupported(key ?? "", logical ?? ""))
    .join("")}${
    has("partyType") && has("partyId")
      ? ""
      : `
  if v_attrs -> 'party' is not null then
    ${fail("ORDERS_FIELD_UNSUPPORTED", "this orders table has no party columns", "22023")}
  end if;`
  }
  if ${amount("orderDiscount")} or ${amount("deposit")} then
    ${fail("ORDERS_AMOUNT_INVALID", "amounts are minor units of zero or more", "22023")}
  end if;
  if nullif(v_attrs ->> 'externalId', '') is not null and nullif(v_attrs ->> 'source', '') is null then
    ${fail("ORDERS_SOURCE_REQUIRED", "attrs.externalId needs attrs.source, the system the id comes from", "22023")}
  end if;
  if v_attrs -> 'party' is not null and (nullif(v_attrs #>> '{party,type}', '') is null or nullif(v_attrs #>> '{party,id}', '') is null) then
    ${fail("ORDERS_PARTY_INVALID", "attrs.party is { type, id }", "22023")}
  end if;`;
}

/**
 * PL/pgSQL that returns the tenant's order with the same source and external
 * id, so an order from another system is made once. Reads `p_attrs`.
 */
export function externalOrderReturn(
  ctx: BlockSqlContext,
  names: OrdersNames,
): string {
  if (!ctx.has("orders", "source") || !ctx.has("orders", "externalId")) {
    return "";
  }

  const o = columns(ctx, "orders");

  return `
  if nullif(p_attrs ->> 'externalId', '') is not null then
    select x.${o("id")} into v_id from ${ctx.table("orders")} x
    where x.${o("tenant")} = p_tenant and x.${o("source")} = p_attrs ->> 'source' and x.${o("externalId")} = p_attrs ->> 'externalId';
    if v_id is not null then
      return ${names.fn("order_json")}(v_id) || jsonb_build_object('created', false);
    end if;
  end if;`;
}

/**
 * PL/pgSQL for `create_fulfillment`: an order that needs payment ships once its
 * deposit, or its total without one, is paid.
 */
export function paymentGate(ctx: BlockSqlContext): string {
  if (!ctx.has("orders", "paymentRequired")) {
    return "";
  }

  const o = columns(ctx, "orders");
  const deposit = ctx.has("orders", "deposit") ? `x.${o("deposit")}` : "null";

  return `
  if exists (select 1 from ${ctx.table("orders")} x where x.${o("id")} = v_order.id and x.${o("paymentRequired")}
    and x.${o("paidTotal")} < coalesce(${deposit}, x.${o("total")})) then
    ${fail("ORDERS_PAYMENT_REQUIRED", "the order ships once its deposit, or its total without one, is paid", "55000")}
  end if;`;
}

/**
 * `page_orders(tenant, filters)`: the staff order list as a keyset page (ADR
 * 1077), newest first. It runs as the caller, so the orders policy decides
 * which orders the caller sees.
 */
export function orderPage(ctx: BlockSqlContext, names: OrdersNames): string {
  const o = columns(ctx, "orders");
  const fn = names.fn("page_orders");
  const has = (logical: string): boolean => ctx.has("orders", logical);

  // A filter on a column the table doesn't map matches no row.
  const optionalFilter = (
    key: string,
    logical: string,
    type = "text",
  ): string =>
    has(logical)
      ? filterAny(key, `x.${o(logical)}`, type)
      : `(not ${filterSet(key)})`;

  const id = { expr: `x.${o("id")}`, dir: "desc", type: "uuid" } as const;

  const newest: readonly ListSortKey[] = [
    { expr: `x.${o("placedAt")}`, dir: "desc", type: "timestamptz" },
    id,
  ];

  const searchable = [
    o("number"),
    ...(has("email") ? [o("email")] : []),
    ...(has("externalId") ? [o("externalId")] : []),
  ].map((column) => `x.${column} ilike v_search`);

  const facets: Record<string, string> = {
    status: ctx.label("orders", "status", `x.${o("status")}`),
    currency: `x.${o("currency")}`,
  };

  if (has("channel")) {
    facets["channel"] = `x.${o("channel")}`;
  }

  const spec = {
    name: "page_orders",
    from: ctx.table("orders"),
    alias: "x",
    where: [
      `x.${o("tenant")} = page_orders.tenant`,
      filterAny("status", ctx.label("orders", "status", `x.${o("status")}`)),
      filterAny("customerId", `x.${o("customer")}`, "uuid"),
      optionalFilter("partyId", "partyId"),
      optionalFilter("channel", "channel"),
      optionalFilter("source", "source"),
      filterAny("currency", `x.${o("currency")}`),
      `(${filterFirst("from")} is null or x.${o("placedAt")} >= (${filterFirst("from")})::timestamptz)`,
      `(${filterFirst("to")} is null or x.${o("placedAt")} < (${filterFirst("to")})::timestamptz)`,
      `(v_search is null or ${searchable.join(" or ")})`,
    ],
    keys: newest,
    sorts: {
      placedAt: newest,
      number: [{ expr: `x.${o("sequence")}`, dir: "desc", type: "bigint" }, id],
      total: [{ expr: `x.${o("total")}`, dir: "desc", type: "bigint" }, id],
    },
    facets,
    rowJson: `jsonb_build_object(
      'id', x.${o("id")}, 'number', x.${o("number")}, 'status', ${ctx.label("orders", "status", `x.${o("status")}`)},
      'customerId', x.${o("customer")}, 'currency', x.${o("currency")}, 'total', x.${o("total")}::text,
      'paidTotal', x.${o("paidTotal")}::text, 'placedAt', x.${o("placedAt")}) || ${staffOrderJson(ctx, "x")}`,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("ORDERS_INVALID", message, "22023"),
  } as const;

  return `
-- The organization's orders as a keyset page, newest first (ADR 1077). Row
-- security decides what the caller sees. filters is { status, customerId,
-- partyId, channel, source, currency (each a value or a list), from and to
-- (placed at), search (number, email, external id), sort (placedAt, number,
-- total), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }. Amounts are text.
create or replace function ${fn}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_orders.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(spec)}
begin
  ${listBody(spec)}
end;
$$;
${userGrant(`${fn}(${ctx.idType}, jsonb)`)}
`;
}
