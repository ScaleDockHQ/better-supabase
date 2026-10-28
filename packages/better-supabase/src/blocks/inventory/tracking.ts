import type { Money } from "../../commerce/money.ts";
import type { StockDetail } from "../../commerce/stock-detail.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import { money } from "../../commerce/money.ts";
import { detailArg } from "../../commerce/stock-detail.ts";
import {
  enumOrThrow,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

export type { StockDetail };

/** How a variant's stock is tracked. */
export const TRACKING_MODES = ["none", "lot", "serial"] as const;

export type TrackingMode = (typeof TRACKING_MODES)[number];

/** How a variant's stock is valued. */
export const COSTING_METHODS = ["none", "average"] as const;

export type CostingMethod = (typeof COSTING_METHODS)[number];

export const ALLOCATION_STATUSES = ["open", "fulfilled", "released"] as const;

export type AllocationStatus = (typeof ALLOCATION_STATUSES)[number];

export interface StockItemInput {
  /** Lowercase, such as `item`, `kg` or `m`. Default `item`. */
  readonly unit?: string;
  /** Decimals a quantity may have, 0 to 6. Default 0. */
  readonly scale?: number;
  /** Default `none`. */
  readonly tracking?: TrackingMode;
  readonly tracksExpiry?: boolean;
  /** Default `none`. */
  readonly costing?: CostingMethod;
  /** The ISO 4217 currency costs are kept in, for `average`. */
  readonly currency?: string;
}

export interface StockItem {
  readonly variantId: string;
  readonly unit: string;
  readonly scale: number;
  readonly tracking: TrackingMode;
  readonly tracksExpiry: boolean;
  readonly costing: CostingMethod;
  readonly currency: string | null;
  /** The weighted average cost per unit, in minor units, with decimals. */
  readonly averageCost: string | null;
}

export interface BinInput {
  /** Updates this bin; creates one when left out. */
  readonly id?: string;
  /** Unique within the location, such as `A-01-3`. */
  readonly code: string;
  readonly name?: string;
  /** Stock in a hold bin isn't available to sell. */
  readonly hold?: boolean;
  readonly active?: boolean;
}

export interface Bin {
  readonly id: string;
  readonly code: string;
  readonly hold: boolean;
  readonly active: boolean;
}

export interface Lot {
  readonly id: string;
  readonly code: string;
  readonly expiresOn: string | null;
}

/** Stock of one bin and lot at a location. */
export interface StockBucket {
  readonly binId: string | null;
  readonly binCode: string | null;
  readonly hold: boolean;
  readonly lotId: string | null;
  readonly lotCode: string | null;
  readonly expiresOn: string | null;
  readonly onHand: number;
}

export interface StockLevelDetail {
  readonly variantId: string;
  readonly locationId: string;
  readonly onHand: number;
  readonly reserved: number;
  /** Stock in hold bins. */
  readonly held: number;
  readonly available: number;
  /** Stock outside any bin or lot. */
  readonly unbinned: number;
  readonly buckets: readonly StockBucket[];
  /** The serial numbers in stock at the location. */
  readonly serials: readonly string[];
}

export interface ExpiringLot {
  readonly lotId: string;
  readonly code: string;
  readonly variantId: string;
  readonly locationId: string;
  readonly binId: string | null;
  readonly expiresOn: string;
  readonly onHand: number;
}

export interface StockValuation {
  readonly variantId: string;
  readonly costing: CostingMethod;
  /** Null without a cost currency. */
  readonly averageCost: string | null;
  readonly onHand: number;
  /** The stock value, null without a cost currency. */
  readonly value: Money | null;
}

export interface AllocationInput {
  readonly variantId: string;
  readonly locationId: string;
  readonly quantity: number;
  /** What the stock is for, such as `order` or `work_order`. */
  readonly documentType: string;
  readonly documentId: string;
  readonly lineId: string;
  /** Keeps what isn't available on backorder. Default true. */
  readonly backorder?: boolean;
}

export interface Allocation {
  readonly id: string;
  readonly variantId: string;
  readonly locationId: string;
  readonly documentType: string;
  readonly documentId: string;
  readonly lineId: string;
  readonly quantity: number;
  /** Held for the document now. */
  readonly allocated: number;
  readonly fulfilled: number;
  /** Waiting for stock; filled by the oldest first as stock arrives. */
  readonly backordered: number;
  readonly status: AllocationStatus;
  readonly createdAt: Temporal.Instant;
  /** The movement `fulfillAllocation` and `restoreAllocation` wrote. */
  readonly movementId?: string;
}

/** Units, bins, lots, serials, costs and document allocations. */
export interface InventoryTracking {
  /** Refused with `INVENTORY_ITEM_LOCKED` once the variant has stock. */
  setStockItem(
    variantId: string,
    input: StockItemInput,
  ): AsyncResult<StockItem>;
  saveBin(locationId: string, input: BinInput): AsyncResult<Bin>;
  saveLot(
    variantId: string,
    code: string,
    expiresOn?: string,
  ): AsyncResult<Lot>;
  stockDetail(
    variantId: string,
    locationId: string,
  ): AsyncResult<StockLevelDetail>;
  /** Lots with stock that expire before `before` (`YYYY-MM-DD`). */
  expiringLots(
    organizationId: string,
    before: string,
  ): AsyncResult<readonly ExpiringLot[]>;
  /**
   * Scraps the stock of lots that expired by `asOf` (default today). Resolves
   * to the number of buckets scrapped.
   */
  expireLots(organizationId: string, asOf?: string): AsyncResult<number>;
  stockValuation(variantId: string): AsyncResult<StockValuation>;
  /** Holds stock for a document line; the rest waits on backorder. */
  allocate(
    organizationId: string,
    input: AllocationInput,
  ): AsyncResult<Allocation>;
  /** Takes allocated stock out as a `sale` movement. */
  fulfillAllocation(
    allocationId: string,
    quantity: number,
    detail?: StockDetail,
  ): AsyncResult<Allocation>;
  /** Puts fulfilled stock back as a `return` movement. */
  restoreAllocation(
    allocationId: string,
    quantity: number,
    detail?: StockDetail,
  ): AsyncResult<Allocation>;
  /** Releases a document's open allocations. Resolves to the number released. */
  releaseAllocations(
    organizationId: string,
    documentType: string,
    documentId: string,
  ): AsyncResult<number>;
  listAllocations(
    organizationId: string,
    documentType: string,
    documentId: string,
  ): AsyncResult<readonly Allocation[]>;
}

const nullable = (value: unknown): string | null => optionalText(value) ?? null;

function itemOf(value: unknown): StockItem {
  const row = recordOf(value, "set_stock_item");

  return {
    variantId: textOf(row["variantId"]),
    unit: textOf(row["unit"]),
    scale: Number(row["scale"]),
    tracking: enumOrThrow(row["tracking"], TRACKING_MODES, "tracking"),
    tracksExpiry: row["tracksExpiry"] === true,
    costing: enumOrThrow(row["costing"], COSTING_METHODS, "costing"),
    currency: nullable(row["currency"]),
    averageCost: nullable(row["averageCost"]),
  };
}

function bucketOf(value: unknown): StockBucket {
  const row = recordOf(value, "stock_detail");

  return {
    binId: nullable(row["binId"]),
    binCode: nullable(row["binCode"]),
    hold: row["hold"] === true,
    lotId: nullable(row["lotId"]),
    lotCode: nullable(row["lotCode"]),
    expiresOn: nullable(row["expiresOn"]),
    onHand: Number(row["onHand"]),
  };
}

function expiringOf(value: unknown): ExpiringLot {
  const row = recordOf(value, "expiring_lots");

  return {
    lotId: textOf(row["lotId"]),
    code: textOf(row["code"]),
    variantId: textOf(row["variantId"]),
    locationId: textOf(row["locationId"]),
    binId: nullable(row["binId"]),
    expiresOn: textOf(row["expiresOn"]),
    onHand: Number(row["onHand"]),
  };
}

/** One allocation row. */
function allocationOf(value: unknown): Allocation {
  const row = recordOf(value, "allocation");
  const movementId = optionalText(row["movementId"]);

  return {
    id: textOf(row["id"]),
    variantId: textOf(row["variantId"]),
    locationId: textOf(row["locationId"]),
    documentType: textOf(row["documentType"]),
    documentId: textOf(row["documentId"]),
    lineId: textOf(row["lineId"]),
    quantity: Number(row["quantity"]),
    allocated: Number(row["allocated"]),
    fulfilled: Number(row["fulfilled"]),
    backordered: Number(row["backordered"]),
    status: enumOrThrow(
      row["status"],
      ALLOCATION_STATUSES,
      "allocation status",
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(movementId === undefined ? {} : { movementId }),
  };
}

function valuationOf(value: unknown): StockValuation {
  const row = recordOf(value, "stock_valuation");
  const currency = nullable(row["currency"]);

  return {
    variantId: textOf(row["variantId"]),
    costing: enumOrThrow(row["costing"], COSTING_METHODS, "costing"),
    averageCost: nullable(row["averageCost"]),
    onHand: Number(row["onHand"]),
    value:
      currency === null ? null : money(BigInt(textOf(row["value"])), currency),
  };
}

/** The tracking methods of the inventory client. */
export function inventoryTracking(call: BlockCall): InventoryTracking {
  return {
    setStockItem: (variantId, input) =>
      call(
        "set_stock_item",
        {
          variant: variantId,
          unit: input.unit ?? null,
          scale: input.scale ?? null,
          tracking: input.tracking ?? null,
          tracks_expiry: input.tracksExpiry ?? null,
          costing: input.costing ?? null,
          currency: input.currency ?? null,
        },
        itemOf,
      ),
    saveBin: (locationId, input) =>
      call(
        "save_bin",
        {
          location: locationId,
          bin: input.id ?? null,
          code: input.code,
          name: input.name ?? null,
          hold: input.hold ?? null,
          active: input.active ?? null,
        },
        (value) => {
          const row = recordOf(value, "save_bin");

          return {
            id: textOf(row["id"]),
            code: textOf(row["code"]),
            hold: row["hold"] === true,
            active: row["active"] === true,
          };
        },
      ),
    saveLot: (variantId, code, expiresOn) =>
      call(
        "save_lot",
        { variant: variantId, code, expires_on: expiresOn ?? null },
        (value) => {
          const row = recordOf(value, "save_lot");

          return {
            id: textOf(row["id"]),
            code: textOf(row["code"]),
            expiresOn: nullable(row["expiresOn"]),
          };
        },
      ),
    stockDetail: (variantId, locationId) =>
      call(
        "stock_detail",
        { variant: variantId, location: locationId },
        (value) => {
          const row = recordOf(value, "stock_detail");

          return {
            variantId: textOf(row["variantId"]),
            locationId: textOf(row["locationId"]),
            onHand: Number(row["onHand"]),
            reserved: Number(row["reserved"]),
            held: Number(row["held"]),
            available: Number(row["available"]),
            unbinned: Number(row["unbinned"]),
            buckets: recordsOf(row["buckets"], "stock_detail").map(bucketOf),
            serials: stringsOf(row["serials"]),
          };
        },
      ),
    expiringLots: (organizationId, before) =>
      call("expiring_lots", { tenant: organizationId, before }, (value) =>
        recordsOf(value, "expiring_lots").map(expiringOf),
      ),
    expireLots: (organizationId, asOf) =>
      call(
        "expire_lots",
        { tenant: organizationId, as_of: asOf ?? null },
        Number,
      ),
    stockValuation: (variantId) =>
      call("stock_valuation", { variant: variantId }, valuationOf),
    allocate: (organizationId, input) =>
      call(
        "allocate_stock",
        {
          tenant: organizationId,
          variant: input.variantId,
          location: input.locationId,
          quantity: input.quantity,
          document_type: input.documentType,
          document_id: input.documentId,
          line_id: input.lineId,
          backorder: input.backorder ?? true,
        },
        allocationOf,
      ),
    fulfillAllocation: (allocationId, quantity, detail) =>
      call(
        "fulfill_allocation",
        { allocation: allocationId, quantity, detail: detailArg(detail) },
        allocationOf,
      ),
    restoreAllocation: (allocationId, quantity, detail) =>
      call(
        "restore_allocation",
        { allocation: allocationId, quantity, detail: detailArg(detail) },
        allocationOf,
      ),
    releaseAllocations: (organizationId, documentType, documentId) =>
      call(
        "release_allocations",
        {
          tenant: organizationId,
          document_type: documentType,
          document_id: documentId,
        },
        Number,
      ),
    listAllocations: (organizationId, documentType, documentId) =>
      call(
        "list_allocations",
        {
          tenant: organizationId,
          document_type: documentType,
          document_id: documentId,
        },
        (value) => recordsOf(value, "list_allocations").map(allocationOf),
      ),
  };
}
