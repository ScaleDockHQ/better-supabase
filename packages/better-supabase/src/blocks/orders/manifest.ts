import type { BlockOf } from "../define-block.ts";
import type { OrdersEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { orderFromQuoteFactory } from "./actions.ts";
import { ordersEvents } from "./events.ts";
import { ordersSqlOptions } from "./options.ts";
import { createOrders } from "./orders.ts";

/** The `orders` block's manifest (ADR 0029). */
export const ordersBlock: BlockOf<"orders", typeof createOrders, OrdersEvents> =
  defineBlock({
    name: "orders",
    sql: ["orders"],
    options: { orders: ordersSqlOptions },
    events: ordersEvents,
    create: createOrders,
    category: "commerce",
    entities: {
      order: { mutability: "state-machine" },
      cart: { mutability: "append-only", emits: { create: false } },
    },
    description:
      "Carts on anonymous or signed-in users, checkout priced from the catalog, confirmed orders from lines or an accepted quote with stock allocations, gapless order and invoice numbers, payments, fulfillments, returns and refunds, with an optional kitchen display. With invoices, a paid order gets an issued, paid invoice.",
    recipes: ["order-detail", "kitchen-display", "order-state-board"],
    actions: [{ kind: "orders.from_quote", title: "Order the accepted quote" }],
    handlers: { "orders.from_quote": orderFromQuoteFactory },
    providers: [
      {
        option: "payments",
        type: "PaymentProvider",
        from: "better-supabase/commerce",
        required: false,
        description:
          "Takes payments; without one, payments are recorded by hand.",
        example: "stripePayments({ stripe })",
      },
      {
        option: "tax",
        type: "TaxProvider",
        from: "better-supabase/commerce",
        required: false,
        description: "Computes tax on order lines.",
        example: "fixedRates({ rates })",
      },
    ],
  });
