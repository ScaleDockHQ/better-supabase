import { describe, expect, it } from "vitest";

import { createInvoices } from "../../../src/blocks/invoices/index.ts";
import { money } from "../../../src/commerce/money.ts";

const eur = (amount: bigint) => money(amount, "EUR");

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const ROW = {
  id: "i1",
  tenant_id: "o",
  kind: "invoice",
  number: "1",
  identifier: "INV-1",
  original_id: null,
  title: "October",
  company_type: "company",
  company_id: "c1",
  contact_type: null,
  contact_id: null,
  currency: "EUR",
  status: "partially_paid",
  terms_days: 30,
  issued_on: "2026-10-15",
  due_on: "2026-11-14",
  paid_total: "500",
  credited_total: "100",
  paid_at: null,
  voided_at: null,
  void_reason: null,
  note: null,
  origin_type: "quote",
  origin_id: "q1",
  deposit_bps: 3000,
  created_by: "u1",
  created_at: "2026-10-15T09:00:00Z",
  updated_at: "2026-10-15T09:00:00Z",
  list_total: "1000",
  discount_total: "0",
  subtotal: "1000",
  tax_total: "0",
  total: "1000",
  balance: "400",
  overdue: true,
  lines: [
    {
      description: "x",
      quantity: 1,
      unitAmount: "1000",
      discountBps: 0,
      taxRateBps: 0,
      taxCode: null,
      product: null,
    },
  ],
  payments: [
    {
      id: "pay1",
      amount: "500",
      paidAt: "2026-10-16T09:00:00Z",
      method: "bank",
      reference: "b1",
    },
  ],
};

describe("invoices block", () => {
  it("reads balances, payments and the deposit share", async () => {
    const t = transport({ issue_invoice: () => ROW });

    const invoice = await createInvoices({ transport: t })
      .issue("i1", Temporal.PlainDate.from("2026-10-15"))
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({ invoice: "i1", issued_on: "2026-10-15" });
    expect(invoice).toMatchObject({
      number: 1n,
      paidTotal: eur(500n),
      creditedTotal: eur(100n),
      balance: eur(400n),
      overdue: true,
      depositBps: 3000,
      origin: { type: "quote", id: "q1" },
      payments: [
        { id: "pay1", amount: eur(500n), method: "bank", reference: "b1" },
      ],
      lines: [{ unitAmount: eur(1000n) }],
      totals: { total: eur(1000n) },
    });
    expect(invoice.dueOn?.toString()).toBe("2026-11-14");
  });

  it("reads a draft without a number", async () => {
    const draft = {
      ...ROW,
      status: "draft",
      number: null,
      identifier: null,
      issued_on: null,
      due_on: null,
      deposit_bps: null,
      payments: [],
    };

    const t = transport({ create_invoice: () => draft });

    const invoice = await createInvoices({ transport: t })
      .create("o", { title: "October" })
      .orThrow();

    expect(invoice.number).toBeUndefined();
    expect(invoice.identifier).toBeUndefined();
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      attrs: { title: "October" },
      lines: null,
    });
  });

  it("records payments, credits, voids, writes off, ages and converts quotes", async () => {
    const t = transport({
      record_invoice_payment: () => ROW,
      credit_invoice: () => ({
        ...ROW,
        kind: "credit_note",
        original_id: "i0",
      }),
      void_invoice: () => ({ ...ROW, status: "void" }),
      write_off_invoice: () => ({ ...ROW, status: "uncollectible" }),
      invoice_aging: () => ({
        currency: "EUR",
        current: "1",
        days1To30: "2",
        days31To60: "3",
        days61To90: "4",
        over90: "5",
        outstanding: "15",
        overdueCount: 4,
      }),
      invoice_from_quote: () => ROW,
      set_invoice_lines: () => ({
        listTotal: "1",
        discountTotal: "0",
        subtotal: "1",
        taxTotal: "0",
        total: "1",
        currency: "EUR",
      }),
    });

    const invoices = createInvoices({ transport: t });
    await invoices
      .recordPayment("i1", {
        amount: eur(-50n),
        paidAt: Temporal.Instant.from("2026-10-16T09:00:00Z"),
        reference: "r",
      })
      .orThrow();
    expect(t.calls[0]?.[1]).toEqual({
      invoice: "i1",
      amount: "-50",
      currency: "EUR",
      paid_at: "2026-10-16T09:00:00Z",
      method: null,
      reference: "r",
    });
    expect(
      (await invoices.credit("i1", { note: "Goodwill" }).orThrow()).originalId,
    ).toBe("i0");
    expect((await invoices.void("i1").orThrow()).status).toBe("void");
    expect((await invoices.writeOff("i1").orThrow()).status).toBe(
      "uncollectible",
    );
    expect(await invoices.aging("o", "EUR").orThrow()).toMatchObject({
      over90: eur(5n),
      outstanding: eur(15n),
      overdueCount: 4,
    });
    await invoices.fromQuote("q1", { depositBps: 2000 }).orThrow();
    expect((await invoices.setLines("i1", []).orThrow()).total).toEqual(
      eur(1n),
    );
    expect(t.calls[1]?.[1]).toEqual({
      invoice: "i1",
      lines: null,
      note: "Goodwill",
    });
    expect(t.calls[5]?.[1]).toEqual({ quote: "q1", deposit_bps: 2000 });
  });
});

