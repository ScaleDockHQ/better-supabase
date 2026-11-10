import type { BlockCall } from "../../core/block-helpers.ts";
import type { ReadType } from "../../core/read-type.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { InventoryOverview } from "../../sql/modules/inventory-reads.ts";

import { decodeRead } from "../../core/read-type.ts";
import { INVENTORY_OVERVIEW_RESULT } from "../../sql/modules/inventory-reads.ts";

export type {
  InventoryExpiringLot,
  InventoryLowStock,
  InventoryOverview,
} from "../../sql/modules/inventory-reads.ts";

/** How a stock level compares with its reorder point. */
export type StockLevelStatus = "in_stock" | "low" | "out";

/** One stock level, as `inventory.levels` reads it. Quantities are text. */
export interface StockLevelRead {
  readonly variantId: string;
  readonly locationId: string;
  readonly onHand: string;
  readonly allocated: string;
  readonly available: string;
  readonly incoming: string;
  readonly reorderPoint: string | null;
  readonly status: StockLevelStatus;
}

/** One ledger movement, as `inventory.movements` reads it. */
export interface StockMovementRead {
  readonly id: string;
  readonly kind: string;
  readonly variantId: string | null;
  readonly locationId: string | null;
  readonly binId: string | null;
  readonly lotId: string | null;
  /** Signed, as text. */
  readonly quantity: string | null;
  readonly documentType: string | null;
  readonly documentId: string | null;
  readonly effectiveAt: string;
}

const STOCK_LEVELS_RESULT: ReadType = [
  {
    variantId: "text",
    locationId: "text",
    onHand: "text",
    allocated: "text",
    available: "text",
    incoming: "text",
    reorderPoint: "text?",
    status: "text",
  },
];

const STOCK_MOVEMENTS_RESULT: ReadType = [
  {
    id: "text",
    kind: "text",
    variantId: "text?",
    locationId: "text?",
    binId: "text?",
    lotId: "text?",
    quantity: "text?",
    documentType: "text?",
    documentId: "text?",
    effectiveAt: "text",
  },
];

/** The composed reads of the inventory client. */
export interface InventoryReads {
  /**
   * The stock page in one call: the number of stock levels, the levels at or
   * below their reorder point (the emptiest `limit`, default 20) and the lots
   * that expire within `expiryDays` (default 30). Quantities are text.
   */
  overview(input: {
    organizationId: string;
    limit?: number | undefined;
    expiryDays?: number | undefined;
  }): AsyncResult<InventoryOverview>;
  /**
   * Stock levels in one call. `variantIds` reads those variants by the level
   * primary key, so a page of 50 products is one query and not 50. Leave it out
   * to read every level, and pass `locationId` to read one location.
   */
  levels(input: {
    organizationId: string;
    variantIds?: readonly string[] | undefined;
    locationId?: string | undefined;
  }): AsyncResult<readonly StockLevelRead[]>;
  /**
   * Ledger movements of kind `stock.*`, newest first, filtered by variant,
   * location, bin, lot or document. `limit` defaults to 50 and is capped at 200.
   */
  movements(input: {
    organizationId: string;
    variantId?: string | undefined;
    locationId?: string | undefined;
    binId?: string | undefined;
    lotId?: string | undefined;
    documentType?: string | undefined;
    documentId?: string | undefined;
    limit?: number | undefined;
    offset?: number | undefined;
  }): AsyncResult<readonly StockMovementRead[]>;
}

export function inventoryReads(call: BlockCall): InventoryReads {
  return {
    overview: ({ organizationId, limit, expiryDays }) =>
      call(
        "inventory_overview",
        {
          tenant: organizationId,
          ...(limit === undefined ? {} : { row_limit: limit }),
          ...(expiryDays === undefined ? {} : { expiry_days: expiryDays }),
        },
        (value) =>
          decodeRead<InventoryOverview>(
            INVENTORY_OVERVIEW_RESULT,
            value,
            "inventory_overview",
          ),
      ),
    levels: ({ organizationId, variantIds, locationId }) =>
      call(
        "inventory_levels",
        {
          tenant: organizationId,
          variant_ids: variantIds ?? null,
          location_id: locationId ?? null,
        },
        (value) => decodeRead(STOCK_LEVELS_RESULT, value, "levels"),
      ),
    movements: (input) =>
      call(
        "list_inventory_movements",
        {
          tenant: input.organizationId,
          variant: input.variantId ?? null,
          location: input.locationId ?? null,
          bin: input.binId ?? null,
          lot: input.lotId ?? null,
          document_type: input.documentType ?? null,
          document_id: input.documentId ?? null,
          row_limit: input.limit ?? null,
          row_offset: input.offset ?? null,
        },
        (value) => decodeRead(STOCK_MOVEMENTS_RESULT, value, "movements"),
      ),
  };
}
