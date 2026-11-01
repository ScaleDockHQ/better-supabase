import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { PaymentRecord, TrackingInput } from "../orders/index.ts";
import type { CommerceParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `commerce.payAndFulfil` returns. */
export interface PaidAndFulfilled {
  readonly payment: PaymentRecord;
  readonly fulfillment: { readonly id: string; readonly shipped: boolean };
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
  };

  return withBlockHooks(client, options.hooks, {
    block: "commerce",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
