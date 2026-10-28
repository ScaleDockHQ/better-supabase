import type { Action } from "../../core/automation.ts";
import type { Result } from "../../core/result.ts";
import type {
  ConversionClients,
  ConversionContext,
} from "../automations/conversion.ts";
import type { OrderDocuments } from "./documents.ts";

import { dbError } from "../../core/errors.ts";
import { err } from "../../core/result.ts";
import { defineConversionAction } from "../automations/conversion.ts";
import { isRecord } from "../shared.ts";

/** Clients with an orders client, so the action can call `fromQuote`. */
export interface OrderFromQuoteClients extends ConversionClients {
  readonly orders: Pick<OrderDocuments, "fromQuote">;
}

type CreateOrder<C> = (
  context: ConversionContext<C>,
) => PromiseLike<Result<{ readonly id: string }>>;

export interface OrderFromQuoteOptions<C extends ConversionClients> {
  /** The clients for one organization, over a service connection. */
  readonly clients: (tenant: string) => C | PromiseLike<C>;
  /**
   * Creates the order for an accepted quote and returns its id. Default:
   * `clients.orders.fromQuote`, which copies the quote's lines and totals;
   * without an orders client the action fails with `ORDERS_CLIENT_MISSING`.
   */
  readonly create?: CreateOrder<C>;
}

function hasOrders(clients: unknown): clients is OrderFromQuoteClients {
  return (
    isRecord(clients) &&
    isRecord(clients["orders"]) &&
    typeof clients["orders"]["fromQuote"] === "function"
  );
}

const fromQuote = <C>(
  context: ConversionContext<C>,
): PromiseLike<Result<{ readonly id: string }>> =>
  hasOrders(context.clients)
    ? context.clients.orders
        .fromQuote(context.source.id)
        .map(({ order }) => ({ id: order.id }))
    : Promise.resolve(
        err(
          dbError("invalid_request", "the clients have no orders client", {
            hint: "ORDERS_CLIENT_MISSING",
          }),
        ),
      );

/**
 * The `orders.from_quote` action, which the quotes block's default automation
 * runs on `quote.accepted` once an organization turns it on: an order linked
 * `created_from` the quote, so an accepted quote orders once.
 */
export function orderFromQuoteAction<C extends ConversionClients>(
  options: OrderFromQuoteOptions<C>,
): Action {
  const create: CreateOrder<C> =
    options.create ?? ((context) => fromQuote(context));

  return defineConversionAction<C, undefined, undefined>({
    kind: "orders.from_quote",
    title: "Order the accepted quote",
    targetType: "order",
    clients: options.clients,
    map: () => undefined,
    create: (_, context) => create(context),
  });
}
