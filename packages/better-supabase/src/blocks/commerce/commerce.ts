import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type {
  PaymentRecord,
  RefundOutcome,
  RefundRequest,
  TrackingInput,
} from "../orders/index.ts";
import type { CommerceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `commerce.payAndFulfil` returns. */
export interface PaidAndFulfilled {
  readonly payment: PaymentRecord;
  readonly fulfillment: { readonly id: string; readonly shipped: boolean };
}

/** What happens to the units of a return. */
export type ReturnDisposition = "restock" | "quarantine" | "reject";

/** What `commerce.processReturn` returns. */
export interface ProcessedReturn {
  readonly disposition: ReturnDisposition;
  /** The refund, or `null` when none was asked for or the return was rejected. */
  readonly refund: RefundOutcome | null;
}

/** The helpers `commerce` adds over its parts. */
export interface Commerce {
  /**
   * Books a payment taken outside the provider (`orders.markPaid`), then
   * fulfils every unit not fulfilled yet (`orders.fulfilAll`) and ships it when
   * `tracking` is set. Both steps are idempotent for one order, so a retry
   * after a failure in the middle finishes the chain. Service only, like
   * `markPaid`.
   */
  payAndFulfil(input: {
    orderId: string;
    reference?: string | undefined;
    locationId?: string | undefined;
    tracking?: TrackingInput | undefined;
  }): AsyncResult<PaidAndFulfilled>;
  /**
   * Settles a return by what happens to its units. `restock` receives them and
   * puts tracked ones back in stock, `quarantine` receives them without
   * restocking (the app inspects them, then adjusts stock with
   * `inventory.adjustStock`), and `reject` refuses the return. With `refund` on
   * a received return, it then refunds the order (`orders.refund`), linked to
   * the return. A failed refund returns its error and leaves the units
   * received, so retry it with `orders.refund`.
   */
  processReturn(input: {
    orderId: string;
    returnId: string;
    disposition: ReturnDisposition;
    /** Where restocked units go. Default: the order's location. */
    locationId?: string | undefined;
    /** Refunds the order: `true` for what is paid, or a request for an amount. */
    refund?: RefundRequest | true | undefined;
  }): AsyncResult<ProcessedReturn>;
}

/** What the `commerce` creator receives. */
export type CommerceOptions = BlockContext &
  CompositeOptions<CommerceParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Commerce>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `commerce` helpers over the clients of its parts. */
export function createCommerce(options: CommerceOptions): Commerce {
  const { orders } = options.parts;

  const client: Commerce = {
    payAndFulfil: ({ orderId, reference, locationId, tracking }) =>
      Async.from(async () => {
        const payment = await orders.markPaid({
          orderId,
          ...(reference === undefined ? {} : { reference }),
        });

        if (!payment.ok) {
          return payment;
        }

        const fulfillment = await orders.fulfilAll({
          orderId,
          ...(locationId === undefined ? {} : { locationId }),
          ...(tracking === undefined ? {} : { tracking }),
        });

        return fulfillment.ok
          ? ok({ payment: payment.data, fulfillment: fulfillment.data })
          : fulfillment;
      }),
    processReturn: ({ orderId, returnId, disposition, locationId, refund }) =>
      Async.from<ProcessedReturn>(async () => {
        switch (disposition) {
          case "reject": {
            const rejected = await orders.rejectReturn(returnId);

            return rejected.ok ? ok({ disposition, refund: null }) : rejected;
          }

          case "restock":
          case "quarantine": {
            const received = await orders.receiveReturn({
              returnId,
              restock: disposition === "restock",
              ...(locationId === undefined ? {} : { locationId }),
            });

            if (!received.ok) {
              return received;
            }

            if (refund === undefined) {
              return ok({ disposition, refund: null });
            }

            const refunded = await orders.refund({
              orderId,
              input: { ...(refund === true ? {} : refund), returnId },
            });

            return refunded.ok
              ? ok({ disposition, refund: refunded.data })
              : refunded;
          }

          default: {
            const unreachable: never = disposition;

            return unreachable;
          }
        }
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "commerce",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
