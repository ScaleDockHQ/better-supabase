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

      return result
        ? Promise.resolve(result(args))
        : Promise.reject(new Error(`unexpected ${fn}`));
    },
  };
}

describe("invoices open items", () => {
  it("reads a party's open items with the discount and bucket", async () => {
    const t = transport({
      open_items_for_party: () => [
        {
          side: "supplier",
          partyId: "c1",
          documentType: "invoice",
          documentId: "i1",
          identifier: "BILL-7",
          currency: "EUR",
          issuedOn: "2026-10-01",
          dueOn: "2026-10-31",
          amount: "100000",
          balance: "60000",
          daysOverdue: 0,
          bucket: "current",
          discountDueOn: "2026-10-11",
          discountAmount: "2000",
          approvalStatus: "approved",
        },
        {
          side: "supplier",
          partyId: "c1",
          documentType: "unallocated_payment",
          documentId: "p1",
          identifier: "ref-1",
          currency: "EUR",
          amount: "-500",
          balance: "-500",
          daysOverdue: 0,
          bucket: "unallocated",
        },
      ],
    });

    const items = await createInvoices({ transport: t })
      .openItems("o", {
        partyId: "c1",
        side: "supplier",
        asOf: Temporal.PlainDate.from("2026-10-05"),
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      party_id: "c1",
      as_of: "2026-10-05",
      side: "supplier",
    });
    expect(items[0]?.balance).toEqual(eur(60_000n));
    expect(items[0]?.discountAmount).toEqual(eur(2000n));
    expect(items[0]?.discountDueOn?.toString()).toBe("2026-10-11");
    expect(items[0]?.approvalStatus).toBe("approved");
    expect(items[1]?.balance).toEqual(eur(-500n));
    expect(items[1]?.bucket).toBe("unallocated");
  });

  it("reads the ageing buckets per party", async () => {
    const t = transport({
      open_item_ageing: () => [
        {
          side: "customer",
          partyId: "c1",
          currency: "EUR",
          current: "100",
          days1To30: "200",
          days31To60: "0",
          days61To90: "0",
          over90: "50",
          unallocated: "-30",
          outstanding: "320",
        },
      ],
    });

    const [row] = await createInvoices({ transport: t })
      .openItemAgeing("o")
      .orThrow();

    expect(row?.days1To30).toEqual(eur(200n));
    expect(row?.unallocated).toEqual(eur(-30n));
    expect(row?.outstanding).toEqual(eur(320n));
  });

  it("allocates a payment and reads what it covered", async () => {
    const t = transport({
      allocate_payment: () => ({
        reference: "bank-1",
        currency: "EUR",
        partyId: "c1",
        allocated: "9800",
        discount: "200",
        credited: "0",
        allocations: [
          {
            invoiceId: "i1",
            source: "payment",
            amount: "9800",
            discount: "200",
            paymentId: "p1",
            allocatedOn: "2026-10-10",
          },
        ],
      }),
    });

    const result = await createInvoices({ transport: t })
      .allocatePayment("o", {
        partyId: "c1",
        amount: eur(9800n),
        allocations: [
          { invoiceId: "i1", amount: eur(9800n) },
          { invoiceId: "i2", amount: eur(0n), takeDiscount: false },
        ],
        receivedOn: Temporal.PlainDate.from("2026-10-10"),
        reference: "bank-1",
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      payment: {
        partyId: "c1",
        side: "customer",
        amount: "9800",
        currency: "EUR",
        receivedOn: "2026-10-10",
        reference: "bank-1",
        method: null,
        note: null,
        source: "payment",
      },
      allocations: [
        { invoiceId: "i1", amount: "9800", takeDiscount: true },
        { invoiceId: "i2", amount: "0", takeDiscount: false },
      ],
    });
    expect(result.discount).toEqual(eur(200n));
    expect(result.allocations[0]?.allocatedOn?.toString()).toBe("2026-10-10");
  });

  it("unallocates a reference and lists allocations", async () => {
    const t = transport({
      unallocate_payment: () => ({ reference: "bank-1", unallocated: 2 }),
      list_invoice_allocations: () => [
        {
          currency: "EUR",
          reference: "bank-1",
          invoiceId: "i1",
          source: "credit",
          amount: "100",
          discount: "0",
          unallocatedAt: "2026-10-31T10:00:00Z",
        },
      ],
    });

    const invoices = createInvoices({ transport: t });

    expect(await invoices.unallocatePayment("o", "bank-1").orThrow()).toBe(2);

    const [row] = await invoices
      .allocations("o", { reference: "bank-1" })
      .orThrow();

    expect(row?.source).toBe("credit");
    expect(row?.amount).toEqual(eur(100n));
    expect(row?.unallocatedAt).toBeDefined();
  });

  it("sets approval levels and reads where a bill stands", async () => {
    const t = transport({
      set_invoice_approval_levels: () => [
        { level: 1, minAmount: "0", approverId: "u1" },
        { level: 2, minAmount: "100000", currency: "EUR", approverId: "u2" },
      ],
      purchase_invoice_approval_status: () => ({
        status: "pending",
        required: [1, 2],
        approved: [1],
        pending: [{ level: 2, approverId: "u2", minAmount: "100000" }],
      }),
      approve_purchase_invoice: (args) => ({ id: args["invoice"] }),
    });

    const invoices = createInvoices({ transport: t });

    const levels = await invoices
      .setApprovalLevels(
        "o",
        [
          { minAmount: 0n, approverId: "u1" },
          { minAmount: 100_000n, currency: "EUR", approverId: "u2" },
        ],
        { legalEntityId: "le1" },
      )
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      levels: [
        { minAmount: "0", approverId: "u1" },
        { minAmount: "100000", currency: "EUR", approverId: "u2" },
      ],
      legal_entity_id: "le1",
    });
    expect(levels[1]?.minAmount).toBe(100_000n);

    expect(await invoices.approvalStatus("i1").orThrow()).toEqual({
      status: "pending",
      required: [1, 2],
      approved: [1],
      pending: [{ level: 2, approverId: "u2" }],
    });
  });

  it("reads the levels, approves without a comment and refuses an unknown bucket", async () => {
    const t = transport({
      list_invoice_approval_levels: () => [
        { level: 1, minAmount: "0", approverId: "u1" },
      ],
      approve_purchase_invoice: (args) => ({ id: args["invoice"] }),
      open_items_for_party: () => [
        {
          side: "customer",
          partyId: "c1",
          documentType: "invoice",
          documentId: "i1",
          identifier: "INV-1",
          currency: "EUR",
          amount: "1",
          balance: "1",
          daysOverdue: 0,
          bucket: "later",
        },
      ],
    });

    const invoices = createInvoices({ transport: t });

    expect(await invoices.approvalLevels("o").orThrow()).toHaveLength(1);
    await invoices.approvePurchaseInvoice("i1");
    expect(t.calls.at(-1)?.[1]).toEqual({ invoice: "i1", comment: null });
    expect((await invoices.openItems("o")).ok).toBe(false);
  });

  it("passes every optional argument and tolerates sparse rows", async () => {
    const t = transport({
      allocate_payment: () => ({
        reference: "r",
        currency: "EUR",
        partyId: "c1",
        allocated: "0",
        discount: "0",
        credited: "0",
        allocations: [],
      }),
      unallocate_payment: () => ({ unallocated: 0 }),
      list_invoice_allocations: () => [],
      set_invoice_approval_levels: () => [],
      purchase_invoice_approval_status: () => ({ status: "weird" }),
      open_items_for_party: () => [
        {
          side: "supplier",
          partyId: "c1",
          documentType: "invoice",
          documentId: "i1",
          identifier: "B",
          currency: "EUR",
          amount: "1",
          balance: "1",
          bucket: "current",
          approvalStatus: "pending",
        },
      ],
    });

    const invoices = createInvoices({ transport: t });
    const actor = { id: "u1", name: "Ada" };

    await invoices.allocatePayment("o", {
      partyId: "c1",
      amount: eur(0n),
      reference: "r",
      allocations: [],
      receivedOn: Temporal.PlainDate.from("2026-10-10"),
      actor,
    });
    await invoices.unallocatePayment("o", "r", { actor });
    await invoices.allocations("o", { reference: "r" });
    await invoices.setApprovalLevels("o", [], { legalEntityId: "le1" });

    const status = await invoices.approvalStatus("i1").orThrow();
    const [item] = await invoices.openItems("o").orThrow();

    expect(status).toEqual({
      status: "not_required",
      required: [],
      approved: [],
      pending: [],
    });
    expect(item?.approvalStatus).toBe("pending");
    expect(item?.daysOverdue).toBe(0);
    expect(t.calls.some(([, args]) => args["legal_entity_id"] === "le1")).toBe(
      true,
    );
    expect(t.calls.some(([, args]) => args["actor"] === actor)).toBe(true);
  });

  it("recomputes totals as a dry run unless told to apply", async () => {
    const t = transport({
      recompute_invoice_totals: () => ({
        dryRun: true,
        checked: 2,
        changed: 1,
        applied: 0,
        invoices: [
          {
            invoiceId: "i1",
            identifier: "INV-1",
            currency: "EUR",
            status: "issued",
            old: { subtotal: "100000", taxTotal: "21000", total: "121000" },
            new: { subtotal: "100000", taxTotal: "15750", total: "115750" },
            balance: "121000",
            balanceAfter: "115750",
            ledger: {
              posted: true,
              entryId: "e1",
              entryNumber: "SAL-2026-00001",
              periodStatus: "closed",
              needsCorrectingEntry: true,
            },
          },
        ],
      }),
    });

    const invoices = createInvoices({ transport: t });
    const repair = await invoices.recomputeTotals("o").orThrow();
    await invoices.recomputeTotals("o", { invoiceIds: ["i1"], dryRun: false });

    expect(repair.dryRun).toBe(true);
    expect(repair.applied).toBe(0);
    expect(repair.invoices[0]?.old.total).toEqual(eur(121_000n));
    expect(repair.invoices[0]?.new.total).toEqual(eur(115_750n));
    expect(repair.invoices[0]?.ledger.needsCorrectingEntry).toBe(true);
    expect(t.calls[0]).toEqual([
      "recompute_invoice_totals",
      { tenant: "o", invoice_ids: null, dry_run: true },
    ]);
    expect(t.calls[1]?.[1]).toEqual({
      tenant: "o",
      invoice_ids: ["i1"],
      dry_run: false,
    });
  });
});

