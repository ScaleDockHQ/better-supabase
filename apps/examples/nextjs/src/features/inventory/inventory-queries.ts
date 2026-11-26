import "server-only";
import type { StockBucket } from "better-supabase/blocks/inventory";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";

import { BILLING_TAG } from "@/features/billing/billing-cache";
import { settle } from "@/features/shop/shop-queries";
import { pageEntityRows } from "@/lib/block-entity-page";
import { getAllPages } from "@/lib/read-all-pages";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

import type { LotRow, MovementRow, StockRow } from "./inventory-list";

import {
  lotList,
  lotMap,
  movementList,
  movementMap,
  stockList,
  stockMap,
  stockStatus,
} from "./inventory-list";

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
async function getStockRows(
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
    getAllPages((page) => db.inventory.levelPage({ organizationId, ...page })),
  ]);

  const incomingBy = new Map(
    incoming.map((level) => [
      `${level.variantId}:${level.locationId}`,
      Number(level.incoming),
    ]),
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

/** What the page methods leave out: the product and location names. */
interface Directory {
  readonly locations: readonly InventoryLocation[];
  readonly product: ReadonlyMap<string, StockRow>;
  readonly location: ReadonlyMap<string, string>;
}

function directoryOf(stock: StockData): Directory {
  return {
    locations: stock.locations,
    product: new Map(stock.rows.map((row) => [row.variantId, row] as const)),
    location: new Map(stock.locations.map((row) => [row.id, row.name])),
  };
}

/**
 * The block lists search ids and codes, not product titles. A search text that
 * matches product titles or SKUs becomes a variant filter, so the database
 * still filters and pages; any other text goes to the block's own search.
 */
function searchOf(
  directory: Directory,
  query: RecordListUrlQuery,
): RecordListUrlQuery {
  const needle = query.q?.trim().toLowerCase() ?? "";

  if (needle === "") {
    return query;
  }

  const variantIds = [
    ...new Set(
      [...directory.product.values()]
        .filter(
          (row) =>
            row.productTitle.toLowerCase().includes(needle) ||
            row.sku.toLowerCase().includes(needle),
        )
        .map((row) => row.variantId),
    ),
  ];

  if (variantIds.length === 0) {
    return query;
  }

  const { q: _q, ...rest } = query;

  return { ...rest, facets: { ...query.facets, variantId: variantIds } };
}

const named = (directory: Directory, variantId: string | null) =>
  variantId === null ? undefined : directory.product.get(variantId);

function movementRowOf(
  directory: Directory,
  movement: {
    readonly id: string;
    readonly kind: string;
    readonly variantId: string | null;
    readonly locationId: string | null;
    readonly quantity: string | null;
    readonly documentType: string | null;
    readonly effectiveAt: string;
  },
): MovementRow {
  const product = named(directory, movement.variantId);

  return {
    id: movement.id,
    kind: movement.kind,
    variantId: movement.variantId,
    productTitle: product?.productTitle ?? "–",
    sku: product?.sku ?? "",
    locationId: movement.locationId,
    locationName:
      (movement.locationId
        ? directory.location.get(movement.locationId)
        : null) ?? "–",
    quantity: Number(movement.quantity ?? 0),
    documentType: movement.documentType,
    effectiveAt: movement.effectiveAt,
  };
}

/** The newest ledger movements of one variant, named by product and location. */
async function getMovementRows(
  db: Db,
  organizationId: string,
  filter: { readonly variantId?: string } = {},
): Promise<{
  readonly locations: readonly InventoryLocation[];
  readonly rows: readonly MovementRow[];
}> {
  const [stock, movements] = await Promise.all([
    getStockRows(db, organizationId),
    db.inventory
      .movementPage({
        organizationId,
        filters: { variantId: filter.variantId ? [filter.variantId] : [] },
        limit: MOVEMENT_LIMIT,
      })
      .orThrow(),
  ]);

  const directory = directoryOf(stock);

  return {
    locations: stock.locations,
    rows: movements.items.map((movement) => movementRowOf(directory, movement)),
  };
}

/**
 * One page of stock levels for a list query, searched, filtered and sorted by
 * the inventory block's `levelPage` and counted by `levelFacets`.
 */
export async function getStockPage(
  db: Db,
  organizationId: string,
  query: RecordListUrlQuery,
  stock?: StockData,
): Promise<RecordListPage<StockRow>> {
  const directory = directoryOf(
    stock ?? (await getStockRows(db, organizationId)),
  );

  return pageEntityRows({
    pager: {
      page: (options) => db.inventory.levelPage({ organizationId, ...options }),
      facets: (options) =>
        db.inventory.levelFacets({ organizationId, ...options }),
    },
    map: stockMap,
    query: searchOf(directory, query),
    pageSize: stockList.config.pageSize,
    rowsOf: (levels) =>
      levels.map((level): StockRow => {
        const product = named(directory, level.variantId);
        const available = Number(level.available);

        const reorderPoint =
          level.reorderPoint === null ? null : Number(level.reorderPoint);

        return {
          id: `${level.variantId}:${level.locationId}`,
          variantId: level.variantId,
          productTitle: product?.productTitle ?? "–",
          sku: product?.sku ?? "",
          locationId: level.locationId,
          locationName: directory.location.get(level.locationId) ?? "",
          onHand: Number(level.onHand),
          reserved: Number(level.allocated),
          available,
          incoming: Number(level.incoming),
          reorderPoint,
          status: stockStatus(available, reorderPoint),
        };
      }),
  });
}

/**
 * One page of ledger movements for a list query, named by product and location,
 * with the locations the list filters by.
 */
export async function getMovementPage(
  db: Db,
  organizationId: string,
  query: RecordListUrlQuery,
): Promise<{
  readonly locations: readonly InventoryLocation[];
  readonly page: RecordListPage<MovementRow>;
}> {
  const directory = directoryOf(await getStockRows(db, organizationId));

  const page = await pageEntityRows({
    pager: {
      page: (options) =>
        db.inventory.movementPage({ organizationId, ...options }),
      facets: (options) =>
        db.inventory.movementFacets({ organizationId, ...options }),
    },
    map: movementMap,
    query: searchOf(directory, query),
    pageSize: movementList.config.pageSize,
    rowsOf: (movements) =>
      movements.map((movement) => movementRowOf(directory, movement)),
  });

  return { locations: directory.locations, page };
}

/**
 * One page of lots with an expiry date for a list query, named by product and
 * location, soonest first.
 */
export async function getLotPage(
  db: Db,
  organizationId: string,
  query: RecordListUrlQuery,
): Promise<{
  readonly locations: readonly InventoryLocation[];
  readonly page: RecordListPage<LotRow>;
}> {
  const directory = directoryOf(await getStockRows(db, organizationId));
  const today = Temporal.Now.plainDateISO();

  const page = await pageEntityRows({
    pager: {
      page: (options) => db.inventory.lotPage({ organizationId, ...options }),
      facets: (options) =>
        db.inventory.lotFacets({ organizationId, ...options }),
    },
    map: lotMap,
    query: searchOf(directory, query),
    pageSize: lotList.config.pageSize,
    rowsOf: (lots) =>
      lots.flatMap((lot): LotRow[] => {
        if (lot.expiresOn === null) {
          return [];
        }

        const product = named(directory, lot.variantId);

        const daysLeft = today.until(Temporal.PlainDate.from(lot.expiresOn), {
          largestUnit: "days",
        }).days;

        return [
          {
            id: lot.id,
            code: lot.code,
            variantId: lot.variantId,
            productTitle: product?.productTitle ?? "–",
            sku: product?.sku ?? "",
            locationId: lot.locationId,
            locationName: directory.location.get(lot.locationId) ?? "–",
            expiresOn: lot.expiresOn,
            onHand: Number(lot.onHand),
            daysLeft,
            expiry:
              daysLeft < 0 ? "expired" : daysLeft <= 30 ? "soon" : "later",
          },
        ];
      }),
  });

  return { locations: directory.locations, page };
}

export interface StockOverviewData extends StockData {
  /** All levels at or below their reorder point. */
  readonly lowCount: number;
  readonly outCount: number;
  readonly expiringCount: number;
  readonly onHandTotal: number;
  /** The first page of the stock list. */
  readonly initial: RecordListPage<StockRow>;
}

async function loadStock(): Promise<StockOverviewData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.inventory(), tags.shop(), tags.manufacturing(), BILLING_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [data, overview] = await Promise.all([
    getStockRows(db, organizationId),
    db.inventory.overview({ organizationId, limit: 1, expiryDays: 30 }),
  ]);

  const initial = await getStockPage(
    db,
    organizationId,
    stockList.defaults,
    data,
  );

  return {
    ...data,
    initial,
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
  cacheTag(tags.inventory(), tags.shop(), tags.manufacturing(), BILLING_TAG);
  const organizationId = tenantOf(session);

  return organizationId
    ? getMovementPage(db, organizationId, movementList.defaults)
    : null;
}

export function getMovements() {
  return settle(loadMovements);
}

async function loadLots() {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.inventory(), tags.shop(), tags.manufacturing(), BILLING_TAG);
  const organizationId = tenantOf(session);

  return organizationId
    ? getLotPage(db, organizationId, lotList.defaults)
    : null;
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
  cacheTag(tags.inventory(), tags.shop(), tags.manufacturing(), BILLING_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [stock, movements] = await Promise.all([
    getStockRows(db, organizationId),
    getMovementRows(db, organizationId, { variantId }),
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
