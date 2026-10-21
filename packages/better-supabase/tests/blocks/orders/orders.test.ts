import * as v from "valibot";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import {
  createOrders,
  type OrdersOptions,
} from "../../../src/blocks/orders/index.ts";
import {
  fixedRates,
  money,
  type Money,
  type Payment,
  type PaymentProvider,
  type TaxProvider,
} from "../../../src/commerce/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";

type Handler = (args: Record<string, unknown>) => unknown;

/** A transport that answers each function with a handler and records the calls. */
function router(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    fns: () => calls.map((call) => call.fn),
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        const handler = handlers[fn];

        if (!handler) {
          return Promise.reject(new Error(`unexpected ${fn}`));
        }

        try {
          return Promise.resolve(handler(args));
        } catch (cause) {
          return Promise.reject(cause);
        }
      },
    },
  };
}

const raise = (hint: string) => () => {
  throw Object.assign(new Error(hint), { code: "P0001", hint });
};

const ADDRESS = { country: "NL", city: "Amsterdam", line1: "Dam 1" };

const cartRow = (overrides: Record<string, unknown> = {}) => ({
  cartId: "c1",
  organizationId: "org",
  customerId: "u1",
  status: "open",
  email: "a@example.test",
  shippingAddress: { ...ADDRESS, ignored: 1 },
  billingAddress: null,
  currency: "EUR",
  lines: [
    {
      id: "l1",
      variantId: "v1",
      productId: "p1",
      sku: "TEE",
      title: "Tee",
      quantity: 2,
      unitAmount: "2000",
      previousUnitAmount: "1900",
      subtotal: "4000",
      discount: "400",
      total: "3600",
      requiresShipping: true,
    },
  ],
  subtotal: "4000",
  discountTotal: "400",
  shippingTotal: "495",
  total: "4095",
  requiresShipping: true,
  weightGrams: "400",
  shipping: { rateId: "r1", name: "Standard", amount: "495" },
  promotions: [
    {
      promotionId: "pr1",
      name: "Ten off",
      kind: "fixed",
      code: "TEN",
      amount: "400",
    },
  ],
  problems: [],
  ...overrides,
});

const orderRow = (overrides: Record<string, unknown> = {}) => ({
  id: "o1",
  organizationId: "org",
  number: "SO-0001",
  cartId: "c1",
  customerId: "u1",
  email: "a@example.test",
  status: "pending_payment",
  currency: "EUR",
  subtotal: "4000",
  discountTotal: "400",
  shippingTotal: "495",
  taxTotal: "860",
  total: "4955",
  paidTotal: "0",
  refundedTotal: "0",
  taxInclusive: false,
  shippingAddress: ADDRESS,
  billingAddress: ADDRESS,
  shipping: { rateId: "r1", name: "Standard", amount: "495" },
  promotions: [],
  tax: {
    provider: "fixed-rates",
    quoteId: "q1",
    currency: "EUR",
    inclusive: false,
    totalTax: "860",
    expiresAt: "2026-10-14T12:00:00Z",
    lines: [
      {
        lineId: "l1",
        taxable: "3600",
        tax: "756",
        rate: "0.21",
        inclusive: false,
        jurisdiction: "NL",
        taxCategory: "standard",
      },
      {
        lineId: "shipping",
        taxable: "495",
        tax: "104",
        rate: "0.21",
        inclusive: false,
      },
    ],
  },
  taxTransaction: null,
  invoiceNumber: null,
  invoicedAt: null,
  placedAt: "2026-10-14T10:00:00Z",
  paidAt: null,
  fulfilledAt: null,
  completedAt: null,
  cancelledAt: null,
  cancelReason: null,
  lines: [
    {
      id: "l1",
      variantId: "v1",
      productId: "p1",
      sku: "TEE",
      title: "Tee",
      quantity: 2,
      unitAmount: "2000",
      subtotal: "4000",
      discount: "400",
      tax: "756",
      total: "3600",
      requiresShipping: true,
      locationId: "w1",
      reservationId: "res1",
      fulfilled: 0,
      returned: 0,
      backordered: false,
    },
  ],
  payments: [],
  fulfillments: [],
  returns: [],
  refunds: [],
  ...overrides,
});

const PAY1 = {
  id: "pay1",
  provider: "fake",
  reference: "pi_1",
  status: "succeeded",
  amount: "4955",
  captured: "4955",
  refunded: "0",
  createdAt: "2026-10-14T10:01:00Z",
};

const paid = (overrides: Record<string, unknown> = {}) =>
  orderRow({
    status: "paid",
    paidTotal: "4955",
    invoiceNumber: "INV-00001",
    invoicedAt: "2026-10-14T10:05:00Z",
    paidAt: "2026-10-14T10:05:00Z",
    taxTransaction: {
      id: "tx1",
      reference: "SO-0001",
      currency: "EUR",
      totalTax: "860",
      lines: [
        {
          lineId: "l1",
          taxable: "3600",
          tax: "756",
          rate: "0.21",
          inclusive: false,
        },
        {
          lineId: "shipping",
          taxable: "495",
          tax: "104",
          rate: "0.21",
          inclusive: false,
        },
      ],
    },
    payments: [PAY1],
    fulfillments: [
      {
        id: "f1",
        status: "shipped",
        locationId: "w1",
        carrier: "PostNL",
        trackingNumber: "3S",
        trackingUrl: null,
        createdAt: "2026-10-14T11:00:00Z",
        shippedAt: "2026-10-14T12:00:00Z",
        deliveredAt: null,
        lines: [{ lineId: "l1", quantity: 2 }],
      },
    ],
    returns: [
      {
        id: "ret1",
        status: "received",
        reason: "too small",
        createdAt: "2026-10-15T10:00:00Z",
        receivedAt: "2026-10-16T10:00:00Z",
        lines: [{ lineId: "l1", quantity: 1 }],
      },
    ],
    refunds: [
      {
        id: "rf0",
        paymentId: "pay1",
        returnId: null,
        amount: "100",
        status: "failed",
        reason: null,
        providerReference: null,
        createdAt: "2026-10-15T10:00:00Z",
        completedAt: "2026-10-15T10:00:01Z",
      },
    ],
    ...overrides,
  });

