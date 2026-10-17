import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

interface Totals {
  readonly cartId: string;
  readonly subtotal: string;
  readonly discountTotal: string;
  readonly shippingTotal: string;
  readonly total: string;
  readonly lines: readonly { readonly id: string; readonly total: string }[];
  readonly problems: readonly Record<string, unknown>[];
  readonly shipping: { readonly amount: string } | null;
}

interface Order {
  readonly id: string;
  readonly number: string;
  readonly status: string;
  readonly total: string;
  readonly taxTotal: string;
  readonly created: boolean;
  readonly invoiceNumber: string | null;
  readonly lines: readonly {
    readonly id: string;
    readonly sku: string;
    readonly quantity: number;
    readonly reservationId: string | null;
    readonly backordered: boolean;
    readonly tax: string;
  }[];
}

const line = (order: Order, sku: string): Order["lines"][number] => {
  const found = order.lines.find((entry) => entry.sku === sku);

  if (found === undefined) {
    throw new Error(`no ${sku} line`);
  }

  return found;
};

const ADDRESS = { country: "NL", city: "Amsterdam", line1: "Dam 1" };

describe.skipIf(!live)("orders module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let shopper: TestUser;
  let stranger: TestUser;
  let tenant: string;
  let warehouse: string;
  let tee: string;
  let mug: string;
  let preorder: string;
  let flat: string;

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  const variant = async (
    sku: string,
    amount: string,
    backorder = false,
  ): Promise<string> => {
    const product = await call<{ id: string }>(
      "better_supabase.save_product($1, null, $2, null, null, 'physical')",
      [tenant, sku],
    );

    await call("better_supabase.set_product_status($1, 'active')", [
      product.id,
    ]);

    const saved = await call<{ id: string }>(
      "better_supabase.save_variant($1, null, $2, '{}'::uuid[], null, null, 500, true, $3)",
      [product.id, sku, backorder],
    );

    await call(
      "better_supabase.set_price($1, 'EUR', $2, null, null, null, null)",
      [saved.id, amount],
    );

    return saved.id;
  };

  const available = async (variantId: string): Promise<number> =>
    (
      await session.rows<{ available: number }>(
        "select available from better_supabase.stock_levels where variant_id = $1 and location_id = $2",
        [variantId, warehouse],
      )
    )[0]?.available ?? 0;

  const events = async (type: string): Promise<Record<string, unknown>[]> =>
    (
      await session.rows<{ data: Record<string, unknown> }>(
        "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = $2 order by position",
        [tenant, type],
      )
    ).map((row) => row.data);

  /** A shopper's open cart with lines, ready to place. */
  const cart = async (
    user: TestUser,
    lines: readonly (readonly [string, number])[],
  ): Promise<string> => {
    await session.as(user);

    const created = await call<{ id: string }>(
      "better_supabase.create_cart($1, 'EUR', null, $2)",
      [tenant, user.email],
    );

    await session.client.query(
      "delete from better_supabase.cart_lines where cart_id = $1",
      [created.id],
    );

    for (const [id, quantity] of lines) {
      await call("better_supabase.add_to_cart($1, $2, $3)", [
        created.id,
        id,
        quantity,
      ]);
    }

    await call("better_supabase.set_cart_details($1, null, $2, $2)", [
      created.id,
      JSON.stringify(ADDRESS),
    ]);
    await call("better_supabase.set_cart_shipping_rate($1, $2)", [
      created.id,
      flat,
    ]);

    return created.id;
  };

  /** Prices the cart, quotes 21% tax on every line, and places it. */
  const place = async (cartId: string): Promise<Order> => {
    await session.service();

    const totals = await call<Totals>("better_supabase.price_cart($1)", [
      cartId,
    ]);

    const lines = totals.lines.map((line) => ({
      lineId: line.id,
      tax: String((BigInt(line.total) * 21n) / 100n),
    }));

    const totalTax = lines.reduce((sum, line) => sum + BigInt(line.tax), 0n);

    return call<Order>("better_supabase.place_order($1, $2, $3, null)", [
      cartId,
      JSON.stringify({
        provider: "test",
        quoteId: "q1",
        currency: "EUR",
        inclusive: false,
        totalTax: String(totalTax),
        lines,
      }),
      totals.total,
    ]);
  };

  const pay = (
    order: Order,
    reference = `pay_${order.id}`,
  ): Promise<{
    readonly status: string;
    readonly newlyPaid: boolean;
    readonly invoiceNumber: string | null;
  }> =>
    call(
      "better_supabase.record_payment($1, 'test', $2, 'succeeded', 'EUR', $3, $3, 0)",
      [order.id, reference, order.total],
    );

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      [
        "organizations",
        "catalog",
        "inventory",
        "outbox",
        "number-sequences",
        "orders",
      ],
      {
        modules: {
          "number-sequences": {
            options: {
              entities: {
                order: { period: "none", format: "SO-{n:4}" },
                invoice: { period: "none", format: "INV-{n:5}" },
              },
            },
          },
        },
      },
    );
    owner = await session.user("orders-owner");
    member = await session.user("orders-member");
    shopper = await session.user("orders-shopper");
    stranger = await session.user("orders-stranger");
    tenant = await session.organization(owner, { member });
    await session.as(owner);
    warehouse = (
      await call<{ id: string }>(
        "better_supabase.save_location($1, null, 'WH-1', 'Warehouse', 'warehouse')",
        [tenant],
      )
    ).id;
    tee = await variant("TEE", "2000");
    mug = await variant("MUG", "1000");
    preorder = await variant("PRE", "5000", true);
    await call("better_supabase.adjust_stock($1, $2, 10, 'receipt', null)", [
      tee,
      warehouse,
    ]);
    await call("better_supabase.adjust_stock($1, $2, 1, 'receipt', null)", [
      mug,
      warehouse,
    ]);
    flat = (
      await call<{ id: string }>(
        "better_supabase.save_shipping_rate($1, null, $2)",
        [
          tenant,
          JSON.stringify({
            name: "Standard",
            countries: ["NL", "BE"],
            currency: "EUR",
            kind: "flat",
            amount: "495",
            freeOver: "10000",
          }),
        ],
      )
    ).id;
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("prices a cart from the catalog with shipping", async () => {
    const id = await cart(shopper, [
      [tee, 2],
      [mug, 1],
    ]);

    const totals = await call<Totals>("better_supabase.price_cart($1)", [id]);
    expect(totals).toMatchObject({
      subtotal: "5000",
      shippingTotal: "495",
      total: "5495",
      problems: [],
    });
    await call("better_supabase.add_to_cart($1, $2, 3)", [id, tee]);
    expect(
      (await call<Totals>("better_supabase.price_cart($1)", [id])).shipping,
    ).toMatchObject({ amount: "0" });
    await call("better_supabase.set_cart_line($1, $2, 0)", [id, tee]);
    expect(
      (await call<Totals>("better_supabase.price_cart($1)", [id])).lines,
    ).toHaveLength(1);

    const options = await call<{ id: string }[]>(
      "better_supabase.shipping_options($1)",
      [id],
    );

    expect(options.map((option) => option.id)).toEqual([flat]);
  });

  it("keeps carts private to their owner", async () => {
    const id = await cart(shopper, [[tee, 1]]);
    await session.as(stranger);
    expect(await session.hint("better_supabase.price_cart($1)", [id])).toBe(
      "ORDERS_CART_NOT_FOUND",
    );
    expect(
      await session.hint("better_supabase.add_to_cart($1, $2, 1)", [id, tee]),
    ).toBe("ORDERS_CART_NOT_FOUND");
    await session.asRole(stranger);
    expect(
      await session.rows("select id from better_supabase.carts where id = $1", [
        id,
      ]),
    ).toEqual([]);
    await session.as(owner);
  });

  it("places an order, reserves stock and refuses a changed total", async () => {
    const id = await cart(shopper, [
      [tee, 2],
      [preorder, 1],
    ]);

    await session.service();
    const totals = await call<Totals>("better_supabase.price_cart($1)", [id]);
    expect(
      await session.hint("better_supabase.place_order($1, null, $2, null)", [
        id,
        Number(totals.total) - 1,
      ]),
    ).toBe("ORDERS_PRICE_CHANGED");
    expect(
      await session.hint("better_supabase.place_order($1, $2, null, null)", [
        id,
        JSON.stringify({ totalTax: "10", lines: [{ lineId: "x", tax: "9" }] }),
      ]),
    ).toBe("ORDERS_TAX_INVALID");
    const before = await available(tee);
    const order = await place(id);
    expect(order).toMatchObject({
      number: expect.stringMatching(/^SO-\d{4}$/),
      status: "pending_payment",
      created: true,
    });
    expect(BigInt(order.total)).toBe(
      BigInt(totals.total) + BigInt(order.taxTotal),
    );
    expect(await available(tee)).toBe(before - 2);
    const teeLine = line(order, "TEE");
    const preLine = line(order, "PRE");
    expect(teeLine.reservationId).not.toBeNull();
    expect(preLine).toMatchObject({ backordered: true });
    expect(teeLine.backordered).toBe(false);
    expect((await place(id)).created).toBe(false);
    expect((await events("order.placed")).at(-1)).toMatchObject({
      id: order.id,
      subjectType: "order",
      units: "3",
      total: order.total,
    });
    expect(
      await session.hint("better_supabase.add_to_cart($1, $2, 1)", [id, tee]),
    ).toBe("ORDERS_CART_CLOSED");
  });

  it("refuses a strict variant without stock", async () => {
    const id = await cart(shopper, [[mug, 2]]);
    await session.service();
    expect(
      await session.hint(
        "select better_supabase.place_order($1, null, null, null)",
        [id],
      ),
    ).toBe("INVENTORY_INSUFFICIENT");
  });

  it("marks an order paid once, with an invoice number and stock taken", async () => {
    const order = await place(await cart(shopper, [[tee, 1]]));

    const onHand = async (): Promise<number> =>
      (
        await session.rows<{ on_hand: number }>(
          "select on_hand from better_supabase.stock_levels where variant_id = $1 and location_id = $2",
          [tee, warehouse],
        )
      )[0]!.on_hand;

    const before = await onHand();
    const paid = await pay(order);
    expect(paid).toMatchObject({
      status: "paid",
      newlyPaid: true,
      invoiceNumber: expect.stringMatching(/^INV-\d{5}$/),
    });
    expect(await onHand()).toBe(before - 1);
    const again = await pay(order);
    expect(again).toMatchObject({
      newlyPaid: false,
      invoiceNumber: paid.invoiceNumber,
    });
    await call(
      "better_supabase.record_payment(null, 'test', $1, 'processing', 'EUR', $2, 0, 0)",
      [`pay_${order.id}`, order.total],
    );
    expect(
      (
        await session.rows<{ status: string }>(
          "select status from better_supabase.order_payments where reference = $1",
          [`pay_${order.id}`],
        )
      )[0]?.status,
    ).toBe("succeeded");
    expect(
      (await events("order.paid")).filter((event) => event["id"] === order.id),
    ).toHaveLength(1);
    expect(
      await session.hint(
        "better_supabase.record_payment($1, 'test', 'x', 'succeeded', 'USD', 1, 1, 0)",
        [order.id],
      ),
    ).toBe("ORDERS_CURRENCY_MISMATCH");
  });

  it("cancels and expires unpaid orders, releasing their stock", async () => {
    const before = await available(tee);
    const order = await place(await cart(shopper, [[tee, 1]]));
    expect(await available(tee)).toBe(before - 1);
    await session.as(stranger);
    expect(
      await session.hint("better_supabase.cancel_order($1, null)", [order.id]),
    ).toBe("ORDERS_ORDER_NOT_FOUND");
    await session.as(shopper);
    expect(
      await call("better_supabase.cancel_order($1, 'changed my mind')", [
        order.id,
      ]),
    ).toBe(true);
    expect(await available(tee)).toBe(before);
    expect((await events("order.cancelled")).at(-1)).toMatchObject({
      id: order.id,
      reason: "changed my mind",
    });
    const stale = await place(await cart(shopper, [[tee, 1]]));
    await session.service();
    await session.client.query(
      "update better_supabase.orders set placed_at = now() - interval '1 hour' where id = $1",
      [stale.id],
    );
    expect(
      await call("better_supabase.expire_orders(10)"),
    ).toBeGreaterThanOrEqual(1);
    expect(
      (await call<Order>("better_supabase.get_order($1)", [stale.id])).status,
    ).toBe("cancelled");
  });

  it("fulfills, returns and refunds a paid order", async () => {
    const order = await place(
      await cart(shopper, [
        [tee, 2],
        [mug, 1],
      ]),
    );

    await pay(order);
    await session.as(member);
    expect(
      await session.hint(
        "better_supabase.create_fulfillment($1, null, null, null, null, null)",
        [order.id],
      ),
    ).toBe("ORDERS_FORBIDDEN");
    await session.as(owner);
    const teeLine = line(order, "TEE");
    const mugLine = line(order, "MUG");

    const first = await call<{ id: string }>(
      "better_supabase.create_fulfillment($1, $2, null, null, null, null)",
      [order.id, JSON.stringify([{ lineId: teeLine.id, quantity: 2 }])],
    );

    expect(
      await session.hint(
        "better_supabase.create_fulfillment($1, $2, null, null, null, null)",
        [order.id, JSON.stringify([{ lineId: teeLine.id, quantity: 1 }])],
      ),
    ).toBe("ORDERS_FULFILLMENT_INVALID");

    const second = await call<{ id: string }>(
      "better_supabase.create_fulfillment($1, null, null, 'PostNL', null, null)",
      [order.id],
    );

    expect(
      await call(
        "better_supabase.ship_fulfillment($1, 'DHL', '3S123', 'https://track.example/3S123')",
        [first.id],
      ),
    ).toBe(true);
    expect(
      (await call<Order>("better_supabase.get_order($1)", [order.id])).status,
    ).toBe("paid");
    await call("better_supabase.ship_fulfillment($1, null, null, null)", [
      second.id,
    ]);
    expect(
      (await call<Order>("better_supabase.get_order($1)", [order.id])).status,
    ).toBe("fulfilled");
    await call("better_supabase.deliver_fulfillment($1)", [first.id]);
    await call("better_supabase.deliver_fulfillment($1)", [second.id]);
    expect(
      (await call<Order>("better_supabase.get_order($1)", [order.id])).status,
    ).toBe("completed");
    expect((await events("fulfillment.shipped")).at(0)).toMatchObject({
      orderId: order.id,
      carrier: "DHL",
      trackingNumber: "3S123",
    });

    await session.as(shopper);
    expect(
      await session.hint("better_supabase.request_return($1, $2, null)", [
        order.id,
        JSON.stringify([{ lineId: mugLine.id, quantity: 2 }]),
      ]),
    ).toBe("ORDERS_RETURN_INVALID");

    const requested = await call<{ id: string; quantity: number }>(
      "better_supabase.request_return($1, $2, 'too small')",
      [order.id, JSON.stringify([{ lineId: teeLine.id, quantity: 1 }])],
    );

    expect(requested.quantity).toBe(1);

    const viewed = await call<Order>("better_supabase.get_order($1)", [
      order.id,
    ]);

    expect(viewed.lines).toHaveLength(2);
    await session.as(owner);
    const before = await available(tee);
    expect(
      await call("better_supabase.receive_return($1, true, null)", [
        requested.id,
      ]),
    ).toBe(true);
    expect(await available(tee)).toBe(before + 1);

    const partial = await call<{
      id: string;
      amount: string;
      paymentReference: string;
    }>("better_supabase.create_refund($1, 2000, $2, 'return')", [
      order.id,
      requested.id,
    ]);

    expect(partial).toMatchObject({
      amount: "2000",
      paymentReference: `pay_${order.id}`,
    });
    expect(
      await session.hint("better_supabase.create_refund($1, $2, null, null)", [
        order.id,
        order.total,
      ]),
    ).toBe("ORDERS_REFUND_INVALID");
    await session.service();
    expect(
      await call("better_supabase.complete_refund($1, 'succeeded', 're_1')", [
        partial.id,
      ]),
    ).toMatchObject({
      status: "succeeded",
      orderStatus: "completed",
      refundedTotal: "2000",
    });
    await call("better_supabase.complete_refund($1, 'succeeded', 're_1')", [
      partial.id,
    ]);
    await session.as(owner);

    const rest = await call<{ id: string; amount: string }>(
      "better_supabase.create_refund($1, null, null, null)",
      [order.id],
    );

    expect(BigInt(rest.amount)).toBe(BigInt(order.total) - 2000n);
    await session.service();
    expect(
      await call("better_supabase.complete_refund($1, 'succeeded', null)", [
        rest.id,
      ]),
    ).toMatchObject({ orderStatus: "refunded" });
    expect(
      (await events("order.refunded")).filter(
        (event) => event["id"] === order.id,
      ),
    ).toHaveLength(2);
  });

  it("shows orders to their customer and order readers only and keeps them from strangers", async () => {
    const order = await place(await cart(shopper, [[tee, 1]]));
    await session.as(owner);
    expect(
      (await call<Order>("better_supabase.get_order($1)", [order.id])).id,
    ).toBe(order.id);
    await session.as(member);
    expect(
      await session.hint("better_supabase.get_order($1)", [order.id]),
    ).toBe("ORDERS_ORDER_NOT_FOUND");
    await session.as(stranger);
    expect(
      await session.hint("better_supabase.get_order($1)", [order.id]),
    ).toBe("ORDERS_ORDER_NOT_FOUND");
    await session.asRole(shopper);
    expect(
      await session.rows(
        "select id from better_supabase.orders where id = $1",
        [order.id],
      ),
    ).toHaveLength(1);
    await session.asRole(stranger);
    expect(
      await session.rows(
        "select id from better_supabase.order_lines where order_id = $1",
        [order.id],
      ),
    ).toEqual([]);
    await session.as(owner);
  });

  it("merges a guest cart into the signed-in account", async () => {
    const guest = await session.user("orders-guest");
    const from = await cart(guest, [[tee, 1]]);
    const into = await cart(shopper, [[mug, 1]]);
    await session.service();
    expect(
      await call("better_supabase.merge_carts($1, $2)", [guest.id, shopper.id]),
    ).toBe(1);
    const totals = await call<Totals>("better_supabase.price_cart($1)", [into]);
    expect(totals.lines).toHaveLength(2);
    expect(
      await session.hint("better_supabase.add_to_cart($1, $2, 1)", [from, tee]),
    ).toBe("ORDERS_CART_CLOSED");
  });
});
