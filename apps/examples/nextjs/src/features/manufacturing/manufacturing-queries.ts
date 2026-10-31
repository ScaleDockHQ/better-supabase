import "server-only";
import type { RequirementAction } from "better-supabase/blocks/manufacturing";

import { tenantOf } from "better-supabase/next";

import type { Loaded } from "@/features/shop/shop-queries";

import { getProducts, settle } from "@/features/shop/shop-queries";
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

/** A shortage material requirements found, serializable. */
export interface RequirementRow {
  readonly variantId: string;
  readonly product: string | null;
  readonly action: RequirementAction;
  readonly quantity: number;
  readonly available: number;
  readonly incoming: number;
  readonly planned: number;
  readonly demand: number;
}

async function loadRequirements(): Promise<readonly RequirementRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const [requirements, products] = await Promise.all([
    db.manufacturing.requirements().orThrow(),
    getProducts(),
  ]);

  const titles = new Map(
    products.kind === "ok"
      ? products.data.map((product) => [product.variantId, product.title])
      : [],
  );

  return requirements.items.map((item) => ({
    variantId: item.variantId,
    product: titles.get(item.variantId) ?? null,
    action: item.action,
    quantity: item.quantity,
    available: item.available,
    incoming: item.incoming,
    planned: item.planned,
    demand: item.demand,
  }));
}

/** What to produce or buy over the next 30 days to reach each reorder point. */
export function getMaterialRequirements(): Promise<
  Loaded<readonly RequirementRow[]>
> {
  return settle(loadRequirements);
}

/** The organization's open and done production orders, by due date. */
export function getProductionOrderBoard(): Promise<
  readonly ProductionOrderCard[] | null
> {
  return loadBoard();
}
