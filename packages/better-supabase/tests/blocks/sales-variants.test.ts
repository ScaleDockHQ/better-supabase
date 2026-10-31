import { describe, expect, it } from "vitest";

import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { createOrders } from "../../src/blocks/orders/index.ts";
import { createQuotes } from "../../src/blocks/quotes/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      return result
        ? Promise.resolve(result(args))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };
}

const VARIANTS = [
  { id: "q1", number: "Q-1", isSelected: false, currency: "EUR", total: "100" },
  {
    id: "q2",
    number: "Q-2",
    variantOf: "q1",
    variantLabel: "Option B",
    isSelected: true,
    currency: "EUR",
    total: "250",
  },
];

describe("quote variants", () => {
  it("creates, lists and selects a variant and copies it forward", async () => {
    const t = transport({
      create_quote_variant: () => ({ id: "q2" }),
      list_quote_variants: () => VARIANTS,
      select_quote_variant: () => ({
        quote: { id: "q2" },
        variants: VARIANTS,
        order: { id: "o1" },
        invoice: null,
      }),
    });

    const quotes = createQuotes({ transport: t });

    expect(
      await quotes.createVariant("q1", "Option B").orThrow(),
    ).toStrictEqual({ id: "q2" });

    const listed = await quotes.listVariants("q1").orThrow();

    expect(listed[1]).toMatchObject({
      variantOf: "q1",
      variantLabel: "Option B",
      isSelected: true,
    });

    const selection = await quotes
      .selectVariant("q2", { forward: "order" })
      .orThrow();

    expect(selection).toMatchObject({ selectedId: "q2", orderId: "o1" });
    expect(selection.invoiceId).toBeUndefined();
    expect(t.calls.at(-1)).toStrictEqual([
      "select_quote_variant",
      { quote: "q2", options: { forward: "order" } },
    ]);
  });
});

describe("order variants", () => {
  it("groups orders and selects one", async () => {
    const t = transport({
      set_order_variant: () => VARIANTS[1],
      list_order_variants: () => VARIANTS,
      select_order_variant: () => ({ order: VARIANTS[1], variants: VARIANTS }),
    });

    const orders = createOrders({ transport: t });

    expect(
      await orders.setVariant("q2", "q1", "Option B").orThrow(),
    ).toMatchObject({ id: "q2", variantOf: "q1" });
    expect(await orders.listVariants("q1").orThrow()).toHaveLength(2);
    expect(await orders.selectVariant("q2").orThrow()).toHaveLength(2);
    expect(t.calls[0]).toStrictEqual([
      "set_order_variant",
      { id: "q2", variant_of: "q1", label: "Option B" },
    ]);
  });
});

describe("collective invoicing", () => {
  it("sends the sources and reads one invoice per party and currency", async () => {
    const t = transport({
      invoice_from_sources: () => ({
        invoices: [
          { id: "i1", currency: "EUR", total: "12100" },
          { id: "i2", currency: "USD", total: "500" },
        ],
        skipped: [{ type: "order", id: "o3" }],
      }),
      sources_ready_to_invoice: () => [
        {
          type: "order",
          id: "o1",
          reference: "ORD-1",
          currency: "EUR",
          lines: 2,
          quantity: "5",
          amount: "10000",
        },
        {
          type: "time",
          currency: "EUR",
          lines: 1,
          quantity: "3.5",
          amount: "35000",
        },
      ],
    });

    const invoices = createInvoices({ transport: t });
    const party = { type: "company", id: "c1" };

    const done = await invoices
      .invoiceFromSources(
        "org",
        party,
        [
          { type: "order", id: "o1", lines: [{ id: "l1", quantity: 2 }] },
          { type: "shipment", id: "s1" },
        ],
        { title: "October" },
      )
      .orThrow();

    expect(done.invoices.map((each) => each.total.amount)).toStrictEqual([
      12_100n,
      500n,
    ]);
    expect(done.skipped).toStrictEqual([{ type: "order", id: "o3" }]);
    expect(t.calls[0]?.[1]).toMatchObject({
      tenant: "org",
      party,
      options: { title: "October" },
    });

    const ready = await invoices.sourcesReadyToInvoice("org", party).orThrow();

    expect(ready.map((each) => each.type)).toStrictEqual(["order", "time"]);
    expect(ready[1]?.id).toBeUndefined();
    expect(ready[0]?.amount.amount).toBe(10_000n);
  });
});
