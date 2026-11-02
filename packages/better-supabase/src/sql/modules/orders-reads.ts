import type { ReadType } from "../../core/read-type.ts";
import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlRead } from "../reads.ts";
import type { OrdersNames } from "./orders-shared.ts";

import { declareRead } from "../reads.ts";
import { userGrant } from "../shared.ts";
import { columns } from "./orders-shared.ts";

/** What `order_status_board` returns. */
export const ORDER_STATUS_BOARD_RESULT: ReadType = {
  columns: [
    {
      status: "text",
      count: "number",
      totals: [{ currency: "text", total: "text", paid: "text" }],
      orders: [
        {
          id: "text",
          number: "text",
          customerId: "text?",
          currency: "text",
          total: "text",
          paidTotal: "text",
          placedAt: "text",
        },
      ],
    },
  ],
};

export interface OrderStatusTotal {
  readonly currency: string;
  readonly total: string;
  readonly paid: string;
}

export interface OrderStatusCard {
  readonly id: string;
  readonly number: string;
  readonly customerId: string | null;
  readonly currency: string;
  readonly total: string;
  readonly paidTotal: string;
  readonly placedAt: string;
}

export interface OrderStatusColumn {
  readonly status: string;
  readonly count: number;
  readonly totals: readonly OrderStatusTotal[];
  readonly orders: readonly OrderStatusCard[];
}

/**
 * What `orders.board` returns. Keep it in step with
 * `ORDER_STATUS_BOARD_RESULT`.
 */
export interface OrderStatusBoard {
  readonly columns: readonly OrderStatusColumn[];
}

export const ORDER_READS: readonly BlockSqlRead[] = [
  declareRead(
    "board",
    "order_status_board",
    {
      organizationId: { param: "tenant", type: "id" },
      perStatus: { param: "per_status", type: "int", optional: true },
    },
    ORDER_STATUS_BOARD_RESULT,
    "An organization's orders by status: the count, the totals per currency and the latest orders of each status.",
    ["orders"],
  ),
];

/**
 * `order_status_board`: one column per status in lifecycle order. It runs as
 * the caller, so row security decides which orders the caller sees.
 */
export function orderReads(ctx: BlockSqlContext, names: OrdersNames): string {
  const o = columns(ctx, "orders");
  const fn = names.fn("order_status_board");

  return `
-- The orders page in one call: a column per status with its count, its totals
-- per currency and its latest orders. Amounts are text.
create or replace function ${fn}(tenant ${ctx.idType}, per_status integer default 20)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('columns', coalesce(jsonb_agg(col order by rank, col ->> 'status'), '[]'::jsonb))
  from (
    select
      array_position(array['pending_payment', 'confirmed', 'paid', 'fulfilled', 'completed', 'cancelled', 'refunded'], g.raw::text) as rank,
      jsonb_build_object(
        'status', g.label,
        'count', g.n,
        'totals', g.totals,
        'orders', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', x.${o("id")}, 'number', x.${o("number")}, 'customerId', x.${o("customer")},
            'currency', x.${o("currency")}, 'total', x.${o("total")}::text,
            'paidTotal', x.${o("paidTotal")}::text, 'placedAt', x.${o("placedAt")}) order by x.${o("placedAt")} desc, x.${o("id")})
          from (
            select * from ${ctx.table("orders")} y
            where y.${o("tenant")} = order_status_board.tenant and y.${o("status")} = g.raw
            order by y.${o("placedAt")} desc, y.${o("id")}
            limit greatest(coalesce(order_status_board.per_status, 20), 0)
          ) x), '[]'::jsonb)
      ) as col
    from (
      select s.raw, s.label, sum(s.n)::integer as n,
        jsonb_agg(jsonb_build_object('currency', s.currency, 'total', s.total::text, 'paid', s.paid::text) order by s.currency) as totals
      from (
        select z.${o("status")} as raw, ${ctx.label("orders", "status", `z.${o("status")}`)} as label,
          z.${o("currency")} as currency, count(*) as n,
          sum(z.${o("total")}) as total, sum(z.${o("paidTotal")}) as paid
        from ${ctx.table("orders")} z
        where z.${o("tenant")} = order_status_board.tenant
        group by z.${o("status")}, z.${o("currency")}
      ) s
      group by s.raw, s.label
    ) g
  ) cols
$$;
${userGrant(`${fn}(${ctx.idType}, integer)`)}
`;
}
