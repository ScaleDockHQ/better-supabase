import type {
  BlockCall,
  Count,
  FacetResult,
  ListPage,
} from "../../core/block-helpers.ts";
import type {
  CountOptions,
  EntityPageOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { ReadType } from "../../core/read-type.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { OrderStatusBoard } from "../../sql/modules/orders-reads.ts";

import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { decodeRead } from "../../core/read-type.ts";
import { ORDER_STATUS_BOARD_RESULT } from "../../sql/modules/orders-reads.ts";
import { orderListSurface } from "./lists.ts";

export type {
  OrderStatusCard,
  OrderStatusColumn,
  OrderStatusTotal,
  OrderStatusBoard,
} from "../../sql/modules/orders-reads.ts";

const ORDER_PAGE_ROW: ReadType = {
  id: "text",
  number: "text",
  status: "text",
  customerId: "text?",
  currency: "text",
  total: "text",
  paidTotal: "text",
  placedAt: "text",
  channel: "text?",
  source: "text?",
  externalId: "text?",
  invoicingPolicy: "text?",
  deliveryMethod: "text?",
  quoteId: "text?",
  orderDiscount: "text?",
  promotionId: "text?",
  paymentRequired: "bool?",
  deposit: "text?",
  party: "json",
};

/**
 * One order of `orderPage`. Amounts are minor units as text; the staff order
 * fields are null when the orders table doesn't map their column.
 */
export interface OrderSummary {
  readonly id: string;
  readonly number: string;
  readonly status: string;
  readonly customerId: string | null;
  readonly currency: string;
  readonly total: string;
  readonly paidTotal: string;
  readonly placedAt: string;
  readonly channel: string | null;
  readonly source: string | null;
  readonly externalId: string | null;
  readonly invoicingPolicy: string | null;
  readonly deliveryMethod: string | null;
  readonly quoteId: string | null;
  readonly orderDiscount: string | null;
  readonly promotionId: string | null;
  readonly paymentRequired: boolean | null;
  readonly deposit: string | null;
  /** `{ type, id }` of the contact or company the order is for, or null. */
  readonly party: { readonly type: string; readonly id: string } | null;
}

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
  /**
   * One keyset page of the organization's orders, newest first (ADR 1077).
   * `filters` takes `status`, `customerId`, `partyId`, `channel`, `source` and
   * `currency` as lists, and `from` and `to` as instants on the placed time;
   * `q` matches the number, the email and the external id.
   */
  orderPage(
    options: EntityPageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<OrderSummary>>;
  /**
   * The values of each facet (`status`, `currency`, `channel`) under the page's
   * filters.
   */
  orderFacets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many orders match the page's filters. */
  orderCount(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
}

export function orderReads(call: BlockCall): OrderReads {
  const orderRows = entityList<OrderSummary, RequiredTenantOption>({
    entity: "order",
    surface: orderListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_orders",
    rowOf: (row, fn) => decodeRead<OrderSummary>(ORDER_PAGE_ROW, row, fn),
  });

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
    orderPage: orderRows.page,
    orderFacets: orderRows.facets,
    orderCount: orderRows.count,
  };
}
