import type {
  BlockCall,
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { ReadType } from "../../core/read-type.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { InventoryOverview } from "../../sql/modules/inventory-reads.ts";

import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { decodeRead } from "../../core/read-type.ts";
import { INVENTORY_OVERVIEW_RESULT } from "../../sql/modules/inventory-reads.ts";
import {
  stockLevelListSurface,
  stockLotListSurface,
  stockMovementListSurface,
} from "./lists.ts";

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

/** One stock level on a page: the level plus its `variant:location` id. */
export interface StockLevelPageRead extends StockLevelRead {
  readonly id: string;
}

/** One lot's stock at a location and bin, as `inventory.lotPage` reads it. */
export interface StockLotRead {
  /** `lot:location:bin`; the bin part is empty without a bin. */
  readonly id: string;
  readonly lotId: string;
  readonly code: string;
  readonly variantId: string;
  readonly locationId: string;
  readonly binId: string | null;
  /** A date, or `null` for a lot that does not expire. */
  readonly expiresOn: string | null;
  readonly onHand: string;
  readonly expiry: "expired" | "soon" | "later" | "none";
}

const LEVEL_PAGE_ROW: ReadType = {
  id: "text",
  variantId: "text",
  locationId: "text",
  onHand: "text",
  allocated: "text",
  available: "text",
  incoming: "text",
  reorderPoint: "text?",
  status: "text",
};

const MOVEMENT_ROW: ReadType = {
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
};

const LOT_ROW: ReadType = {
  id: "text",
  lotId: "text",
  code: "text",
  variantId: "text",
  locationId: "text",
  binId: "text?",
  expiresOn: "text?",
  onHand: "text",
  expiry: "text",
};

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
   * One keyset page of the stock levels, emptiest first. `filters` takes
   * `status` (`in_stock`, `low`, `out`), `variantId` and `locationId` as lists;
   * `q` matches a variant or location id. Quantities are text.
   */
  levelPage(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<StockLevelPageRead>>;
  /** The values of each facet (`status`, `locationId`) under the page's filters. */
  levelFacets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many stock levels match the page's filters. */
  levelCount(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /** One stock level by its `variant:location` id, or a `not_found` error. */
  getLevel(id: string): AsyncResult<StockLevelPageRead>;
  /**
   * One keyset page of the `stock.*` ledger movements, newest first. `filters`
   * takes `kind`, `variantId`, `locationId`, `binId`, `lotId`, `documentType`
   * and `documentId` as lists; `q` matches the kind and the document id.
   */
  movementPage(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<StockMovementRead>>;
  /** The values of each facet (`kind`, `locationId`) under the page's filters. */
  movementFacets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many movements match the page's filters. */
  movementCount(
    options: CountOptions & RequiredTenantOption,
  ): AsyncResult<Count>;
  /** One movement by id, or a `not_found` error. */
  getMovement(id: string): AsyncResult<StockMovementRead>;
  /**
   * One keyset page of the lots that hold stock, soonest expiry first, one row
   * per lot, location and bin. `filters` takes `expiry` (`expired`, `soon`,
   * `later`, `none`), `variantId` and `locationId` as lists; `q` matches the
   * lot code.
   */
  lotPage(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<StockLotRead>>;
  /** The values of each facet (`expiry`, `locationId`) under the page's filters. */
  lotFacets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many lot rows match the page's filters. */
  lotCount(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /** One lot's stock by `lot:location:bin` id, or a `not_found` error. */
  getLot(id: string): AsyncResult<StockLotRead>;
  /**
   * @deprecated Use `levelPage`, which pages by keyset and takes `q`, sorts,
   * array filters and a count (ADR 1077).
   *
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
   * @deprecated Use `movementPage` (ADR 1077).
   *
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
  const levelRows = entityList<StockLevelPageRead, RequiredTenantOption>({
    entity: "inventory_level",
    surface: stockLevelListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_inventory_levels",
    rowOf: (row, fn) => decodeRead<StockLevelPageRead>(LEVEL_PAGE_ROW, row, fn),
  });

  const movementRows = entityList<StockMovementRead, RequiredTenantOption>({
    entity: "inventory_movement",
    surface: stockMovementListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_inventory_movements",
    rowOf: (row, fn) => decodeRead<StockMovementRead>(MOVEMENT_ROW, row, fn),
  });

  const lotRows = entityList<StockLotRead, RequiredTenantOption>({
    entity: "inventory_lot",
    surface: stockLotListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_inventory_lots",
    rowOf: (row, fn) => decodeRead<StockLotRead>(LOT_ROW, row, fn),
  });

  return {
    levelPage: levelRows.page,
    levelFacets: levelRows.facets,
    levelCount: levelRows.count,
    getLevel: (id) =>
      call("get_inventory_level", { level_id: id }, (value) =>
        decodeRead<StockLevelPageRead>(
          LEVEL_PAGE_ROW,
          value,
          "get_inventory_level",
        ),
      ),
    movementPage: movementRows.page,
    movementFacets: movementRows.facets,
    movementCount: movementRows.count,
    getMovement: (id) =>
      call("get_inventory_movement", { movement_id: id }, (value) =>
        decodeRead<StockMovementRead>(
          MOVEMENT_ROW,
          value,
          "get_inventory_movement",
        ),
      ),
    lotPage: lotRows.page,
    lotFacets: lotRows.facets,
    lotCount: lotRows.count,
    getLot: (id) =>
      call("get_inventory_lot", { lot_id: id }, (value) =>
        decodeRead<StockLotRead>(LOT_ROW, value, "get_inventory_lot"),
      ),
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
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
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
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
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
