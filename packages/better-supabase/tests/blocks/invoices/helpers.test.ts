import { describe, expect, it } from "vitest";

import type {
  EInvoiceChannel,
  EInvoiceFormat,
} from "../../../src/blocks/invoices/index.ts";

import { createInvoices } from "../../../src/blocks/invoices/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

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
  prices_include_tax: true,
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
      note: "Paid in two parts",
      recordedBy: "u1",
    },
  ],
};

const DRAFT = { ...ROW, status: "draft", paid_total: "0", payments: [] };
const SENT = { ...ROW, status: "issued", paid_total: "0", payments: [] };

const format: EInvoiceFormat = {
  apiVersion: 1,
  key: "ubl",
  render: (invoice) => ({
    body: "<Invoice/>",
    filename: `${invoice.identifier}.xml`,
    contentType: "application/xml",
  }),
};

const channel: EInvoiceChannel = {
  apiVersion: 1,
  key: "memory",
  send: () => Promise.resolve({ externalRef: "ref-1" }),
};

function setup() {
  const t = fieldsTransport({
    create_invoice: () => DRAFT,
    issue_invoice: () => SENT,
    record_invoice_payment: () => ({ ...SENT, status: "paid", balance: "0" }),
    record_invoice_delivery: () => ({
      id: "d1",
      invoiceId: "i1",
      channel: "memory",
      format: "ubl",
      externalRef: "ref-1",
      filename: "INV-1.xml",
      sentAt: "2026-10-16T09:00:00Z",
    }),
  });

  return { t, invoices: createInvoices({ transport: t }) };
}

describe("invoices helpers", () => {
  it("createAndIssue creates the draft and issues it", async () => {
    const { t, invoices } = setup();

    const issued = await invoices
      .createAndIssue({
        organizationId: "o",
        input: { title: "October", currency: "EUR" },
        lines: [{ description: "x", unitAmount: money(1000, "EUR") }],
      })
      .orThrow();

    expect(issued.status).toBe("issued");
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "create_invoice",
      "issue_invoice",
    ]);
    expect(t.calls[1]?.[1]).toMatchObject({ invoice: "i1" });
  });

  it("markPaid records the whole balance under a stable reference", async () => {
    const { t, invoices } = setup();

    const paid = await invoices
      .markPaid({
        invoice: { id: "i1", balance: money(1000, "EUR") },
        method: "bank",
      })
      .orThrow();

    expect(paid.status).toBe("paid");
    expect(t.calls[0]).toEqual([
      "record_invoice_payment",
      expect.objectContaining({
        invoice: "i1",
        amount: "1000",
        currency: "EUR",
        method: "bank",
        reference: "paid:i1",
      }),
    ]);
  });

  it("issueAndSend issues the invoice and sends it as an e-invoice", async () => {
    const { t, invoices } = setup();

    const done = await invoices
      .issueAndSend({ invoiceId: "i1", format, channel })
      .orThrow();

    expect(done.invoice.status).toBe("issued");
    expect(done.delivery).toMatchObject({
      invoiceId: "i1",
      externalRef: "ref-1",
      deliveryId: "d1",
    });
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "issue_invoice",
      "record_invoice_delivery",
    ]);
  });

  it("issueAndSend doesn't send when issuing fails", async () => {
    const t = fieldsTransport({});
    const invoices = createInvoices({ transport: t });

    const done = await invoices.issueAndSend({
      invoiceId: "i1",
      format,
      channel,
    });

    expect(done.ok).toBe(false);
    expect(t.calls.map(([fn]) => fn)).toEqual(["issue_invoice"]);
  });
});
