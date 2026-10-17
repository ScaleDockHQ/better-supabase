import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createOrders, sqlTransport } from "../../src/blocks/orders/index.ts";
import {
  fixedRates,
  money,
  type Payment,
  type PaymentProvider,
} from "../../src/commerce/index.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

const ADDRESS = { country: "NL", city: "Amsterdam", line1: "Dam 1" };

let providers = 0;

/** A payment provider that settles at once and keeps its payments in memory. */
function fakePayments(): PaymentProvider & {
  readonly created: Map<string, Payment>;
} {
  providers += 1;
  const prefix = `pi_${String(providers)}_`;
  const created = new Map<string, Payment>();
  const byKey = new Map<string, Payment>();
  let refunds = 0;

  return {
    apiVersion: 1,
    name: "fake",
    created,
    createPayment(input, options) {
      const key = options?.idempotencyKey ?? "";
      const existing = byKey.get(key);

      if (existing) {
        return AsyncResult.ok(existing);
      }

      const payment: Payment = {
        id: `${prefix}${String(created.size + 1)}`,
        provider: "fake",
        status: input.capture === "manual" ? "authorized" : "succeeded",
        amount: input.amount,
        captured:
          input.capture === "manual"
            ? money(0, input.amount.currency)
            : input.amount,
        refunded: money(0, input.amount.currency),
        reference: input.reference,
        clientSecret: "secret",
        metadata: input.metadata ?? {},
      };

      created.set(payment.id, payment);
      byKey.set(key, payment);

      return AsyncResult.ok(payment);
    },
    capture(paymentId) {
      const payment = created.get(paymentId)!;

      const captured = {
        ...payment,
        status: "succeeded" as const,
        captured: payment.amount,
      };

      created.set(paymentId, captured);

      return AsyncResult.ok(captured);
    },
    refund(paymentId, input) {
      refunds += 1;
      const payment = created.get(paymentId)!;

      return AsyncResult.ok({
        id: `re_${prefix}${String(refunds)}`,
        paymentId,
        amount: input?.amount ?? payment.captured,
        status: "succeeded",
      });
    },
    parseWebhook() {
      return AsyncResult.ok([]);
    },
  };
}

