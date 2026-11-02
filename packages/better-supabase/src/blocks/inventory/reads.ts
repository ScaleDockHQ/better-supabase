import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { InventoryOverview } from "../../sql/modules/inventory-reads.ts";

import { decodeRead } from "../../core/read-type.ts";
import { INVENTORY_OVERVIEW_RESULT } from "../../sql/modules/inventory-reads.ts";

export type {
  InventoryExpiringLot,
  InventoryLowStock,
  InventoryOverview,
} from "../../sql/modules/inventory-reads.ts";

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
  };
}
