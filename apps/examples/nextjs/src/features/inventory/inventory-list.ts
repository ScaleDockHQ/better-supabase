import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

export const STOCK_STATUS_VALUES = ["in_stock", "low", "out"] as const;

export type StockStatus = (typeof STOCK_STATUS_VALUES)[number];

/** One stock level of the overview, as the page and the list route send it. */
export interface StockRow {
  /** `variantId:locationId`, the level's primary key. */
  readonly id: string;
  readonly variantId: string;
  readonly productTitle: string;
  readonly sku: string;
  readonly locationId: string;
  readonly locationName: string;
  readonly onHand: number;
  readonly reserved: number;
  readonly available: number;
  readonly incoming: number;
  readonly reorderPoint: number | null;
  readonly status: StockStatus;
}

export function stockStatus(
  available: number,
  reorderPoint: number | null,
): StockStatus {
  if (available <= 0) {
    return "out";
  }

  return reorderPoint !== null && available <= reorderPoint
    ? "low"
    : "in_stock";
}

/** `/shop/inventory?q=&status=&location=&sort=&after=`. */
export const stockList = defineBlockList({
  facets: ["status", "location"],
  sorts: ["product", "available", "on_hand"],
  defaultSort: "product",
  pageSize: 25,
});

/** The stock list's URL names on the inventory block's level list. */
export const stockMap: EntityListMap = {
  sorts: {
    product: { by: "variantId" },
    // The emptiest first, so the levels that need an order come on top.
    available: { by: "available", direction: "asc" },
    on_hand: { by: "onHand", direction: "desc" },
  },
  filters: { location: "locationId" },
  facets: { location: "locationId" },
};

/** One ledger movement of the movements overview. */
export interface MovementRow {
  readonly id: string;
  readonly kind: string;
  readonly variantId: string | null;
  readonly productTitle: string;
  readonly sku: string;
  readonly locationId: string | null;
  readonly locationName: string;
  /** Signed. */
  readonly quantity: number;
  readonly documentType: string | null;
  readonly effectiveAt: string;
}

/** The ledger's `stock.<reason>` kinds the example writes or reads. */
export const MOVEMENT_KIND_VALUES = [
  "stock.receipt",
  "stock.adjustment",
  "stock.damage",
  "stock.loss",
  "stock.return",
  "stock.scrap",
  "stock.sale",
  "stock.count",
  "stock.transfer",
] as const;

/** `/shop/inventory/movements?q=&kind=&location=&sort=&after=`. */
export const movementList = defineBlockList({
  facets: ["kind", "location"],
  sorts: ["newest", "oldest", "quantity"],
  defaultSort: "newest",
  pageSize: 25,
});

/** The movements list's URL names on the inventory block's movement list. */
export const movementMap: EntityListMap = {
  sorts: {
    newest: { by: "effectiveAt", direction: "desc" },
    oldest: { by: "effectiveAt", direction: "asc" },
    quantity: { by: "quantity", direction: "desc" },
  },
  filters: { location: "locationId" },
  facets: { location: "locationId" },
};

/** One lot with stock, on the lots overview. */
export interface LotRow {
  readonly id: string;
  readonly code: string;
  readonly variantId: string;
  readonly productTitle: string;
  readonly sku: string;
  readonly locationId: string;
  readonly locationName: string;
  readonly expiresOn: string;
  readonly onHand: number;
  readonly daysLeft: number;
  readonly expiry: "expired" | "soon" | "later";
}

export const LOT_EXPIRY_VALUES = ["expired", "soon", "later"] as const;

/** `/shop/inventory/lots?q=&expiry=&location=&sort=&after=`. */
export const lotList = defineBlockList({
  facets: ["expiry", "location"],
  sorts: ["expires", "on_hand", "code"],
  defaultSort: "expires",
  pageSize: 25,
});

/** The lots list's URL names on the inventory block's lot list. */
export const lotMap: EntityListMap = {
  sorts: {
    expires: { by: "expiresOn", direction: "asc" },
    on_hand: { by: "onHand", direction: "desc" },
    code: { by: "code", direction: "asc" },
  },
  filters: { location: "locationId" },
  facets: { location: "locationId" },
  // Lots that never expire stay off the overview, as before.
  defaultFilters: { expiry: ["expired", "soon", "later"] },
};