const payment = (overrides: Partial<Payment> = {}): Payment => ({
  id: "pi_1",
  provider: "fake",
  status: "succeeded",
  amount: money(4955, "EUR"),
  captured: money(4955, "EUR"),
  refunded: money(0, "EUR"),
  reference: "o1",
  clientSecret: "secret",
  metadata: {},
  ...overrides,
});

function paymentSpies(overrides: Partial<PaymentProvider> = {}) {
  const spies = {
    createPayment: vi.fn(() => AsyncResult.ok(payment())),
    capture: vi.fn(() => AsyncResult.ok(payment())),
    refund: vi.fn((paymentId: string, input?: { amount?: Money }) =>
      AsyncResult.ok({
        id: "re_1",
        paymentId,
        amount: input?.amount ?? money(0, "EUR"),
        status: "succeeded" as const,
      }),
    ),
  };

  const provider: PaymentProvider = {
    apiVersion: 1,
    name: "fake",
    ...spies,
    parseWebhook: vi.fn(() => AsyncResult.ok([])),
    ...overrides,
  };

  return { provider, spies };
}

const fakePayments = (
  overrides: Partial<PaymentProvider> = {},
): PaymentProvider => paymentSpies(overrides).provider;

const TAX = fixedRates({ rates: { NL: { standard: "0.21" } } });

const recordRow = (newlyPaid: boolean, status = "paid") => ({
  orderId: "o1",
  status,
  paidTotal: "4955",
  newlyPaid,
  invoiceNumber: newlyPaid ? "INV-00001" : null,
});

function orders(
  handlers: Record<string, Handler>,
  options: Partial<OrdersOptions> = {},
) {
  const route = router(handlers);

  const logger = {
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  };

  return {
    ...route,
    logger,
    orders: createOrders({ transport: route.transport, logger, ...options }),
  };
}

