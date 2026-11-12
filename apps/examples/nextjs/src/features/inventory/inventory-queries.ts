import "server-only";
import type { StockBucket } from "better-supabase/blocks/inventory";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { BILLING_TAG } from "@/features/billing/billing-cache";
import { MANUFACTURING_TAG } from "@/features/manufacturing/manufacturing-cache";
import { SHOP_TAG } from "@/features/shop/shop-cache";
import { settle } from "@/features/shop/shop-queries";
import { bsb } from "@/lib/supabase/server";

import type { LotRow, MovementRow, StockRow } from "./inventory-list";

import { INVENTORY_TAG } from "./inventory-cache";
import { stockStatus } from "./inventory-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

const Id = v.pipe(v.string(), v.uuid());

/** The shop's read of every tracked variant at every active location. */
const StockLevels = v.object({
  locations: v.array(
    v.object({
      id: Id,
      code: v.string(),
      name: v.string(),
      active: v.boolean(),
    }),
  ),
  levels: v.array(
    v.object({
      variantId: Id,
      productTitle: v.string(),
      sku: v.string(),
      locationId: Id,
      onHand: v.number(),
      reserved: v.number(),
      available: v.number(),
      reorderPoint: v.nullable(v.number()),
    }),
  ),
});

export interface InventoryLocation {
  readonly id: string;
  readonly code: string;
  readonly name: string;
}

export interface StockData {
  readonly locations: readonly InventoryLocation[];
  readonly rows: readonly StockRow[];
}

/**
 * Every tracked variant at every active location with its incoming units. The
 * block's `levels` read has no titles, so the shop's SQL read supplies them;
 * the list kit searches, filters and sorts the rows on the server.
 */
export async function readStockRows(
  db: Db,
  organizationId: string,
): Promise<StockData> {
  const [stock, incoming] = await Promise.all([
    db
      .$api(
        "shop_stock_levels",
        { tenant: organizationId },
        { returns: StockLevels },
      )
      .orThrow(),
    db.inventory.levels({ organizationId }),
  ]);

  const incomingBy = new Map(
    incoming.ok
      ? incoming.data.map((level) => [
          `${level.variantId}:${level.locationId}`,
          Number(level.incoming),
        ])
      : [],
  );

  const locationName = new Map(
    stock.locations.map((location) => [location.id, location.name]),
  );

  return {
    locations: stock.locations
      .filter((location) => location.active)
      .map(({ id, code, name }) => ({ id, code, name })),
    rows: stock.levels.map((level): StockRow => {
      const id = `${level.variantId}:${level.locationId}`;

      return {
        id,
        variantId: level.variantId,
        productTitle: level.productTitle,
        sku: level.sku,
        locationId: level.locationId,
        locationName: locationName.get(level.locationId) ?? "",
        onHand: level.onHand,
        reserved: level.reserved,
        available: level.available,
        incoming: incomingBy.get(id) ?? 0,
        reorderPoint: level.reorderPoint,
        status: stockStatus(level.available, level.reorderPoint),
      };
    }),
  };
}

const MOVEMENT_LIMIT = 200;

/** The newest ledger movements, named by product and location. */
export async function readMovementRows(
  db: Db,
  organizationId: string,
  filter: { readonly variantId?: string } = {},
): Promise<{
  readonly locations: readonly InventoryLocation[];
  readonly rows: readonly MovementRow[];
}> {
  const [stock, movements] = await Promise.all([
    readStockRows(db, organizationId),
    db.inventory.movements({
      organizationId,
      variantId: filter.variantId,
      limit: MOVEMENT_LIMIT,
    }),
  ]);

  if (!movements.ok) {
    throw new Error("The stock movements did not load");
  }

  const product = new Map(
    stock.rows.map((row) => [row.variantId, row] as const),
  );

  const location = new Map(stock.locations.map((row) => [row.id, row.name]));

  return {
    locations: stock.locations,
    rows: movements.data.map((movement): MovementRow => {
      const named =
        movement.variantId === null
          ? undefined
          : product.get(movement.variantId);

      return {
        id: movement.id,
        kind: movement.kind,
        variantId: movement.variantId,
        productTitle: named?.productTitle ?? "–",
        sku: named?.sku ?? "",
        locationId: movement.locationId,
        locationName:
          (movement.locationId ? location.get(movement.locationId) : null) ??
          "–",
        quantity: Number(movement.quantity ?? 0),
        documentType: movement.documentType,
        effectiveAt: movement.effectiveAt,
      };
    }),
  };
}