describe("invoices block, defaults", () => {
  it("issues today, credits in full and pays without a date", async () => {
    const paid = {
      ...ROW,
      status: "paid",
      contact_type: "person",
      contact_id: "p1",
      paid_at: "2026-10-20T09:00:00Z",
      void_reason: null,
      origin_type: null,
      origin_id: null,
      deposit_bps: null,
      terms_days: null,
      payments: [
        {
          id: "pay1",
          amount: "1000",
          paidAt: "2026-10-20T09:00:00Z",
          method: null,
          reference: null,
        },
      ],
    };

    const t = transport({
      issue_invoice: () => paid,
      credit_invoice: () => paid,
      record_invoice_payment: () => paid,
      invoice_aging: () => ({
        currency: "EUR",
        current: "0",
        days1To30: "0",
        days31To60: "0",
        days61To90: "0",
        over90: "0",
        outstanding: "0",
        overdueCount: null,
      }),
    });

    const invoices = createInvoices({ transport: t });
    const invoice = await invoices.issue("i1").orThrow();
    expect(invoice).toMatchObject({
      status: "paid",
      contact: { type: "person", id: "p1" },
      termsDays: 0,
    });
    expect(invoice.depositBps).toBeUndefined();
    expect(invoice.paidAt).toBeDefined();
    await invoices
      .credit("i1", { lines: [{ description: "x", unitAmount: eur(5n) }] })
      .orThrow();
    await invoices
      .recordPayment("i1", { amount: eur(1n), method: "card" })
      .orThrow();
    expect(
      (
        await invoices
          .aging("o", "EUR", Temporal.PlainDate.from("2026-12-01"))
          .orThrow()
      ).overdueCount,
    ).toBe(0);
    expect(t.calls.map(([, args]) => args)).toEqual([
      { invoice: "i1", issued_on: null },
      {
        invoice: "i1",
        lines: [{ description: "x", unitAmount: "5", currency: "EUR" }],
        note: null,
      },
      {
        invoice: "i1",
        amount: "1",
        currency: "EUR",
        paid_at: null,
        method: "card",
        reference: null,
      },
      { tenant: "o", currency: "EUR", as_of: "2026-12-01" },
    ]);
  });
});

describe("invoices block, currencies", () => {
  it("refuses lines in another currency and unknown codes before calling", async () => {
    const t = transport({});
    const invoices = createInvoices({ transport: t });
    const usd = money(1n, "USD");

    const results = [
      await invoices.create("o", { title: "x", currency: "EUR" }, [
        { description: "x", unitAmount: usd },
      ]),
      await invoices.setLines("i1", [
        { description: "a", unitAmount: eur(1n) },
        { description: "b", unitAmount: usd },
      ]),
      await invoices.credit("i1", {
        lines: [
          { description: "a", unitAmount: eur(1n) },
          { description: "b", unitAmount: usd },
        ],
      }),
      await invoices.aging("o", "XXQ"),
    ];

    expect(
      results.map((result) => (result.ok ? undefined : result.error.hint)),
    ).toEqual([
      "CURRENCY_MISMATCH",
      "CURRENCY_MISMATCH",
      "CURRENCY_MISMATCH",
      "CURRENCY_INVALID",
    ]);
    expect(t.calls).toEqual([]);
  });

  it("takes the currency from the lines when the input has none", async () => {
    const t = transport({ create_invoice: () => ROW });

    await createInvoices({ transport: t })
      .create("o", { title: "x" }, [
        { description: "x", unitAmount: money(5n, "USD") },
      ])
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      attrs: { title: "x", currency: "USD" },
      lines: [{ description: "x", unitAmount: "5", currency: "USD" }],
    });
  });
});
