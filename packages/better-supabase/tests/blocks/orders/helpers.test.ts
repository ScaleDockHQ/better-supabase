import { describe, expect, it, vi } from "vitest";

import type { Orders } from "../../../src/blocks/orders/orders.ts";

import { orderHelpers } from "../../../src/blocks/orders/helpers.ts";
import { money } from "../../../src/commerce/money.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err } from "../../../src/core/result.ts";

function setup(overrides: Record<string, unknown> = {}) {
  const afterPayment = vi.fn(() => Promise.resolve());

  const client = {
    getOrder: vi.fn(() =>
      AsyncResult.ok({ total: money(5000, "EUR"), currency: "EUR" }),
    ),
    recordPayment: vi.fn(() =>
      AsyncResult.ok({ orderId: "o1", newlyPaid: true }),
    ),
    requestReturn: vi.fn(() => AsyncResult.ok({ id: "r1" })),
    receiveReturn: vi.fn(() => AsyncResult.ok(true)),
    refund: vi.fn(() => AsyncResult.ok({ refunded: true })),
    createFulfillment: vi.fn(() => AsyncResult.ok({ id: "f1" })),
    shipFulfillment: vi.fn(() => AsyncResult.ok(true)),
    ...overrides,
  };

  // SAFETY: the stub implements the methods the helpers call.
  const helpers = orderHelpers(() => client as unknown as Orders, afterPayment);

  return { client, helpers, afterPayment };
}

describe("order helpers", () => {
  it("markPaid records a manual payment for the whole total and commits tax", async () => {
    const { client, helpers, afterPayment } = setup();

    await helpers.markPaid({ orderId: "o1" }).orThrow();

    expect(client.recordPayment).toHaveBeenCalledWith({
      orderId: "o1",
      payment: expect.objectContaining({
        id: "manual:o1",
        provider: "manual",
        status: "succeeded",
        amount: money(5000, "EUR"),
        captured: money(5000, "EUR"),
      }),
    });
    expect(afterPayment).toHaveBeenCalledOnce();
  });

  it("markPaid keeps a given reference as the payment id", async () => {
    const { client, helpers } = setup();

    await helpers.markPaid({ orderId: "o1", reference: "wire-9" }).orThrow();

    expect(client.recordPayment).toHaveBeenCalledWith(
      expect.objectContaining({
        payment: expect.objectContaining({ id: "wire-9" }),
      }),
    );
  });

  it("returnAndRefund requests, receives and refunds the return", async () => {
    const { client, helpers } = setup();

    const done = await helpers
      .returnAndRefund({
        orderId: "o1",
        lines: [{ lineId: "l1", quantity: 1 }],
        reason: "damaged",
        restock: false,
      })
      .orThrow();

    expect(done).toEqual({ returnId: "r1", refund: { refunded: true } });
    expect(client.receiveReturn).toHaveBeenCalledWith({
      returnId: "r1",
      restock: false,
    });
    expect(client.refund).toHaveBeenCalledWith({
      orderId: "o1",
      input: { returnId: "r1", reason: "damaged" },
    });
  });

  it("returnAndRefund stops when the return can't be received", async () => {
    const { client, helpers } = setup({
      receiveReturn: vi.fn(() =>
        AsyncResult.from(() =>
          Promise.resolve(err(dbError("conflict", "already received"))),
        ),
      ),
    });

    const done = await helpers.returnAndRefund({
      orderId: "o1",
      lines: [{ lineId: "l1", quantity: 1 }],
    });

    expect(done.ok).toBe(false);
    expect(client.refund).not.toHaveBeenCalled();
  });

  it("fulfilAll ships only when tracking is given", async () => {
    const { client, helpers } = setup();

    expect(await helpers.fulfilAll({ orderId: "o1" }).orThrow()).toEqual({
      id: "f1",
      shipped: false,
    });
    expect(client.shipFulfillment).not.toHaveBeenCalled();

    const tracking = { carrier: "dhl", trackingNumber: "123" };

    expect(
      await helpers.fulfilAll({ orderId: "o1", tracking }).orThrow(),
    ).toEqual({ id: "f1", shipped: true });
    expect(client.shipFulfillment).toHaveBeenCalledWith({
      fulfillmentId: "f1",
      tracking,
    });
  });
});
