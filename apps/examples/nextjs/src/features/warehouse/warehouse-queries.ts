import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { postgres, userClaims } from "@/features/developer/postgres";
import { MANUFACTURING_TAG } from "@/features/manufacturing/manufacturing-cache";
import { SHOP_TAG } from "@/features/shop/shop-cache";
import { bsb } from "@/lib/supabase/server";

import { WAREHOUSE_TAG } from "./warehouse-cache";

export interface LocationOption {
  readonly id: string;
  readonly code: string;
  readonly name: string;
}

export interface VariantOption {
  readonly id: string;
  readonly sku: string;
  readonly title: string;
}

export interface BinOption {
  readonly id: string;
  readonly code: string;
  readonly locationId: string;
}

interface Lookups {
  readonly locations: readonly LocationOption[];
  readonly variants: readonly VariantOption[];
  readonly bins: readonly BinOption[];
}

/**
 * The active locations, the variants and the bins of the organization, for the
 * names and selects of the warehouse and request pages. The inventory block has
 * no list calls for them, so the read goes through the caller's connection and
 * row level security decides the rows (EX-1102).
 */
export async function loadLookups(): Promise<Lookups | null> {
  "use cache: private";
  const { session } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG);
  const tenant = tenantOf(session);
  const connection = postgres();
  const claims = userClaims(session);

  if (!tenant || !connection || !claims) {
    return null;
  }

  const sql = connection.asUser(claims);

  const [locations, variants, bins] = await Promise.all([
    sql.queryRaw<LocationOption>(
      `select id, code, name from better_supabase.inventory_locations
       where tenant_id = $1 and active order by code limit 200`,
      [tenant],
    ),
    sql.queryRaw<VariantOption>(
      `select id, sku, title from better_supabase.product_variants
       where tenant_id = $1 order by sku limit 200`,
      [tenant],
    ),
    sql.queryRaw<{ id: string; code: string; location_id: string }>(
      `select id, code, location_id from better_supabase.stock_bins
       where tenant_id = $1 and active order by code limit 200`,
      [tenant],
    ),
  ]);

  return {
    locations,
    variants,
    bins: bins.map((bin) => ({
      id: bin.id,
      code: bin.code,
      locationId: bin.location_id,
    })),
  };
}

/** A pick list as the overview shows it, serializable. */
export interface PickListRow {
  readonly id: string;
  readonly documentType: string;
  readonly documentId: string;
  readonly status: "open" | "picked" | "cancelled";
  readonly locationId: string;
  readonly waveId: string | null;
  readonly picked: number;
  readonly lines: number;
  readonly createdAt: string;
}

/**
 * The newest 200 pick lists. `listPickLists` filters by status, wave and
 * document but has no text search, so the overview searches the document id on
 * the server (EX-1103).
 */
export async function loadPickLists(): Promise<readonly PickListRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG, MANUFACTURING_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const rows = await db.warehouse.listPickLists({ limit: 200 }).orThrow();

  return rows.map((row) => ({
    id: row.id,
    documentType: row.documentType,
    documentId: row.documentId,
    status: row.status,
    locationId: row.locationId,
    waveId: row.waveId ?? null,
    picked: row.lines.filter((line) => line.status === "picked").length,
    lines: row.lines.length,
    createdAt: row.createdAt.toString(),
  }));
}

export interface PickLineRow {
  readonly id: string;
  readonly variantId: string;
  readonly binId: string | null;
  readonly route: number | null;
  readonly quantity: string;
  readonly picked: string;
  readonly status: "open" | "picked" | "short" | "cancelled";
}

export interface PickListFull extends PickListRow {
  readonly pickedAt: string | null;
  readonly assigneeId: string | null;
  readonly items: readonly PickLineRow[];
}