describe("allocatePayment answers without a credited total", () => {
  it("leaves credited unset and keeps the rest", async () => {
    const t = transport({
      allocate_payment: () => ({
        reference: "bank-2",
        currency: "EUR",
        partyId: "c1",
        allocated: "100",
        discount: "0",
        allocations: [],
      }),
    });

    const result = await createInvoices({ transport: t })
      .allocatePayment("o", {
        partyId: "c1",
        amount: eur(100n),
        allocations: [{ invoiceId: "i1", amount: eur(100n) }],
        receivedOn: Temporal.PlainDate.from("2026-10-10"),
        reference: "bank-2",
      })
      .orThrow();

    expect(result.credited).toBeUndefined();
    expect(result.allocated).toEqual(eur(100n));
  });
});

describe("optional arguments left out", () => {
  it("sends null for the filters and entity that were not given", async () => {
    const t = transport({
      list_invoice_allocations: () => [],
      set_invoice_approval_levels: () => [],
      recompute_invoice_totals: () => ({
        dryRun: true,
        checked: 1,
        changed: 1,
        applied: 0,
        invoices: [
          {
            invoiceId: "i1",
            identifier: "INV-1",
            currency: "EUR",
            status: "issued",
            old: {
              listTotal: "100",
              discountTotal: "0",
              subtotal: "100",
              taxTotal: "21",
              total: "121",
            },
            new: {
              listTotal: "100",
              discountTotal: "10",
              subtotal: "90",
              taxTotal: "19",
              total: "109",
            },
            balance: "121",
            balanceAfter: "109",
            ledger: { posted: false, needsCorrectingEntry: false },
          },
        ],
      }),
      allocate_payment: () => ({
        reference: "r",
        currency: "EUR",
        partyId: "c1",
        allocated: "0",
        discount: "0",
        allocations: [],
      }),
    });

    const invoices = createInvoices({ transport: t });

    await invoices.allocations("o").orThrow();
    await invoices.setApprovalLevels("o", []).orThrow();
    const repair = await invoices.recomputeTotals("o").orThrow();
    await invoices
      .allocatePayment("o", {
        partyId: "c1",
        amount: eur(0n),
        allocations: [],
        reference: "r",
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      reference: null,
      invoice_id: null,
    });
    expect(t.calls[1]?.[1]).toMatchObject({ legal_entity_id: null });
    expect(repair.invoices[0]?.new.discountTotal).toEqual(eur(10n));
    expect(t.calls[3]?.[1]).toMatchObject({ payment: { receivedOn: null } });
  });
});
