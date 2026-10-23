import type { Action } from "../../core/automation.ts";
import type { Result } from "../../core/result.ts";
import type {
  ConversionClients,
  ConversionContext,
} from "../automations/conversion.ts";

import { defineConversionAction } from "../automations/conversion.ts";

export interface OrderFromQuoteOptions<C extends ConversionClients> {
  /** The clients for one organization, over a service connection. */
  readonly clients: (tenant: string) => C | PromiseLike<C>;
  /**
   * Creates the order for an accepted quote and returns its id, such as a cart
   * of the quote's variants and `orders.checkout`. The orders block has no
   * conversion from a quote, so the app supplies it.
   */
  readonly create: (
    context: ConversionContext<C>,
  ) => PromiseLike<Result<{ readonly id: string }>>;
}

/**
 * The `orders.from_quote` action, which the quotes block's default automation
 * runs on `quote.accepted` once an organization turns it on: an order linked
 * `created_from` the quote, so an accepted quote orders once.
 */
export function orderFromQuoteAction<C extends ConversionClients>(
  options: OrderFromQuoteOptions<C>,
): Action {
  return defineConversionAction<C, undefined, undefined>({
    kind: "orders.from_quote",
    title: "Order the accepted quote",
    targetType: "order",
    clients: options.clients,
    map: () => undefined,
    create: (_, context) => options.create(context),
  });
}
