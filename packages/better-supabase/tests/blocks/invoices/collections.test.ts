import { Temporal } from "temporal-polyfill";
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

const INVOICE = {
  id: "i1",
  tenant_id: "o",
  kind: "invoice",
  number: "1",
  identifier: "INV-0001",
  title: "Retainer",
  company_type: "company",
  company_id: "c1",
  currency: "EUR",
  status: "partially_paid",
  terms_days: 30,
  paid_total: "150",
  credited_total: "0",
  balance: "850",
  overdue: true,
  list_total: "1000",
  discount_total: "0",
  subtotal: "1000",
  tax_total: "0",
  total: "1000",
  created_at: "2026-10-01T09:00:00Z",
  dunning_level: 2,
  dunning_at: "2026-10-30T06:00:00Z",
  dunning_paused_until: "2026-11-07",
  lines: [],
  payments: [],
};

describe("invoices collections", () => {
  it("records a party payment and reads the credit it keeps", async () => {
    const t = transport({
      record_party_payment: () => ({
        partyId: "c1",
        currency: "EUR",
        amount: "1500",
        allocated: "1300",
        credited: "200",
        creditTransactionId: "tx1",
        credit: "200",
      }),
    });

    const payment = await createInvoices({ transport: t })
      .recordPartyPayment("o", {
        partyId: "c1",
        amount: eur(1500n),
        allocations: [
          { invoiceId: "i1", amount: eur(1000n) },
          { invoiceId: "i2", amount: eur(300n) },
        ],
        receivedOn: Temporal.PlainDate.from("2026-10-31"),
        reference: "bank-0001",
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      party_id: "c1",
      amount: "1500",
      currency: "EUR",
      allocations: [
        { invoiceId: "i1", amount: "1000" },
        { invoiceId: "i2", amount: "300" },
      ],
      received_on: "2026-10-31",
      reference: "bank-0001",
      method: null,
      note: null,
    });
    expect(payment).toEqual({
      partyId: "c1",
      amount: eur(1500n),
      allocated: eur(1300n),
      credited: eur(200n),
      creditTransactionId: "tx1",
      credit: eur(200n),
    });
  });

  it("applies party credit and lists it per currency", async () => {
    const t = transport({
      apply_party_credit: () => INVOICE,
      list_party_credits: () => [{ currency: "EUR", amount: "50" }],
    });

    const invoices = createInvoices({ transport: t });

    const paid = await invoices
      .applyPartyCredit("c1", "i1", eur(150n))
      .orThrow();

    expect(t.calls[0]).toEqual([
      "apply_party_credit",
      { party_id: "c1", invoice: "i1", amount: "150" },
    ]);
    expect(paid.dunning).toEqual({
      level: 2,
      at: Temporal.Instant.from("2026-10-30T06:00:00Z"),
      pausedUntil: Temporal.PlainDate.from("2026-11-07"),
    });
    expect(await invoices.partyCredits("o", "c1").orThrow()).toEqual([
      eur(50n),
    ]);
  });

  it("sets and reads dunning levels", async () => {
    const levels = [
      {
        level: 1,
        daysAfterDue: 7,
        templateKey: "reminder",
        fee: "0",
        final: false,
      },
      {
        level: 2,
        daysAfterDue: 21,
        templateKey: "final",
        fee: "500",
        final: true,
      },
    ];

    const t = transport({
      set_invoice_dunning_levels: () => levels,
      list_invoice_dunning_levels: () => levels,
    });

    const invoices = createInvoices({ transport: t });

    const saved = await invoices
      .setDunningLevels("o", [
        { daysAfterDue: 7, templateKey: "reminder" },
        { daysAfterDue: 21, templateKey: "final", fee: 500n, final: true },
      ])
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      levels: [
        { daysAfterDue: 7, templateKey: "reminder", fee: "0", final: false },
        { daysAfterDue: 21, templateKey: "final", fee: "500", final: true },
      ],
    });
    expect(saved[1]).toEqual({
      level: 2,
      daysAfterDue: 21,
      templateKey: "final",
      fee: 500n,
      final: true,
    });
    expect(await invoices.dunningLevels("o").orThrow()).toHaveLength(2);
  });

  it("runs and pauses dunning", async () => {
    const t = transport({
      run_invoice_dunning: () => 3,
      pause_invoice_dunning: () => INVOICE,
    });

    const invoices = createInvoices({ transport: t });

    expect(
      await invoices
        .runDunning({ asOf: Temporal.PlainDate.from("2026-10-31") })
        .orThrow(),
    ).toBe(3);
    await invoices
      .pauseDunning("i1", Temporal.PlainDate.from("2026-11-07"), "Disputed")
      .orThrow();
    await invoices.pauseDunning("i1", null).orThrow();

    expect(t.calls.map(([, args]) => args)).toEqual([
      { tenant: null, as_of: "2026-10-31" },
      { invoice: "i1", until: "2026-11-07", reason: "Disputed" },
      { invoice: "i1", until: null, reason: null },
    ]);
  });

  it("passes the actor, method and note through", async () => {
    const t = transport({
      record_party_payment: () => ({
        partyId: "c1",
        currency: "EUR",
        amount: "100",
        allocated: "100",
        credited: "0",
        creditTransactionId: null,
        credit: "0",
      }),
      apply_party_credit: () => INVOICE,
      run_invoice_dunning: () => null,
    });

    const invoices = createInvoices({ transport: t });
    const actor = { id: "u1", name: "Ann" };

    await invoices
      .recordPartyPayment("o", {
        partyId: "c1",
        amount: eur(100n),
        allocations: [{ invoiceId: "i1", amount: eur(100n) }],
        reference: "bank-0002",
        method: "sepa",
        note: "Batch",
        actor,
      })
      .orThrow();
    await invoices.applyPartyCredit("c1", "i1", eur(10n), { actor }).orThrow();

    expect(await invoices.runDunning({ organizationId: "o" }).orThrow()).toBe(
      0,
    );
    expect(t.calls.map(([, args]) => args)).toMatchObject([
      { method: "sepa", note: "Batch", received_on: null, actor },
      { actor },
      { tenant: "o", as_of: null },
    ]);
  });

  it("leaves dunning out when the table has no dunning columns", async () => {
    const {
      dunning_level: _level,
      dunning_at: _at,
      dunning_paused_until: _paused,
      ...row
    } = INVOICE;

    const t = transport({ pause_invoice_dunning: () => row });

    const invoice = await createInvoices({ transport: t })
      .pauseDunning("i1", null)
      .orThrow();

    expect(invoice.dunning).toBeUndefined();
  });
});