describe.skipIf(!live)("orders block in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let shopper: TestUser;
  let owner: TestUser;
  let tenant: string;
  let tee: string;
  let flat: string;
  let warehouse: string;

  /** Runs each call in a savepoint, as `role`, so a raised error doesn't end the test's transaction. */
  const transport = (role: () => Promise<void>): BlockTransport => {
    const inner = sqlTransport(session.sql);

    return {
      async call(schema, fn, args) {
        await role();
        await session.client.query("savepoint block_call");

        try {
          const value = await inner.call(schema, fn, args);
          await session.client.query("release savepoint block_call");

          return value;
        } catch (cause) {
          await session.client.query("rollback to savepoint block_call");
          throw cause;
        }
      },
    };
  };

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

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
    owner = await session.user("orders-block-owner");
    shopper = await session.user("orders-block-shopper");
    tenant = await session.organization(owner);
    await session.as(owner);

    const product = await call<{ id: string }>(
      "better_supabase.save_product($1, null, 'Tee', null, null, 'physical')",
      [tenant],
    );

    await call("better_supabase.set_product_status($1, 'active')", [
      product.id,
    ]);
    tee = (
      await call<{ id: string }>(
        "better_supabase.save_variant($1, null, 'TEE', '{}'::uuid[], null, null, 200, true, false)",
        [product.id],
      )
    ).id;
    await call(
      "better_supabase.set_price($1, 'EUR', '2000', null, null, null, null)",
      [tee],
    );
    warehouse = (
      await call<{ id: string }>(
        "better_supabase.save_location($1, null, 'WH', 'Warehouse', null)",
        [tenant],
      )
    ).id;
    await call("better_supabase.adjust_stock($1, $2, 10, 'receipt', null)", [
      tee,
      warehouse,
    ]);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("checks out, pays, ships, refunds and reverses the tax", async () => {
    const payments = fakePayments();
    const asOwner = () => session.as(owner);

    const admin = createOrders({
      transport: transport(asOwner),
      service: transport(() => session.service()),
    });

    flat = (
      await admin
        .saveShippingRate(tenant, {
          name: "Standard",
          countries: ["NL"],
          amount: money(495, "EUR"),
          freeOver: money(10_000, "EUR"),
        })
        .orThrow()
    ).id;

    const tax = fixedRates({ rates: { NL: { standard: "0.21" } } });

    const orders = createOrders({
      transport: transport(() => session.as(shopper)),
      service: transport(() => session.service()),
      payments,
      tax,
    });

    const cart = await orders
      .createCart(tenant, { currency: "EUR", email: shopper.email })
      .orThrow();

    await orders.addToCart(cart.id, tee, 2).orThrow();
    expect(
      await orders.checkout(cart.id).then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_CART_INVALID");
    expect(
      await orders
        .setCartDetails(cart.id, {
          shippingAddress: ADDRESS,
          billingAddress: ADDRESS,
        })
        .orThrow(),
    ).toBe(true);
    const options = await orders.shippingOptions(cart.id).orThrow();
    expect(options).toEqual([
      { id: flat, name: "Standard", kind: "flat", amount: money(495, "EUR") },
    ]);
    await orders.setShippingRate(cart.id, flat).orThrow();
    const priced = await orders.priceCart(cart.id).orThrow();
    expect(priced.total).toEqual(money(4495, "EUR"));
    expect(priced.problems).toEqual([]);

    const { order, payment } = await orders.checkout(cart.id).orThrow();
    expect(payment?.clientSecret).toBe("secret");
    expect(order.status).toBe("paid");
    expect(order.number).toBe("SO-0001");
    expect(order.invoiceNumber).toBe("INV-00001");
    // 21% of 4000 plus 21% of 495
    expect(order.taxTotal).toEqual(money(944, "EUR"));
    expect(order.total).toEqual(money(5439, "EUR"));
    expect(order.taxTransaction?.reference).toBe("SO-0001");
    expect(order.lines[0]?.reservationId).not.toBeNull();

    const again = await orders.checkout(cart.id).orThrow();
    expect(again.order.id).toBe(order.id);
    expect(payments.created.size).toBe(1);

    expect((await orders.invoice(order.id).orThrow()).number).toBe("INV-00001");
    const fulfillment = await admin.createFulfillment(order.id).orThrow();
    await admin
      .shipFulfillment(fulfillment.id, { carrier: "PostNL" })
      .orThrow();
    await admin.deliverFulfillment(fulfillment.id).orThrow();
    expect((await admin.getOrder(order.id).orThrow()).status).toBe("completed");

    const returned = await orders
      .requestReturn(order.id, [{ lineId: order.lines[0]!.id, quantity: 1 }])
      .orThrow();

    expect(returned.quantity).toBe(1);
    await admin.receiveReturn(returned.id).orThrow();

    const refunder = createOrders({
      transport: transport(asOwner),
      service: transport(() => session.service()),
      payments,
      tax,
    });

    const refund = await refunder
      .refund(order.id, { amount: money(2420, "EUR"), returnId: returned.id })
      .orThrow();

    expect(refund.status).toBe("succeeded");
    expect(refund.orderStatus).toBe("completed");
    expect(refund.refundedTotal).toEqual(money(2420, "EUR"));
    expect(refund.taxReversal?.totalTax.amount).toBeLessThan(0n);

    const rest = await refunder.refund(order.id).orThrow();
    expect(rest.amount).toEqual(money(3019, "EUR"));
    expect(rest.orderStatus).toBe("refunded");
  });

  it("handles a manual capture and a refund webhook", async () => {
    const payments = fakePayments();

    const orders = createOrders({
      transport: transport(() => session.as(shopper)),
      service: transport(() => session.service()),
      payments,
      capture: "manual",
    });

    const cart = await orders.createCart(tenant, { currency: "EUR" }).orThrow();
    await orders.setCartLine(cart.id, tee, 1).orThrow();
    await orders
      .setCartDetails(cart.id, { shippingAddress: ADDRESS })
      .orThrow();
    await orders.setShippingRate(cart.id, flat).orThrow();
    const { order } = await orders.checkout(cart.id).orThrow();
    expect(order.status).toBe("pending_payment");
    expect(order.payments[0]?.status).toBe("authorized");

    const captured = await orders.capture(order.id).orThrow();
    expect(captured.status).toBe("paid");

    const outcome = await orders
      .handlePaymentEvent({
        id: "evt_1",
        type: "refund.succeeded",
        paymentId: "pi_1",
        refundId: "re_unknown",
        occurredAt: Temporal.Now.instant(),
      })
      .orThrow();

    expect(outcome.kind).toBe("ignored");
  });

  it("cancels an unpaid order", async () => {
    const orders = createOrders({
      transport: transport(() => session.as(shopper)),
      service: transport(() => session.service()),
    });

    const cart = await orders.createCart(tenant, { currency: "EUR" }).orThrow();
    await orders.setCartLine(cart.id, tee, 1).orThrow();
    await orders
      .setCartDetails(cart.id, { shippingAddress: ADDRESS })
      .orThrow();
    await orders.setShippingRate(cart.id, flat).orThrow();
    const { order, payment } = await orders.checkout(cart.id).orThrow();
    expect(payment).toBeNull();
    expect(await orders.cancelOrder(order.id, "changed mind").orThrow()).toBe(
      true,
    );
    expect(await orders.cancelOrder(order.id).orThrow()).toBe(false);
    expect(
      await orders.invoice(order.id).then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_NOT_INVOICED");
  });
});