/** One pick list with its lines, in the walking order of its route. */
export async function loadPickList(
  id: string,
): Promise<PickListFull | null | undefined> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG, MANUFACTURING_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const found = await db.warehouse.getPickList(id);

  if (!found.ok) {
    if (found.error.kind === "not_found") {
      return undefined;
    }

    throw new Error(found.error.message);
  }

  const list = found.data;

  return {
    id: list.id,
    documentType: list.documentType,
    documentId: list.documentId,
    status: list.status,
    locationId: list.locationId,
    waveId: list.waveId ?? null,
    picked: list.lines.filter((line) => line.status === "picked").length,
    lines: list.lines.length,
    createdAt: list.createdAt.toString(),
    pickedAt: list.pickedAt?.toString() ?? null,
    assigneeId: list.assigneeId ?? null,
    items: list.lines
      .toSorted(
        (a, b) =>
          (a.routePosition ?? Number.MAX_SAFE_INTEGER) -
          (b.routePosition ?? Number.MAX_SAFE_INTEGER),
      )
      .map((line) => ({
        id: line.id,
        variantId: line.variantId,
        binId: line.binId ?? null,
        route: line.routePosition ?? null,
        quantity: line.quantity,
        picked: line.picked,
        status: line.status,
      })),
  };
}

export interface WaveRow {
  readonly id: string;
  readonly name: string;
  readonly locationId: string;
  readonly status: "draft" | "released" | "completed" | "cancelled";
  readonly lists: number;
  readonly openLists: number;
  readonly createdAt: string;
}

export async function loadWaves(): Promise<readonly WaveRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const waves = await db.warehouse.listPickWaves().orThrow();

  return waves.map((wave) => ({
    id: wave.id,
    name: wave.name,
    locationId: wave.locationId,
    status: wave.status,
    lists: wave.lists ?? 0,
    openLists: wave.openLists ?? 0,
    createdAt: wave.createdAt.toString(),
  }));
}

export interface PutawayRuleRow {
  readonly id: string;
  readonly locationId: string;
  readonly binId: string;
  readonly variantId: string | null;
  readonly priority: number;
  readonly maxQuantity: string | null;
  readonly active: boolean;
}

export async function loadPutawayRules(): Promise<
  readonly PutawayRuleRow[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const rules = await db.warehouse.listPutawayRules().orThrow();

  return rules.map((rule) => ({
    id: rule.id,
    locationId: rule.locationId,
    binId: rule.binId,
    variantId: rule.variantId ?? null,
    priority: rule.priority,
    maxQuantity: rule.maxQuantity ?? null,
    active: rule.active,
  }));
}

export interface SlottingRow {
  readonly variantId: string;
  readonly picks: number;
  readonly velocity: string;
  readonly onHand: string;
  readonly action: "keep" | "move";
  readonly currentBinId: string | null;
  readonly suggestedBinId: string | null;
}

/** The fastest movers of one location and the bin that suits each. */
export async function loadSlotting(
  locationId: string,
): Promise<readonly SlottingRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const rows = await db.warehouse
    .suggestSlotting({ locationId, limit: 10 })
    .orThrow();

  return rows.map((row) => ({
    variantId: row.variantId,
    picks: row.picks,
    velocity: row.velocity,
    onHand: row.onHand,
    action: row.action,
    currentBinId: row.currentBinId ?? null,
    suggestedBinId: row.suggestedBinId ?? null,
  }));
}

export interface CountPlanRow {
  readonly id: string;
  readonly name: string;
  readonly locationId: string;
  readonly everyDays: number;
  readonly varianceLimitPct: string;
  readonly nextRunOn: string;
  readonly lastRunAt: string | null;
  readonly lastCountId: string | null;
  readonly active: boolean;
  readonly due: boolean;
}

export async function loadCountPlans(): Promise<
  readonly CountPlanRow[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const plans = await db.warehouse.listCountPlans().orThrow();
  const today = new Date().toISOString().slice(0, 10);

  return plans.map((plan) => ({
    id: plan.id,
    name: plan.name,
    locationId: plan.locationId,
    everyDays: plan.everyDays,
    varianceLimitPct: plan.varianceLimitPct,
    nextRunOn: plan.nextRunOn,
    lastRunAt: plan.lastRunAt?.toString() ?? null,
    lastCountId: plan.lastCountId ?? null,
    active: plan.active,
    due: plan.active && plan.nextRunOn <= today,
  }));
}

export interface VarianceLine {
  readonly lineId: string;
  readonly variantId: string;
  readonly expected: string;
  readonly counted: string;
  readonly variance: string;
  readonly variancePct: string;
}

export interface CountVariance {
  readonly countId: string;
  readonly limitPct: string;
  readonly maxVariancePct: string;
  readonly overLimit: boolean;
  readonly lines: readonly VarianceLine[];
}

