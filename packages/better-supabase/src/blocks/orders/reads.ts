import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { OrderStatusBoard } from "../../sql/modules/orders-reads.ts";

import { decodeRead } from "../../core/read-type.ts";
import { ORDER_STATUS_BOARD_RESULT } from "../../sql/modules/orders-reads.ts";

export type {
  OrderStatusCard,
  OrderStatusColumn,
  OrderStatusTotal,
  OrderStatusBoard,
} from "../../sql/modules/orders-reads.ts";

/** The composed reads of the orders client. */
export interface OrderReads {
  /**
   * An organization's orders by status in one call: a column per status with
   * its count, its totals per currency and its latest `perStatus` orders
   * (default 20). Amounts are text; wrap them with `money` to compute.
   */
  board(input: {
    organizationId: string;
    perStatus?: number | undefined;
  }): AsyncResult<OrderStatusBoard>;
}

export function orderReads(call: BlockCall): OrderReads {
  return {
    board: ({ organizationId, perStatus }) =>
      call(
        "order_status_board",
        {
          tenant: organizationId,
          ...(perStatus === undefined ? {} : { per_status: perStatus }),
        },
        (value) =>
          decodeRead<OrderStatusBoard>(
            ORDER_STATUS_BOARD_RESULT,
            value,
            "order_status_board",
          ),
      ),
  };
}