/** Lots with stock that carry an expiry date, soonest first. */
export async function readLotRows(
  db: Db,
  organizationId: string,
): Promise<{
  readonly locations: readonly InventoryLocation[];
  readonly rows: readonly LotRow[];
}> {
  const today = Temporal.Now.plainDateISO();
  const horizon = today.add({ years: 10 }).toString();

  const [stock, lots] = await Promise.all([
    readStockRows(db, organizationId),
    db.inventory.expiringLots({ organizationId, before: horizon }),
  ]);

  if (!lots.ok) {
    throw new Error("The lots did not load");
  }

  const product = new Map(
    stock.rows.map((row) => [row.variantId, row] as const),
  );

  const location = new Map(stock.locations.map((row) => [row.id, row.name]));

  return {
    locations: stock.locations,
    rows: lots.data.map((lot): LotRow => {
      const named = product.get(lot.variantId);

      const daysLeft = today.until(Temporal.PlainDate.from(lot.expiresOn), {
        largestUnit: "days",
      }).days;

      return {
        id: `${lot.lotId}:${lot.locationId}:${lot.binId ?? ""}`,
        code: lot.code,
        variantId: lot.variantId,
        productTitle: named?.productTitle ?? "–",
        sku: named?.sku ?? "",
        locationId: lot.locationId,
        locationName: location.get(lot.locationId) ?? "–",
        expiresOn: lot.expiresOn,
        onHand: lot.onHand,
        daysLeft,
        expiry: daysLeft < 0 ? "expired" : daysLeft <= 30 ? "soon" : "later",
      };
    }),
  };
}

export interface StockOverviewData extends StockData {
  /** All levels at or below their reorder point. */
  readonly lowCount: number;
  readonly outCount: number;
  readonly expiringCount: number;
  readonly onHandTotal: number;
}

async function loadStock(): Promise<StockOverviewData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(INVENTORY_TAG, SHOP_TAG, MANUFACTURING_TAG, BILLING_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [data, overview] = await Promise.all([
    readStockRows(db, organizationId),
    db.inventory.overview({ organizationId, limit: 1, expiryDays: 30 }),
  ]);

  return {
    ...data,
    lowCount: overview.ok ? overview.data.lowStockCount : 0,
    outCount: data.rows.filter((row) => row.status === "out").length,
    expiringCount: overview.ok ? overview.data.expiring.length : 0,
    onHandTotal: data.rows.reduce((sum, row) => sum + row.onHand, 0),
  };
}

export function getStock() {
  return settle(loadStock);
}

async function loadMovements() {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(INVENTORY_TAG, SHOP_TAG, MANUFACTURING_TAG, BILLING_TAG);
  const organizationId = tenantOf(session);

  return organizationId ? readMovementRows(db, organizationId) : null;
}

export function getMovements() {
  return settle(loadMovements);
}

async function loadLots() {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(INVENTORY_TAG, SHOP_TAG, MANUFACTURING_TAG, BILLING_TAG);
  const organizationId = tenantOf(session);

  return organizationId ? readLotRows(db, organizationId) : null;
}

export function getLots() {
  return settle(loadLots);
}

export interface StockLocationDetail {
  readonly row: StockRow;
  readonly held: number;
  readonly buckets: readonly StockBucket[];
}

export type StockItemData =
  | { readonly found: false }
  | {
      readonly found: true;
      readonly productTitle: string;
      readonly sku: string;
      readonly locations: readonly StockLocationDetail[];
      readonly movements: readonly MovementRow[];
    };

async function loadStockItem(variantId: string): Promise<StockItemData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(INVENTORY_TAG, SHOP_TAG, MANUFACTURING_TAG, BILLING_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [stock, movements] = await Promise.all([
    readStockRows(db, organizationId),
    readMovementRows(db, organizationId, { variantId }),
  ]);

  const rows = stock.rows.filter((row) => row.variantId === variantId);
  const first = rows[0];

  if (first === undefined) {
    return { found: false };
  }

  const details = await Promise.all(
    rows.map(async (row): Promise<StockLocationDetail> => {
      const detail = await db.inventory.stockDetail({
        variantId,
        locationId: row.locationId,
      });

      return {
        row,
        held: detail.ok ? detail.data.held : 0,
        buckets: detail.ok ? detail.data.buckets : [],
      };
    }),
  );

  return {
    found: true,
    productTitle: first.productTitle,
    sku: first.sku,
    locations: details,
    movements: movements.rows,
  };
}

export function getStockItem(variantId: string) {
  return settle(() => loadStockItem(variantId));
}