/** The variance of a plan's last count against its limit. */
export async function loadVariance(
  countId: string,
): Promise<CountVariance | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG);

  if (!tenantOf(session)) {
    return null;
  }

  const variance = await db.warehouse.cycleCountVariance(countId).orThrow();

  return {
    countId: variance.countId,
    limitPct: variance.limitPct,
    maxVariancePct: variance.maxVariancePct,
    overLimit: variance.overLimit,
    lines: variance.lines.map((line) => ({ ...line })),
  };
}

export interface ReceivableOrder {
  readonly id: string;
  readonly number: string;
}

/** Placed purchase orders that still owe units, for the receive dialog. */
export async function loadReceivableOrders(): Promise<
  readonly ReceivableOrder[] | null
> {
  "use cache: private";
  const { session } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG);
  const tenant = tenantOf(session);
  const connection = postgres();
  const claims = userClaims(session);

  if (!tenant || !connection || !claims) {
    return null;
  }

  const rows = await connection
    .asUser(claims)
    .queryRaw<{ id: string; number: string | null }>(
      `select id, number from better_supabase.purchase_orders
     where tenant_id = $1 and status in ('ordered', 'partially_received')
     order by created_at desc limit 50`,
      [tenant],
    );

  return rows.map((row) => ({
    id: row.id,
    number: row.number ?? row.id.slice(0, 8),
  }));
}

/** The units a purchase order still owes, one receipt line per order line. */
export async function openOrderLines(
  purchaseOrderId: string,
): Promise<readonly { lineId: string; quantity: number }[]> {
  const { session } = await bsb.cached();
  const connection = postgres();
  const claims = userClaims(session);

  if (!connection || !claims) {
    return [];
  }

  const rows = await connection
    .asUser(claims)
    .queryRaw<{ id: string; open: string }>(
      `select id, (quantity_ordered - quantity_received - quantity_canceled)::text as open
     from better_supabase.purchase_order_lines where purchase_order_id = $1`,
      [purchaseOrderId],
    );

  return rows
    .map((row) => ({ lineId: row.id, quantity: Number(row.open) }))
    .filter((line) => line.quantity > 0);
}

export interface ReceiptRow {
  readonly id: string;
  readonly order: string;
  readonly locationId: string;
  readonly receivedAt: string;
}

export interface ReceiptPutaway {
  readonly receipt: ReceiptRow;
  readonly suggestions: readonly {
    readonly variantId: string;
    readonly quantity: string;
    readonly unassigned: string;
    readonly bins: string;
  }[];
}

/**
 * The newest goods receipts, and the putaway suggestion of the latest one. The
 * inventory block has no list call for receipts, so the read goes through the
 * caller's connection (EX-1111).
 */
export async function loadReceipts(): Promise<{
  readonly receipts: readonly ReceiptRow[];
  readonly latest: ReceiptPutaway | null;
} | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(WAREHOUSE_TAG, SHOP_TAG);
  const tenant = tenantOf(session);
  const connection = postgres();
  const claims = userClaims(session);

  if (!tenant || !connection || !claims) {
    return null;
  }

  const rows = await connection
    .asUser(claims)
    .queryRaw<{
      id: string;
      number: string | null;
      location_id: string;
      received_at: Date | string;
    }>(
      `select r.id, o.number, r.location_id, r.received_at
     from better_supabase.inventory_receipts r
     join better_supabase.purchase_orders o on o.id = r.purchase_order_id
     where r.tenant_id = $1 order by r.received_at desc limit 20`,
      [tenant],
    );

  const receipts = rows.map((row) => ({
    id: row.id,
    order: row.number ?? "–",
    locationId: row.location_id,
    receivedAt: new Date(row.received_at).toISOString(),
  }));

  const first = receipts[0];

  if (!first) {
    return { receipts, latest: null };
  }

  const suggested = await db.warehouse
    .suggestReceiptPutaway(first.id)
    .orThrow();

  return {
    receipts,
    latest: {
      receipt: first,
      suggestions: suggested.map((row) => ({
        variantId: row.variantId,
        quantity: row.quantity,
        unassigned: row.unassigned,
        bins: row.placements
          .map((placement) => `${placement.binCode} (${placement.quantity})`)
          .join(", "),
      })),
    },
  };
}