describe("orders block", () => {
  it("manages shipping rates and carts", async () => {
    const { orders: o, calls } = orders({
      save_shipping_rate: () => ({ id: "r1" }),
      delete_shipping_rate: () => true,
      create_cart: () => ({ id: "c1", currency: "EUR", status: "open" }),
      add_to_cart: () => ({ lineId: "l1", quantity: 2 }),
      set_cart_line: () => ({ lineId: null, quantity: 0 }),
      set_cart_details: () => true,
      set_cart_shipping_rate: () => true,
      shipping_options: () => [
        {
          id: "r1",
          name: "Standard",
          kind: "weight",
          currency: "EUR",
          amount: "695",
        },
      ],
      price_cart: () => cartRow(),
      merge_carts: () => 1,
    });

    expect(
      await o
        .saveShippingRate("org", {
          name: "Standard",
          countries: ["NL"],
          kind: "weight",
          amount: money(495, "EUR"),
          amountPerKg: money(100, "EUR"),
          freeOver: money(10_000, "EUR"),
        })
        .orThrow(),
    ).toEqual({ id: "r1" });
    await o
      .saveShippingRate("org", {
        id: "r1",
        name: "Pickup",
        amount: money(0, "EUR"),
        active: false,
      })
      .orThrow();
    expect(calls[0]?.args).toEqual({
      tenant: "org",
      rate: null,
      data: {
        name: "Standard",
        countries: ["NL"],
        kind: "weight",
        currency: "EUR",
        amount: "495",
        amountPerKg: "100",
        freeOver: "10000",
        active: true,
      },
    });
    expect(calls[1]?.args["data"]).toEqual({
      name: "Pickup",
      countries: [],
      kind: "flat",
      currency: "EUR",
      amount: "0",
      active: false,
    });
    expect(await o.deleteShippingRate("r1").orThrow()).toBe(true);
    expect(
      await o
        .createCart("org", {
          currency: "EUR",
          email: "a@example.test",
          priceListId: "pl",
        })
        .orThrow(),
    ).toEqual({ id: "c1", currency: "EUR" });
    await o.createCart("org", { currency: "EUR" }).orThrow();
    expect(await o.addToCart("c1", "v1", 2).orThrow()).toEqual({
      lineId: "l1",
      quantity: 2,
    });
    expect(await o.setCartLine("c1", "v1", 0).orThrow()).toEqual({
      lineId: null,
      quantity: 0,
    });
    await o
      .setCartDetails("c1", {
        email: "b@example.test",
        shippingAddress: ADDRESS,
      })
      .orThrow();
    await o.setCartDetails("c1", {}).orThrow();
    expect(calls.at(-1)?.args).toEqual({
      cart: "c1",
      email: null,
      shipping_address: null,
      billing_address: null,
    });
    await o.setShippingRate("c1", "r1").orThrow();
    expect(await o.shippingOptions("c1").orThrow()).toEqual([
      { id: "r1", name: "Standard", kind: "weight", amount: money(695, "EUR") },
    ]);
    const priced = await o.priceCart("c1").orThrow();
    expect(priced.shippingAddress).toEqual(ADDRESS);
    expect(priced.billingAddress).toBeUndefined();
    expect(priced.lines[0]?.previousUnitAmount).toEqual(money(1900, "EUR"));
    expect(priced.promotions[0]?.code).toBe("TEN");
    expect(priced.shipping?.amount).toEqual(money(495, "EUR"));
    expect(await o.mergeCarts("anon", "u1").orThrow()).toBe(1);
  });

  it("decodes a sparse cart", async () => {
    const { orders: o } = orders({
      price_cart: () =>
        cartRow({
          email: null,
          shippingAddress: null,
          shipping: null,
          promotions: null,
          problems: [
            { problem: "unpriced", lineId: "l1", variantId: "v1", code: null },
            "junk",
          ],
          weightGrams: null,
          lines: [{ ...cartRow().lines[0], previousUnitAmount: "2000" }],
        }),
    });

    const priced = await o.priceCart("c1").orThrow();
    expect(priced.email).toBeUndefined();
    expect(priced.shipping).toBeUndefined();
    expect(priced.promotions).toEqual([]);
    expect(priced.weightGrams).toBe(0);
    expect(priced.problems).toEqual([
      { problem: "unpriced", lineId: "l1", variantId: "v1" },
    ]);
    expect(priced.lines[0]?.previousUnitAmount).toBeUndefined();
  });

  it("checks out: quotes tax, places, pays and commits the tax", async () => {
    const { provider: payments, spies } = paymentSpies();
    let order = orderRow();

    const {
      orders: o,
      calls,
      fns,
    } = orders(
      {
        price_cart: () => cartRow(),
        place_order: () => order,
        record_payment: () => {
          order = paid({ taxTransaction: null });

          return recordRow(true);
        },
        get_order: () => order,
        set_order_tax_transaction: () => {
          order = paid();

          return true;
        },
      },
      {
        payments,
        tax: TAX,
        taxCategory: (line) => (line.sku === "TEE" ? "standard" : undefined),
        shippingTaxCategory: "standard",
      },
    );

    const result = await o
      .checkout("c1", {
        customer: "cus_1",
        returnUrl: "https://shop.test/done",
        locationId: "w1",
        metadata: { channel: "web" },
      })
      .orThrow();

    expect(result.payment?.clientSecret).toBe("secret");
    expect(result.order.status).toBe("paid");
    expect(result.order.taxTransaction?.id).toBe("tx1");
    expect(result.order.fulfillments[0]?.shippedAt?.toString()).toBe(
      "2026-10-14T12:00:00Z",
    );
    expect(result.order.returns[0]?.receivedAt).toBeDefined();
    expect(result.order.refunds[0]?.completedAt).toBeDefined();
    expect(result.order.taxQuote?.expiresAt?.toString()).toBe(
      "2026-10-14T12:00:00Z",
    );
    expect(fns()).toEqual([
      "price_cart",
      "place_order",
      "record_payment",
      "get_order",
      "set_order_tax_transaction",
      "get_order",
    ]);
    const place = calls[1]?.args;
    expect(place?.["expected_total"]).toBe("4095");
    expect(place?.["location"]).toBe("w1");
    expect(place?.["tax"]).toMatchObject({
      provider: "fixed-rates",
      currency: "EUR",
      inclusive: false,
      totalTax: "860",
    });
    expect(spies.createPayment).toHaveBeenCalledWith(
      expect.objectContaining({
        amount: money(4955, "EUR"),
        reference: "o1",
        capture: "automatic",
        customer: "cus_1",
        returnUrl: "https://shop.test/done",
        description: "Order SO-0001",
        metadata: { channel: "web", orderId: "o1", orderNumber: "SO-0001" },
      }),
      { idempotencyKey: "order:o1:payment" },
    );
    expect(calls[2]?.args).toEqual({
      order_id: "o1",
      provider: "fake",
      reference: "pi_1",
      status: "succeeded",
      currency: "EUR",
      amount: "4955",
      captured: "4955",
      refunded: "0",
    });
  });

  it("quotes tax-inclusive prices from the billing address", async () => {
    const quote = vi.fn((...args: Parameters<TaxProvider["quote"]>) =>
      TAX.quote(...args),
    );

    const tax: TaxProvider = { ...TAX, quote };

    const { orders: o } = orders(
      {
        price_cart: () =>
          cartRow({
            shippingAddress: null,
            billingAddress: {
              country: "NL",
              state: "NH",
              postalCode: "1012",
              city: "Amsterdam",
              line2: "2",
            },
            shippingTotal: "0",
          }),
        place_order: () => orderRow({ status: "paid" }),
      },
      { tax, pricesIncludeTax: true, taxCategory: "standard" },
    );

    const result = await o.checkout("c1").orThrow();
    expect(result.payment).toBeNull();
    expect(quote.mock.calls[0]?.[0]).toMatchObject({
      address: {
        country: "NL",
        state: "NH",
        postalCode: "1012",
        city: "Amsterdam",
        line2: "2",
      },
      lines: [{ id: "l1", taxCategory: "standard", inclusive: true }],
    });
    expect(quote.mock.calls[0]?.[0].shipping).toBeUndefined();
  });

  it("refuses carts that can't check out", async () => {
    const hint = (o: ReturnType<typeof orders>["orders"]) =>
      o.checkout("c1").then((r) => !r.ok && r.error.hint);

    expect(
      await hint(orders({ price_cart: () => cartRow({ lines: [] }) }).orders),
    ).toBe("ORDERS_CART_EMPTY");
    expect(
      await hint(
        orders({
          price_cart: () =>
            cartRow({ problems: [{ problem: "shipping_required" }] }),
        }).orders,
      ),
    ).toBe("ORDERS_CART_INVALID");
    expect(
      await hint(
        orders(
          { price_cart: () => cartRow({ shippingAddress: null }) },
          { tax: TAX },
        ).orders,
      ),
    ).toBe("ORDERS_ADDRESS_REQUIRED");
    expect(
      await hint(orders({ price_cart: raise("ORDERS_CART_NOT_FOUND") }).orders),
    ).toBe("ORDERS_CART_NOT_FOUND");
    expect(
      await hint(
        orders(
          { price_cart: () => cartRow({ shippingAddress: { country: "US" } }) },
          { tax: TAX },
        ).orders,
      ),
    ).not.toBe(false);
    expect(
      await hint(
        orders({
          price_cart: () => cartRow(),
          place_order: raise("ORDERS_PRICE_CHANGED"),
        }).orders,
      ),
    ).toBe("ORDERS_PRICE_CHANGED");
  });

  it("returns the order of a converted cart without a new quote", async () => {
    const { orders: o, fns } = orders(
      {
        price_cart: () =>
          cartRow({
            status: "converted",
            lines: [],
            problems: [{ problem: "closed" }],
          }),
        place_order: () => orderRow(),
      },
      { tax: TAX },
    );

    const result = await o.checkout("c1").orThrow();
    expect(result).toMatchObject({ payment: null, order: { id: "o1" } });
    expect(fns()).toEqual(["price_cart", "place_order"]);
  });

  it("records a free order as paid without a provider", async () => {
    const { orders: o, calls } = orders(
      {
        price_cart: () => cartRow(),
        place_order: () => orderRow({ total: "0" }),
        record_payment: () => recordRow(true),
        get_order: () => paid({ total: "0", tax: null, taxTransaction: null }),
      },
      { payments: fakePayments(), tax: TAX },
    );

    const result = await o.checkout("c1").orThrow();
    expect(result.payment).toBeNull();
    expect(calls[2]?.args).toMatchObject({
      provider: "none",
      reference: "free:o1",
      amount: "0",
    });
  });

  it("passes payment and lookup errors through", async () => {
    const declined = fakePayments({
      createPayment: () =>
        AsyncResult.err(
          dbError("raised", "declined", { hint: "PAYMENT_DECLINED" }),
        ),
    });

    const base = { price_cart: () => cartRow(), place_order: () => orderRow() };
    expect(
      await orders(base, { payments: declined })
        .orders.checkout("c1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("PAYMENT_DECLINED");
    expect(
      await orders(
        { ...base, record_payment: raise("ORDERS_PAYMENT_CONFLICT") },
        { payments: fakePayments() },
      )
        .orders.checkout("c1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_PAYMENT_CONFLICT");
    expect(
      await orders(
        {
          ...base,
          record_payment: () => recordRow(false, "pending_payment"),
          get_order: raise("ORDERS_ORDER_NOT_FOUND"),
        },
        { payments: fakePayments() },
      )
        .orders.checkout("c1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_ORDER_NOT_FOUND");
    expect(
      await orders({
        ...base,
        place_order: () => orderRow({ total: "0" }),
        record_payment: raise("ORDERS_AMOUNT_INVALID"),
      })
        .orders.checkout("c1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_AMOUNT_INVALID");
    expect(
      await orders({
        ...base,
        place_order: () => orderRow({ total: "0" }),
        record_payment: () => recordRow(false),
        get_order: raise("X"),
      })
        .orders.checkout("c1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("X");
  });

  it("logs a failed tax commit and retries it with commitTax", async () => {
    const tax: TaxProvider = {
      ...TAX,
      commit: () => AsyncResult.err(dbError("unexpected", "down")),
    };

    const { orders: o, logger } = orders(
      {
        price_cart: () => cartRow(),
        place_order: () => orderRow(),
        record_payment: () => recordRow(true),
        get_order: () => paid({ taxTransaction: null }),
      },
      { payments: fakePayments(), tax },
    );

    const result = await o.checkout("c1").orThrow();
    expect(result.order.taxTransaction).toBeUndefined();
    expect(logger.warn).toHaveBeenCalledWith(
      "orders: tax commit failed; retry with commitTax",
      expect.objectContaining({ orderId: "o1" }),
    );
    expect((await o.commitTax("o1")).ok).toBe(false);
  });

  it("commits tax only once there is a quote, an invoice and no transaction", async () => {
    let row = orderRow();

    const { orders: o, fns } = orders(
      {
        get_order: () => row,
        set_order_tax_transaction: raise("ORDERS_FORBIDDEN"),
      },
      { tax: TAX },
    );

    expect(await o.commitTax("o1").orThrow()).toBeNull();
    row = paid();
    expect((await o.commitTax("o1").orThrow())?.id).toBe("tx1");
    row = paid({ taxTransaction: null, tax: null });
    expect(await o.commitTax("o1").orThrow()).toBeNull();
    row = paid({ taxTransaction: null });
    expect(await o.commitTax("o1").then((r) => !r.ok && r.error.hint)).toBe(
      "ORDERS_FORBIDDEN",
    );
    expect(fns()).toContain("set_order_tax_transaction");
    expect(await orders({}).orders.commitTax("o1").orThrow()).toBeNull();
    expect(
      await orders({ get_order: raise("ORDERS_ORDER_NOT_FOUND") }, { tax: TAX })
        .orders.commitTax("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_ORDER_NOT_FOUND");
  });

  it("captures authorized payments", async () => {
    const { provider: payments, spies } = paymentSpies();

    let row = orderRow({
      payments: [
        { ...PAY1, status: "authorized", captured: "0" },
        { ...PAY1, id: "pay2", provider: "other", status: "authorized" },
      ],
    });

    const { orders: o } = orders(
      {
        get_order: () => row,
        record_payment: () => {
          row = paid();

          return recordRow(true);
        },
      },
      { payments, capture: "manual" },
    );

    expect((await o.capture("o1").orThrow()).status).toBe("paid");
    expect(spies.capture).toHaveBeenCalledExactlyOnceWith(
      "pi_1",
      {},
      { idempotencyKey: "capture:pay1" },
    );

    expect(
      await orders({})
        .orders.capture("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_NO_PAYMENTS");
    expect(
      await orders({ get_order: raise("ORDERS_ORDER_NOT_FOUND") }, { payments })
        .orders.capture("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_ORDER_NOT_FOUND");

    const failing = fakePayments({
      capture: () =>
        AsyncResult.err(dbError("not_found", "gone", { hint: "GONE" })),
    });

    const authorized = orderRow({
      payments: [{ ...PAY1, status: "authorized" }],
    });

    expect(
      await orders({ get_order: () => authorized }, { payments: failing })
        .orders.capture("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("GONE");
    expect(
      await orders(
        { get_order: () => authorized, record_payment: raise("NOPE") },
        { payments },
      )
        .orders.capture("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("NOPE");
  });

  it("refunds through the provider and reverses part of the tax", async () => {
    const reverse = vi.fn((...args: Parameters<TaxProvider["reverse"]>) =>
      TAX.reverse(...args),
    );

    const tax: TaxProvider = { ...TAX, reverse };
    const { provider: payments, spies } = paymentSpies();

    const { orders: o, calls } = orders(
      {
        create_refund: () => ({
          id: "rf1",
          orderId: "o1",
          paymentId: "pay1",
          provider: "fake",
          paymentReference: "pi_1",
          amount: "2000",
          currency: "EUR",
          status: "pending",
        }),
        complete_refund: () => ({
          id: "rf1",
          orderId: "o1",
          status: "succeeded",
          amount: "2000",
          orderStatus: "paid",
          refundedTotal: "2000",
        }),
        get_order: () => paid(),
      },
      { payments, tax },
    );

    const outcome = await o
      .refund("o1", {
        amount: money(2000, "EUR"),
        returnId: "ret1",
        reason: "too small",
      })
      .orThrow();

    expect(outcome).toMatchObject({
      id: "rf1",
      status: "succeeded",
      amount: money(2000, "EUR"),
      orderStatus: "paid",
      refundedTotal: money(2000, "EUR"),
    });
    expect(outcome.taxReversal?.totalTax.amount).toBeLessThan(0n);
    expect(calls[0]?.args).toEqual({
      order_id: "o1",
      amount: "2000",
      return_id: "ret1",
      reason: "too small",
    });
    expect(spies.refund).toHaveBeenCalledWith(
      "pi_1",
      { amount: money(2000, "EUR"), reason: "too small" },
      { idempotencyKey: "refund:rf1" },
    );
    expect(calls[1]?.args).toEqual({
      refund: "rf1",
      status: "succeeded",
      provider_reference: "re_1",
    });
    const lines = reverse.mock.calls[0]?.[0].lines;
    // 2000 of 4955: 3600 * 2000 / 4955 = 1453 and 756 * 2000 / 4955 = 305
    expect(lines?.[0]).toEqual({
      lineId: "l1",
      amount: money(1453, "EUR"),
      tax: money(305, "EUR"),
    });
    expect(reverse.mock.calls[0]?.[1]).toEqual({
      idempotencyKey: "tax-reverse:rf1",
    });
  });

  it("reverses all the tax on a full refund and logs a failed reversal", async () => {
    const reverse = vi.fn((...args: Parameters<TaxProvider["reverse"]>) =>
      TAX.reverse(...args),
    );

    const full = {
      create_refund: () => ({
        id: "rf1",
        paymentReference: "pi_1",
        amount: "4955",
        currency: "EUR",
      }),
      complete_refund: () => ({
        id: "rf1",
        orderId: "o1",
        status: "succeeded",
        amount: "4955",
        orderStatus: "refunded",
        refundedTotal: "4955",
      }),
      get_order: () => paid(),
    };

    await orders(full, { payments: fakePayments(), tax: { ...TAX, reverse } })
      .orders.refund("o1")
      .orThrow();
    expect(reverse.mock.calls[0]?.[0].lines).toBeUndefined();

    const broken = orders(full, {
      payments: fakePayments(),
      tax: {
        ...TAX,
        reverse: () => AsyncResult.err(dbError("unexpected", "down")),
      },
    });

    expect((await broken.orders.refund("o1").orThrow()).taxReversal).toBeNull();
    expect(broken.logger.warn).toHaveBeenCalledWith(
      "orders: tax reversal failed",
      expect.anything(),
    );

    const untaxed = orders(
      { ...full, get_order: () => paid({ taxTransaction: null }) },
      { payments: fakePayments(), tax: TAX },
    );

    expect(
      (await untaxed.orders.refund("o1").orThrow()).taxReversal,
    ).toBeNull();
    expect(
      (
        await orders(full, { payments: fakePayments() })
          .orders.refund("o1")
          .orThrow()
      ).taxReversal,
    ).toBeNull();
  });

  it("marks the refund failed when the provider refuses it", async () => {
    const payments = fakePayments({
      refund: () =>
        AsyncResult.err(
          dbError("invalid_input", "too much", { hint: "TOO_MUCH" }),
        ),
    });

    const { orders: o, calls } = orders(
      {
        create_refund: () => ({
          id: "rf1",
          paymentReference: "pi_1",
          amount: "10",
          currency: "EUR",
        }),
        complete_refund: () => ({
          id: "rf1",
          orderId: "o1",
          status: "failed",
          amount: "10",
          orderStatus: "paid",
          refundedTotal: "0",
        }),
        get_order: () => paid(),
      },
      { payments },
    );

    expect(await o.refund("o1").then((r) => !r.ok && r.error.hint)).toBe(
      "TOO_MUCH",
    );
    expect(calls.at(-2)?.args).toEqual({
      refund: "rf1",
      status: "failed",
      provider_reference: null,
    });
    expect(
      await orders({})
        .orders.refund("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_NO_PAYMENTS");
    expect(
      await orders(
        { create_refund: raise("ORDERS_REFUND_INVALID") },
        { payments },
      )
        .orders.refund("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_REFUND_INVALID");

    const canceled = fakePayments({
      refund: (paymentId) =>
        AsyncResult.ok({
          id: "re_9",
          paymentId,
          amount: money(10, "EUR"),
          status: "canceled",
        }),
    });

    const pending = orders(
      {
        create_refund: () => ({
          id: "rf1",
          paymentReference: "pi_1",
          amount: "10",
          currency: "EUR",
        }),
        complete_refund: raise("ORDERS_REFUND_NOT_FOUND"),
      },
      { payments: canceled },
    );

    expect(
      await pending.orders.refund("o1").then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_REFUND_NOT_FOUND");
    expect(pending.calls.at(-1)?.args["status"]).toBe("failed");
    expect(
      await orders(
        {
          create_refund: () => ({
            id: "rf1",
            paymentReference: "pi_1",
            amount: "10",
            currency: "EUR",
          }),
          complete_refund: () => ({
            id: "rf1",
            orderId: "o1",
            status: "failed",
            amount: "10",
            orderStatus: "paid",
            refundedTotal: "0",
          }),
          get_order: raise("ORDERS_ORDER_NOT_FOUND"),
        },
        { payments },
      )
        .orders.refund("o1", { amount: money(10, "EUR") })
        .then((r) => !r.ok && r.error.hint),
    ).toBe("TOO_MUCH");
  });

  it("applies payment and refund events", async () => {
    const event = (type: string, extra: Record<string, unknown> = {}) =>
      ({
        id: "evt_1",
        type,
        paymentId: "pi_1",
        reference: "o1",
        amount: money(4955, "EUR"),
        occurredAt: Temporal.Now.instant(),
        ...extra,
      }) as Parameters<
        ReturnType<typeof createOrders>["handlePaymentEvent"]
      >[0];

    const { orders: o, calls } = orders(
      {
        record_payment: () => recordRow(false),
        complete_refund: () => ({
          id: "rf1",
          orderId: "o1",
          status: "succeeded",
          amount: "100",
          orderStatus: "paid",
          refundedTotal: "100",
        }),
        get_order: () => paid(),
      },
      { payments: fakePayments() },
    );

    expect(
      await o.handlePaymentEvent(event("payment.succeeded")).orThrow(),
    ).toMatchObject({
      kind: "payment",
      record: { orderId: "o1", newlyPaid: false },
    });
    expect(calls.at(-1)?.args).toMatchObject({
      order_id: "o1",
      status: "succeeded",
      captured: "4955",
    });
    await o
      .handlePaymentEvent(event("payment.failed", { reference: undefined }))
      .orThrow();
    expect(calls.at(-1)?.args).toMatchObject({
      order_id: null,
      status: "failed",
      captured: "0",
    });
    expect(
      await o
        .handlePaymentEvent(event("payment.processing", { amount: undefined }))
        .orThrow(),
    ).toMatchObject({ kind: "ignored", reason: "no amount" });
    expect(
      await o
        .handlePaymentEvent(event("refund.succeeded", { refundId: "re_1" }))
        .orThrow(),
    ).toMatchObject({
      kind: "refund",
      refund: { id: "rf1", taxReversal: null },
    });
    expect(calls.at(-2)?.args).toEqual({
      refund: null,
      status: "succeeded",
      provider_reference: "re_1",
    });
    await o
      .handlePaymentEvent(event("refund.failed", { refundId: "re_1" }))
      .orThrow();
    expect(calls.at(-2)?.args["status"]).toBe("failed");
    expect(
      await o.handlePaymentEvent(event("refund.failed")).orThrow(),
    ).toMatchObject({ kind: "ignored", reason: "no refund id" });

    const unknown = orders({
      record_payment: raise("ORDERS_ORDER_NOT_FOUND"),
      complete_refund: raise("ORDERS_REFUND_NOT_FOUND"),
    }).orders;

    expect(
      await unknown.handlePaymentEvent(event("payment.succeeded")).orThrow(),
    ).toMatchObject({ kind: "ignored", reason: "unknown order" });
    expect(
      await unknown
        .handlePaymentEvent(event("refund.succeeded", { refundId: "re_x" }))
        .orThrow(),
    ).toMatchObject({ kind: "ignored", reason: "unknown refund" });

    const broken = orders({
      record_payment: raise("BROKEN"),
      complete_refund: raise("BROKEN"),
    }).orders;

    expect(
      await broken
        .handlePaymentEvent(event("payment.succeeded"))
        .then((r) => !r.ok && r.error.hint),
    ).toBe("BROKEN");
    expect(
      await broken
        .handlePaymentEvent(event("refund.succeeded", { refundId: "re_x" }))
        .then((r) => !r.ok && r.error.hint),
    ).toBe("BROKEN");
  });

  it("reads the payment from the provider when it can", async () => {
    const get = vi.fn(() => AsyncResult.ok(payment({ reference: "" })));

    const { orders: o, calls } = orders(
      { record_payment: () => recordRow(false) },
      { payments: fakePayments({ get }) },
    );

    await o
      .handlePaymentEvent({
        id: "evt",
        type: "payment.succeeded",
        paymentId: "pi_1",
        reference: "o9",
        occurredAt: Temporal.Now.instant(),
      })
      .orThrow();
    expect(get).toHaveBeenCalledWith("pi_1");
    expect(calls[0]?.args["order_id"]).toBe("o9");

    const failing = orders(
      {},
      {
        payments: fakePayments({
          get: () =>
            AsyncResult.err(dbError("not_found", "no", { hint: "NO" })),
        }),
      },
    );

    expect(
      await failing.orders
        .handlePaymentEvent({
          id: "e",
          type: "payment.succeeded",
          paymentId: "x",
          occurredAt: Temporal.Now.instant(),
        })
        .then((r) => !r.ok && r.error.hint),
    ).toBe("NO");
  });

  it("verifies webhooks and applies their events", async () => {
    const events = [
      {
        id: "e1",
        type: "payment.succeeded" as const,
        paymentId: "pi_1",
        reference: "o1",
        amount: money(4955, "EUR"),
        occurredAt: Temporal.Now.instant(),
      },
    ];

    const payments = fakePayments({
      parseWebhook: () => AsyncResult.ok(events),
    });

    const { orders: o } = orders(
      { record_payment: () => recordRow(false) },
      { payments },
    );

    const input = { body: "{}", headers: new Headers() } as never;
    expect(await o.webhook(input).orThrow()).toHaveLength(1);
    expect(
      await orders({})
        .orders.webhook(input)
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_NO_PAYMENTS");

    const unsigned = fakePayments({
      parseWebhook: () =>
        AsyncResult.err(dbError("unauthorized", "bad", { hint: "SIG" })),
    });

    expect(
      await orders({}, { payments: unsigned })
        .orders.webhook(input)
        .then((r) => !r.ok && r.error.hint),
    ).toBe("SIG");
    expect(
      await orders({ record_payment: raise("BROKEN") }, { payments })
        .orders.webhook(input)
        .then((r) => !r.ok && r.error.hint),
    ).toBe("BROKEN");
  });

  it("cancels orders and their open payments", async () => {
    const cancel = vi.fn(() =>
      AsyncResult.ok(
        payment({ status: "canceled", captured: money(0, "EUR") }),
      ),
    );

    const pending = orderRow({
      payments: [
        { ...PAY1, status: "authorized", captured: "0" },
        { ...PAY1, id: "pay2", reference: "pi_2", status: "failed" },
        {
          ...PAY1,
          id: "pay3",
          reference: "pi_3",
          provider: "other",
          status: "authorized",
        },
      ],
    });

    const { orders: o, fns } = orders(
      {
        cancel_order: () => true,
        get_order: () => pending,
        record_payment: () => recordRow(false, "cancelled"),
      },
      { payments: fakePayments({ cancel }) },
    );

    expect(await o.cancelOrder("o1", "changed mind").orThrow()).toBe(true);
    expect(cancel).toHaveBeenCalledExactlyOnceWith("pi_1", {
      idempotencyKey: "cancel:pay1",
    });
    expect(fns()).toEqual(["cancel_order", "get_order", "record_payment"]);

    const failing = orders(
      { cancel_order: () => true, get_order: () => pending },
      {
        payments: fakePayments({
          cancel: () => AsyncResult.err(dbError("unexpected", "down")),
        }),
      },
    );

    expect(await failing.orders.cancelOrder("o1").orThrow()).toBe(true);
    expect(failing.logger.warn).toHaveBeenCalledWith(
      "orders: cancelling the payment failed",
      expect.anything(),
    );
    expect(
      await orders(
        { cancel_order: () => true, get_order: raise("X") },
        { payments: fakePayments({ cancel }) },
      )
        .orders.cancelOrder("o1")
        .orThrow(),
    ).toBe(true);
    expect(
      await orders(
        { cancel_order: () => false },
        { payments: fakePayments({ cancel }) },
      )
        .orders.cancelOrder("o1")
        .orThrow(),
    ).toBe(false);
    expect(
      await orders({ cancel_order: () => true })
        .orders.cancelOrder("o1")
        .orThrow(),
    ).toBe(true);
  });

  it("fulfills, returns, invoices and expires", async () => {
    const { orders: o, calls } = orders({
      create_fulfillment: () => ({
        id: "f1",
        orderId: "o1",
        status: "pending",
      }),
      ship_fulfillment: () => true,
      deliver_fulfillment: () => true,
      cancel_fulfillment: () => false,
      request_return: () => ({
        id: "ret1",
        orderId: "o1",
        status: "requested",
        quantity: 1,
      }),
      receive_return: () => true,
      reject_return: () => true,
      get_order: () => paid(),
      expire_orders: () => 2,
    });

    expect(await o.createFulfillment("o1").orThrow()).toEqual({ id: "f1" });
    expect(calls[0]?.args).toEqual({
      order_id: "o1",
      lines: null,
      location: null,
      carrier: null,
      tracking_number: null,
      tracking_url: null,
    });
    await o
      .createFulfillment("o1", {
        lines: [{ lineId: "l1", quantity: 1 }],
        locationId: "w1",
        carrier: "PostNL",
        trackingNumber: "3S",
        trackingUrl: "https://t.test",
      })
      .orThrow();
    expect(calls[1]?.args["lines"]).toEqual([{ lineId: "l1", quantity: 1 }]);
    await o.shipFulfillment("f1").orThrow();
    await o
      .shipFulfillment("f1", {
        carrier: "DHL",
        trackingNumber: "1",
        trackingUrl: "u",
      })
      .orThrow();
    expect(calls[3]?.args).toEqual({
      fulfillment: "f1",
      carrier: "DHL",
      tracking_number: "1",
      tracking_url: "u",
    });
    expect(await o.deliverFulfillment("f1").orThrow()).toBe(true);
    expect(await o.cancelFulfillment("f1").orThrow()).toBe(false);
    expect(
      await o
        .requestReturn("o1", [{ lineId: "l1", quantity: 1 }], "too small")
        .orThrow(),
    ).toEqual({ id: "ret1", quantity: 1 });
    await o.requestReturn("o1", [{ lineId: "l1", quantity: 1 }]).orThrow();
    await o.receiveReturn("ret1").orThrow();
    expect(calls.at(-1)?.args).toEqual({
      return_id: "ret1",
      restock: true,
      location: null,
    });
    await o
      .receiveReturn("ret1", { restock: false, locationId: "w1" })
      .orThrow();
    expect(await o.rejectReturn("ret1").orThrow()).toBe(true);
    const invoice = await o.invoice("o1").orThrow();
    expect(invoice.number).toBe("INV-00001");
    expect(invoice.issuedAt.toString()).toBe("2026-10-14T10:05:00Z");
    expect((await o.getOrder("o1").orThrow()).fulfillments[0]?.carrier).toBe(
      "PostNL",
    );
    expect(await o.expireOrders().orThrow()).toBe(2);
    await o.job({ maxRows: 5 }, {} as never, new AbortController().signal);
    expect(calls.at(-1)?.args).toEqual({ max_rows: 5 });
    await o.job(null, {} as never, new AbortController().signal);
    await o.job({ maxRows: "x" }, {} as never, new AbortController().signal);
    expect(calls.at(-1)?.args).toEqual({ max_rows: null });
    expect(
      await orders({ get_order: () => orderRow() })
        .orders.invoice("o1")
        .then((r) => !r.ok && r.error.hint),
    ).toBe("ORDERS_NOT_INVOICED");
  });

  it("rejects providers for another API version", () => {
    const transport = router({}).transport;
    expect(() =>
      createOrders({
        transport,
        payments: { ...fakePayments(), apiVersion: 2 as never },
      }),
    ).toThrow(/payment provider API 2/);
    expect(() =>
      createOrders({ transport, tax: { ...TAX, apiVersion: 2 as never } }),
    ).toThrow(/tax provider API 2/);
  });

  it("runs block hooks around methods", async () => {
    const before = vi.fn();

    const { orders: o } = orders(
      { get_order: () => paid() },
      { hooks: { getOrder: { before } } },
    );

    await o.getOrder("o1").orThrow();
    expect(before).toHaveBeenCalledWith(["o1"], {
      block: "orders",
      method: "getOrder",
    });
  });
});

describe("order fields", () => {
  const schema = v.object({ channel: v.picklist(["web", "pos"]) });

  it("validates checkout fields, sends them to place_order and parses reads", async () => {
    const route = router({
      price_cart: () =>
        cartRow({ status: "converted", lines: [], problems: [] }),
      place_order: () =>
        orderRow({ status: "paid", fields: { channel: "pos" } }),
      get_order: () => orderRow({ fields: { channel: "web" } }),
    });

    const o = createOrders({ transport: route.transport, fields: schema });

    const bad = await o.checkout("c1", {
      // @ts-expect-error not one of the channels
      fields: { channel: "fax" },
    });

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(route.calls).toHaveLength(0);

    const placed = await o
      .checkout("c1", { fields: { channel: "pos" } })
      .orThrow();

    expect(route.calls[1]?.args).toMatchObject({ fields: { channel: "pos" } });
    expect(placed.order.fields).toEqual({ channel: "pos" });
    const order = await o.getOrder("o1").orThrow();
    expectTypeOf(order.fields.channel).toEqualTypeOf<"web" | "pos">();
    expect(order.fields.channel).toBe("web");
  });

  it("refuses an order whose stored fields fail the schema", async () => {
    const route = router({
      get_order: () => orderRow({ fields: { channel: 1 } }),
    });

    const o = createOrders({ transport: route.transport, fields: schema });
    expect(await o.getOrder("o1")).toMatchObject({
      ok: false,
      error: { kind: "validation" },
    });
  });
});
