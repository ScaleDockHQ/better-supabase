import "server-only";
import { tenantOf } from "better-supabase/next";

import { getProducts } from "@/features/shop/shop-queries";
import { bsb } from "@/lib/supabase/server";

import type { BoardStatus } from "./production-order-statuses";

import { isBoardStatus } from "./production-order-statuses";

/** A production order as a board card shows it, serializable. */
export interface ProductionOrderCard {
  readonly id: string;
  readonly number: string;
  readonly product: string | null;
  readonly quantity: number;
  readonly producedQuantity: number;
  readonly status: BoardStatus;
  readonly dueOn: string | null;
}

async function loadBoard(): Promise<readonly ProductionOrderCard[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const [orders, products] = await Promise.all([
    db.manufacturing.listOrders({ limit: 200 }).orThrow(),
    getProducts(),
  ]);

  const titles = new Map(
    products.kind === "ok"
      ? products.data.map((product) => [product.variantId, product.title])
      : [],
  );

  return orders.flatMap((order): ProductionOrderCard[] =>
    isBoardStatus(order.status)
      ? [
          {
            id: order.id,
            number: order.number,
            product: titles.get(order.variantId) ?? null,
            quantity: order.quantity,
            producedQuantity: order.producedQuantity,
            status: order.status,
            dueOn: order.dueOn?.toString() ?? null,
          },
        ]
      : [],
  );
}

/** The organization's open and done production orders, by due date. */
export function getProductionOrderBoard(): Promise<
  readonly ProductionOrderCard[] | null
> {
  return loadBoard();
}
