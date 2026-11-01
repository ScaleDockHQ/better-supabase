import type { Money } from "../../commerce/money.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { QuantityLine } from "./codecs.ts";
import type {
  Orders,
  PaymentRecord,
  RefundOutcome,
  TrackingInput,
} from "./orders.ts";

import { money } from "../../commerce/money.ts";
import { ok } from "../../core/result.ts";

/** The multi-step methods of the orders client. */
export interface OrderHelpers {
  /**
   * Records a payment taken outside the provider (a bank transfer, cash) for
   * the order's whole total. It reads `getOrder`, calls `recordPayment` with
   * the `manual` provider and the reference (default `manual:<orderId>`, so a
   * repeat is a no-op), then commits the tax when the order became paid.
   * Service only, like `recordPayment`.
   */
  markPaid(input: {
    orderId: string;
    reference?: string | undefined;
  }): AsyncResult<PaymentRecord>;
  /**
   * Takes `lines` back and refunds them: `requestReturn`, `receiveReturn`
   * (`restock` default true) and `refund` for the return, with `reason` on
   * both. The refund is the whole outstanding payment unless `amount` is set. A
   * failure stops the chain; the return it already made stays and can be
   * refunded with `refund`.
   */
  returnAndRefund(input: {
    orderId: string;
    lines: readonly QuantityLine[];
    reason?: string | undefined;
    restock?: boolean | undefined;
    locationId?: string | undefined;
    amount?: Money | undefined;
  }): AsyncResult<{
    readonly returnId: string;
    readonly refund: RefundOutcome;
  }>;
  /**
   * Creates one fulfillment with every unit not fulfilled yet and, when
   * `tracking` is set, ships it with that tracking. It calls
   * `createFulfillment` and `shipFulfillment`.
   */
  fulfilAll(input: {
    orderId: string;
    locationId?: string | undefined;
    tracking?: TrackingInput | undefined;
  }): AsyncResult<{ readonly id: string; readonly shipped: boolean }>;
}

/**
 * The multi-step helpers of the orders client. They call `client()`, the hooked
 * client, so app hooks see each step.
 */
export function orderHelpers<F extends object>(
  client: () => Orders<F>,
  afterPayment: (record: PaymentRecord) => Promise<void>,
): OrderHelpers {
  return {
    markPaid: ({ orderId, reference }) =>
      client()
        .getOrder(orderId)
        .andThen(async (order) => {
          const { total } = order;

          const recorded = await client().recordPayment({
            orderId,
            payment: {
              id: reference ?? `manual:${orderId}`,
              provider: "manual",
              status: "succeeded",
              amount: total,
              captured: total,
              refunded: money(0, order.currency),
              reference: orderId,
              metadata: {},
            },
          });

          if (recorded.ok) {
            await afterPayment(recorded.data);
          }

          return recorded;
        }),
    returnAndRefund: ({
      orderId,
      lines,
      reason,
      restock,
      locationId,
      amount,
    }) =>
      client()
        .requestReturn({ orderId, lines, reason })
        .andThen(async (made) => {
          const received = await client().receiveReturn({
            returnId: made.id,
            ...(restock === undefined ? {} : { restock }),
            ...(locationId === undefined ? {} : { locationId }),
          });

          if (!received.ok) {
            return received;
          }

          const refunded = await client().refund({
            orderId,
            input: {
              returnId: made.id,
              ...(reason === undefined ? {} : { reason }),
              ...(amount === undefined ? {} : { amount }),
            },
          });

          return refunded.ok
            ? ok({ returnId: made.id, refund: refunded.data })
            : refunded;
        }),
    fulfilAll: ({ orderId, locationId, tracking }) =>
      client()
        .createFulfillment({
          orderId,
          input: locationId === undefined ? undefined : { locationId },
        })
        .andThen(async (fulfillment) => {
          if (tracking === undefined) {
            return ok({ id: fulfillment.id, shipped: false });
          }

          const shipped = await client().shipFulfillment({
            fulfillmentId: fulfillment.id,
            tracking,
          });

          return shipped.ok
            ? ok({ id: fulfillment.id, shipped: shipped.data })
            : shipped;
        }),
  };
}
