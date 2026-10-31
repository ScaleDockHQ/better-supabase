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

const BILL = {
  id: "b1",
  tenant_id: "o",
  kind: "invoice",
  direction: "purchase",
  supplier_reference: "SUP-77",
  purchase_order_id: "po1",
  dimensions: { project: "P-1" },
  number: null,
  identifier: null,
  title: "Steel",
  company_type: "company",
  company_id: "s1",
  currency: "EUR",
  status: "draft",
  terms_days: 30,
  paid_total: "0",
  credited_total: "0",
  balance: "0",
  overdue: false,
  list_total: "0",
  discount_total: "0",
  subtotal: "0",
  tax_total: "0",
  total: "0",
  created_at: "2026-10-30T09:00:00Z",
  lines: [],
  payments: [],
};

describe("invoices purchase bills", () => {
  it("creates a purchase bill and reads its purchase columns", async () => {
    const t = transport({ create_invoice: () => BILL });

    const bill = await createInvoices({ transport: t })
      .create("o", {
        title: "Steel",
        direction: "purchase",
        company: { type: "company", id: "s1" },
        supplierReference: "SUP-77",
        purchaseOrderId: "po1",
        dimensions: { project: "P-1" },
        currency: "EUR",
      })
      .orThrow();

    expect(t.calls[0]?.[1]["attrs"]).toMatchObject({
      direction: "purchase",
      supplierReference: "SUP-77",
      purchaseOrderId: "po1",
      dimensions: { project: "P-1" },
    });
    expect(bill).toMatchObject({
      direction: "purchase",
      supplierReference: "SUP-77",
      purchaseOrderId: "po1",
      dimensions: { project: "P-1" },
    });
    expect(bill.fields).toEqual({});
  });

  it("reads a sales invoice without purchase columns", async () => {
    const {
      direction: _direction,
      supplier_reference: _reference,
      purchase_order_id: _order,
      dimensions: _dimensions,
      ...row
    } = BILL;

    const t = transport({ create_invoice: () => row });

    const invoice = await createInvoices({ transport: t })
      .create("o", { title: "Steel" })
      .orThrow();

    expect(invoice.direction).toBe("sales");
    expect(invoice.dimensions).toBeUndefined();
  });

  it("runs the three-way match and ages payables", async () => {
    const t = transport({
      purchase_bill_match: () => ({
        invoiceId: "b1",
        currency: "EUR",
        purchaseOrderId: "po1",
        status: "price_variance",
        lines: [
          {
            variantId: "v1",
            quantity: "2",
            billedQuantity: "2",
            orderedQuantity: "2",
            receivedQuantity: "2",
            amount: "2400",
            expectedAmount: "2000",
            status: "price_variance",
          },
        ],
      }),
      invoice_aging: () => ({
        currency: "EUR",
        current: "2400",
        days1To30: "0",
        days31To60: "0",
        days61To90: "0",
        over90: "0",
        outstanding: "2400",
        overdueCount: 0,
      }),
    });

    const invoices = createInvoices({ transport: t });

    expect(await invoices.match("b1").orThrow()).toEqual({
      invoiceId: "b1",
      purchaseOrderId: "po1",
      status: "price_variance",
      lines: [
        {
          variantId: "v1",
          quantity: "2",
          billedQuantity: "2",
          orderedQuantity: "2",
          receivedQuantity: "2",
          amount: eur(2400n),
          expectedAmount: eur(2000n),
          status: "price_variance",
        },
      ],
    });
    expect(
      (await invoices.aging("o", "EUR", undefined, "purchase").orThrow())
        .outstanding,
    ).toEqual(eur(2400n));
    expect(t.calls[1]).toEqual([
      "invoice_aging",
      { tenant: "o", currency: "EUR", as_of: null, direction: "purchase" },
    ]);
  });
});
