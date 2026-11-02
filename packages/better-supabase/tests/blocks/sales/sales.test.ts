import { describe, expect, it, vi } from "vitest";

import { createSales } from "../../../src/blocks/sales/sales.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const fail = (message: string) =>
  AsyncResult.err({ kind: "unknown", message } as never);

/**
 * The option is named `then`; a computed key keeps the literal from reading as
 * a thenable.
 */
const THEN = ["th", "en"].join("");

function parts(overrides: Record<string, Record<string, unknown>> = {}) {
  const calls: unknown[][] = [];

  const record =
    (name: string, value: unknown) =>
    (...args: unknown[]) => {
      calls.push([name, ...args]);

      return AsyncResult.ok(value);
    };

  const clients = {
    deals: {
      win: record("deals.win", { id: "d1" }),
      lose: record("deals.lose", { id: "d1" }),
      ...overrides["deals"],
    },
    quotes: {
      fromDeal: record("quotes.fromDeal", { id: "q1" }),
      withdraw: record("quotes.withdraw", { id: "q1" }),
      decide: record("quotes.decide", { id: "q1" }),
      ...overrides["quotes"],
    },
    orders: {
      fromQuote: record("orders.fromQuote", { order: { id: "o1" } }),
      ...overrides["orders"],
    },
    invoices: {
      fromQuote: record("invoices.fromQuote", { id: "i1" }),
      issue: record("invoices.issue", { id: "i1", issued: true }),
      ...overrides["invoices"],
    },
  };

  return { calls, sales: createSales({ parts: clients } as never) };
}

describe("sales", () => {
  it("closeWon wins the deal and drafts a quote only when asked", async () => {
    const { sales, calls } = parts();

    expect(await sales.closeWon({ dealId: "d1" })).toMatchObject({
      ok: true,
      data: { deal: { id: "d1" }, quote: null },
    });
    expect(await sales.closeWon({ dealId: "d1", quote: true })).toMatchObject({
      data: { quote: { id: "q1" } },
    });
    expect(calls.map(([name]) => name)).toEqual([
      "deals.win",
      "deals.win",
      "quotes.fromDeal",
    ]);
  });

  it("closeLost withdraws each quote with the reason", async () => {
    const { sales, calls } = parts();

    expect(await sales.closeLost({ dealId: "d1" })).toMatchObject({
      data: { withdrawn: 0 },
    });
    expect(
      await sales.closeLost({
        dealId: "d1",
        reason: "price",
        withdraw: ["a", "b"],
      }),
    ).toMatchObject({ data: { withdrawn: 2 } });
    expect(
      await sales.closeLost({ dealId: "d1", withdraw: ["a"] }),
    ).toMatchObject({ data: { withdrawn: 1 } });
    expect(calls.find(([name]) => name === "quotes.withdraw")).toEqual([
      "quotes.withdraw",
      { quoteId: "a", options: { reason: "price" } },
    ]);
  });

  it("closeLost stops at the first refused withdrawal", async () => {
    const withdraw = vi.fn(() => fail("locked"));
    const { sales } = parts({ quotes: { withdraw } });

    const result = await sales.closeLost({
      dealId: "d1",
      withdraw: ["a", "b"],
    });

    expect(result.ok).toBe(false);
    expect(withdraw).toHaveBeenCalledOnce();
  });

  it("acceptQuote records the decision, wins the deal and then orders", async () => {
    const { sales, calls } = parts();

    const result = await sales.acceptQuote({
      quoteId: "q1",
      dealId: "d1",
      by: "Ada",
      note: "ok",
      [THEN]: "order",
    });

    expect(result).toMatchObject({
      ok: true,
      data: { deal: { id: "d1" }, order: { id: "o1" }, invoice: null },
    });
    expect(calls[0]).toEqual([
      "quotes.decide",
      {
        quoteId: "q1",
        decision: "accepted",
        options: { by: "Ada", note: "ok" },
      },
    ]);
  });

  it("acceptQuote can invoice, or do nothing further", async () => {
    const { sales } = parts();

    expect(
      await sales.acceptQuote({ quoteId: "q1", [THEN]: "invoice" }),
    ).toMatchObject({
      data: { deal: null, order: null, invoice: { id: "i1" } },
    });
    expect(await sales.acceptQuote({ quoteId: "q1" })).toMatchObject({
      data: { deal: null, order: null, invoice: null },
    });
  });

  it("billQuote passes the deposit and issues on request", async () => {
    const { sales, calls } = parts();
    const amount = { amount: 100n, currency: "EUR" } as never;

    expect(await sales.billQuote({ quoteId: "q1" })).toMatchObject({
      data: { issued: false },
    });
    expect(
      await sales.billQuote({
        quoteId: "q1",
        depositBps: 2500,
        depositAmount: amount,
        issue: true,
      }),
    ).toMatchObject({ data: { issued: true } });
    expect(calls[1]).toEqual([
      "invoices.fromQuote",
      { quoteId: "q1", depositBps: 2500, depositAmount: amount },
    ]);
  });
});
