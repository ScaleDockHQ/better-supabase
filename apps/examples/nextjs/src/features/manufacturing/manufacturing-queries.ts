import "server-only";
import type {
  ProductionOrderStatus,
  RequirementAction,
} from "better-supabase/blocks/manufacturing";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import type { Loaded } from "@/features/shop/shop-queries";

import { SHOP_TAG } from "@/features/shop/shop-cache";
import { getProducts, settle } from "@/features/shop/shop-queries";
import { bsb } from "@/lib/supabase/server";

import type { BoardStatus } from "./production-order-statuses";

import { MANUFACTURING_TAG } from "./manufacturing-cache";
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
  cacheTag(MANUFACTURING_TAG, SHOP_TAG);

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
  cacheTag(MANUFACTURING_TAG, SHOP_TAG);

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

/** One production order with its operations and components, serializable. */
export interface ProductionOrderView {
  readonly id: string;
  readonly number: string;
  readonly product: string | null;
  readonly status: ProductionOrderStatus;
  readonly quantity: number;
  readonly producedQuantity: number;
  readonly scrapQuantity: number;
  readonly dueOn: string | null;
  readonly note: string | null;
  readonly releasedAt: string | null;
  readonly completedAt: string | null;
  readonly operations: readonly {
    readonly id: string;
    readonly sequence: number;
    readonly title: string;
    readonly plannedMinutes: number;
    readonly status: string;
  }[];
  readonly components: readonly {
    readonly componentId: string;
    readonly product: string | null;
    readonly quantity: number;
    readonly allocated: number;
    readonly backordered: number;
    readonly consumed: number;
  }[];
}

async function loadProductionOrder(
  id: string,
): Promise<ProductionOrderView | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(MANUFACTURING_TAG, SHOP_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const [order, products] = await Promise.all([
    db.manufacturing.getOrder(id),
    getProducts(),
  ]);

  if (!order.ok) {
    if (order.error.kind === "not_found") {
      return null;
    }

    throw new Error(order.error.message);
  }

  const titles = new Map(
    products.kind === "ok"
      ? products.data.map((product) => [product.variantId, product.title])
      : [],
  );

  const detail = order.data;

  return {
    id: detail.id,
    number: detail.number,
    product: titles.get(detail.variantId) ?? null,
    status: detail.status,
    quantity: detail.quantity,
    producedQuantity: detail.producedQuantity,
    scrapQuantity: detail.scrapQuantity,
    dueOn: detail.dueOn?.toString() ?? null,
    note: detail.note ?? null,
    releasedAt: detail.releasedAt?.toString() ?? null,
    completedAt: detail.completedAt?.toString() ?? null,
    operations: detail.operations.map((operation) => ({
      id: operation.id,
      sequence: operation.sequence,
      title: operation.title,
      plannedMinutes: operation.plannedMinutes,
      status: operation.status,
    })),
    components: detail.components.map((component) => ({
      componentId: component.componentId,
      product: titles.get(component.variantId) ?? null,
      quantity: component.quantity,
      allocated: component.allocated,
      backordered: component.backordered,
      consumed: component.consumed,
    })),
  };
}

export type ProductionOrderDetailResult =
  | { readonly kind: "ok"; readonly data: ProductionOrderView }
  | { readonly kind: "error" }
  | { readonly kind: "not-found" };

/** A production order by id, `not-found` when the caller can't read it. */
export async function getProductionOrder(
  id: string,
): Promise<ProductionOrderDetailResult> {
  if (!v.is(v.pipe(v.string(), v.uuid()), id)) {
    return { kind: "not-found" };
  }

  try {
    const data = await loadProductionOrder(id);

    return data === null ? { kind: "not-found" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
