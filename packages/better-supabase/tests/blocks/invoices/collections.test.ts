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

  it("carries a level's text key and hands over without options", async () => {
    const level = {
      level: 1,
      daysAfterDue: 7,
      templateKey: "reminder",
      textKey: "friendly",
      fee: "0",
      final: false,
    };

    const t = transport({
      set_invoice_dunning_levels: () => [level],
      hand_over_to_collection: () => [{ id: "i1" }],
      pause_invoice_dunning: () => ({ ...INVOICE, payment_terms_id: "t1" }),
    });

    const invoices = createInvoices({ transport: t });

    const [saved] = await invoices
      .setDunningLevels("o", [
        { daysAfterDue: 7, templateKey: "reminder", textKey: "friendly" },
      ])
      .orThrow();

    expect(saved?.textKey).toBe("friendly");
    expect(t.calls[0]?.[1]).toMatchObject({
      levels: [{ textKey: "friendly" }],
    });

    await invoices.handOverToCollection(["i1"], "a1").orThrow();
    expect(t.calls.at(-1)?.[1]).toMatchObject({ note: null });

    const read = await invoices.pauseDunning("i1", null).orThrow();

    expect(read.paymentTerms).toEqual({ id: "t1" });
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

  it("reads dunning runs, history and the invoice's terms and hand-over", async () => {
    const t = transport({
      list_invoice_dunning_runs: () => [
        {
          id: "r1",
          asOf: "2026-10-31",
          createdAt: "2026-10-31T06:00:00Z",
          items: 2,
          customers: 1,
        },
      ],
      list_invoice_dunning_run_items: () => [
        {
          partyId: "c1",
          balance: "2000",
          fee: "500",
          items: [
            {
              invoiceId: "i1",
              level: 2,
              textKey: "second",
              templateKey: "t",
              fee: "500",
              balance: "1000",
              dueOn: "2026-10-01",
            },
          ],
        },
      ],
      list_invoice_dunning_history: () => [
        {
          kind: "reminder",
          level: 1,
          fee: "0",
          balance: "1000",
          runId: "r1",
          at: "2026-10-31T06:00:00Z",
        },
        {
          kind: "handed_over",
          level: 1,
          fee: "0",
          balance: "1000",
          note: "Sent",
          at: "2026-11-01T06:00:00Z",
        },
      ],
      hand_over_to_collection: () => [{ id: "i1" }],
      pause_invoice_dunning: () => ({
        ...INVOICE,
        payment_terms_id: "t1",
        discount_due_on: "2026-10-11",
        discount_amount_early: "20",
        collection_status: "handed_over",
        collection_agency_id: "a1",
        collection_handed_at: "2026-11-01T06:00:00Z",
        warnings: [
          {
            code: "INVOICE_CREDIT_LIMIT_EXCEEDED",
            message: "over",
            limit: "1000",
          },
        ],
      }),
    });

    const invoices = createInvoices({ transport: t });
    const [run] = await invoices.dunningRuns("o").orThrow();

    expect(run).toMatchObject({ id: "r1", items: 2, customers: 1 });

    const [customer] = await invoices.dunningRunItems("r1").orThrow();

    expect(customer).toMatchObject({
      partyId: "c1",
      balance: 2000n,
      fee: 500n,
    });
    expect(customer?.items[0]).toMatchObject({
      invoiceId: "i1",
      level: 2,
      balance: 1000n,
    });
    expect(
      (await invoices.dunningHistory("i1").orThrow()).map(
        (entry) => entry.kind,
      ),
    ).toEqual(["reminder", "handed_over"]);
    expect(
      await invoices
        .handOverToCollection(["i1"], "a1", { note: "Sent" })
        .orThrow(),
    ).toEqual(["i1"]);
    expect(t.calls.at(-1)?.[1]).toEqual({
      invoice_ids: ["i1"],
      agency_party_id: "a1",
      note: "Sent",
    });

    const read = await invoices.pauseDunning("i1", null).orThrow();

    expect(read.paymentTerms).toEqual({
      id: "t1",
      discountDueOn: Temporal.PlainDate.from("2026-10-11"),
      discountAmount: eur(20n),
    });
    expect(read.collection).toMatchObject({
      status: "handed_over",
      agencyPartyId: "a1",
    });
    expect(read.warnings).toEqual([
      { code: "INVOICE_CREDIT_LIMIT_EXCEEDED", message: "over", limit: 1000n },
    ]);
  });
});
