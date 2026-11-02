import type { Money } from "../../commerce/money.ts";
import type { BlockCall } from "../shared.ts";
import type { Address, Order } from "./codecs.ts";
import type { OrderReads } from "./reads.ts";

import { AsyncResult } from "../../core/result.ts";
import { recordOf, textOf } from "../shared.ts";
import { orderOf } from "./codecs.ts";
import { orderReads } from "./reads.ts";

/** One line of an order staff enter, such as a phone or wholesale order. */
export interface OrderLineInput {
  /** A catalog variant: the line takes its price, title and SKU. */
  readonly variantId?: string;
  /** Required without a variant. */
  readonly title?: string;
  readonly sku?: string;
  /** Whole units. */
  readonly quantity: number;
  /** The price per unit. Default: the variant's price in the order currency. */
  readonly unitAmount?: Money;
  /** Off the line total. */
  readonly discount?: Money;
  readonly tax?: Money;
  /** For a line without a variant. Default false. */
  readonly requiresShipping?: boolean;
}

export interface OrderDocumentInput {
  readonly customerId?: string;
  readonly email?: string;
  readonly shippingAddress?: Address;
  readonly billingAddress?: Address;
  /** Where the order's stock is allocated. Default: the first with stock. */
  readonly locationId?: string;
}

export interface OrderFromLinesInput extends OrderDocumentInput {
  readonly currency: string;
  readonly lines: readonly OrderLineInput[];
  readonly shippingTotal?: Money;
  readonly taxInclusive?: boolean;
  /**
   * The record the order comes from, such as a work order. An origin orders
   * once: a second call returns the first order with `created: false`.
   */
  readonly origin?: { readonly type: string; readonly id: string };
}

export interface OrderFromDocument<F extends object = Record<never, never>> {
  readonly order: Order<F>;
  /** False when the origin already had an order. */
  readonly created: boolean;
}

/** Orders from lines and from accepted quotes. */
export interface OrderDocuments<
  F extends object = Record<never, never>,
> extends OrderReads {
  /**
   * A `confirmed` order from lines, outside the cart: its stock is allocated
   * (or backordered) and taken when a fulfillment ships.
   */
  fromLines(input: {
    organizationId: string;
    input: OrderFromLinesInput;
  }): AsyncResult<OrderFromDocument<F>>;
  /**
   * The order of an accepted quote, with the quote's lines and totals. Needs
   * the quotes block; a quote orders once.
   */
  fromQuote(input: {
    quoteId: string;
    input?: OrderDocumentInput | undefined;
  }): AsyncResult<OrderFromDocument<F>>;
  /**
   * A draft inventory purchase order for a drop ship: the order's lines from
   * one supplier, delivered to the order's shipping address (`shipTo`). Needs
   * the inventory block and `inventory.purchase`; a blocked supplier is refused
   * with `PURCHASE_ORDER_SUPPLIER_BLOCKED`.
   */
  purchaseOrderFromOrder(
    input: {
      orderId: string;
      supplier: { readonly type?: string; readonly id: string };
    } & {
      /** Where the purchase order books. Default: the order's location. */
      readonly locationId?: string;
    },
  ): AsyncResult<{ readonly id: string; readonly orderId: string }>;
}

const amountOf = (value: Money | undefined): string | undefined =>
  value?.amount.toString();

function attrsOf(input: OrderDocumentInput): Record<string, unknown> {
  return {
    customerId: input.customerId,
    email: input.email,
    shippingAddress: input.shippingAddress,
    billingAddress: input.billingAddress,
    locationId: input.locationId,
  };
}

function lineOf(line: OrderLineInput): Record<string, unknown> {
  return {
    variantId: line.variantId,
    title: line.title,
    sku: line.sku,
    quantity: line.quantity,
    unitAmount: amountOf(line.unitAmount),
    discount: amountOf(line.discount),
    tax: amountOf(line.tax),
    requiresShipping: line.requiresShipping,
  };
}

/** The document methods of the orders client. */
export function orderDocuments<F extends object>(
  call: BlockCall,
  parsed: (result: AsyncResult<Order>) => AsyncResult<Order<F>>,
): OrderDocuments<F> {
  const created = (
    result: AsyncResult<{ readonly order: Order; readonly created: boolean }>,
  ): AsyncResult<OrderFromDocument<F>> =>
    result.andThen((value) =>
      parsed(AsyncResult.ok(value.order)).map((order) => ({
        order,
        created: value.created,
      })),
    );

  const of = (fn: string) => (value: unknown) => ({
    order: orderOf(value),
    created: recordOf(value, fn)["created"] !== false,
  });

  return {
    ...orderReads(call),
    fromLines: ({ organizationId, input }) =>
      created(
        call(
          "order_from_lines",
          {
            tenant: organizationId,
            lines: input.lines.map(lineOf),
            attrs: {
              ...attrsOf(input),
              currency: input.currency,
              shippingTotal: amountOf(input.shippingTotal),
              taxInclusive: input.taxInclusive,
              origin: input.origin,
            },
          },
          of("order_from_lines"),
        ),
      ),
    purchaseOrderFromOrder: ({ orderId, supplier, ...options }) =>
      call(
        "purchase_order_from_order",
        {
          order_id: orderId,
          supplier_id: supplier.id,
          supplier_type: supplier.type ?? "company",
          location: options.locationId ?? null,
        },
        (value) => {
          const row = recordOf(value, "purchase_order_from_order");

          return { id: textOf(row["id"]), orderId: textOf(row["orderId"]) };
        },
      ),
    fromQuote: ({ quoteId, input = {} }) =>
      created(
        call(
          "order_from_quote",
          { quote: quoteId, attrs: attrsOf(input) },
          of("order_from_quote"),
        ),
      ),
  };
}
