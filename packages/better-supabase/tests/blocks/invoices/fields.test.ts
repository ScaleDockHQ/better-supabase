import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createInvoices } from "../../../src/blocks/invoices/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const ROW = {
  id: "i1",
  tenant_id: "o",
  kind: "invoice",
  title: "October",
  currency: "EUR",
  status: "draft",
  terms_days: 30,
  paid_total: 0,
  credited_total: 0,
  created_at: "2026-10-15T09:00:00Z",
  updated_at: "2026-10-15T09:00:00Z",
  balance: "0",
  overdue: false,
  lines: [],
  payments: [],
  po_number: "PO-7",
};

const Fields = v.object({ po_number: v.pipe(v.string(), v.startsWith("PO-")) });

describe("invoices fields", () => {
  it("writes the extra fields by column name and parses every read", async () => {
    const t = fieldsTransport({
      create_invoice: () => ROW,
      void_invoice: () => ROW,
    });
    const invoices = createInvoices({ transport: t, fields: Fields });
    const created = await invoices
      .create("o", { title: "October", fields: { po_number: "PO-7" } })
      .orThrow();
    expect(created.fields.po_number).toBe("PO-7");
    expect(t.calls[0]?.[1]["attrs"]).toEqual({
      title: "October",
      po_number: "PO-7",
    });
    expect((await invoices.void("i1").orThrow()).fields.po_number).toBe("PO-7");
  });

  it("refuses a bad field before the call", async () => {
    const t = fieldsTransport({ create_invoice: () => ROW });
    const created = await createInvoices({
      transport: t,
      fields: Fields,
    }).create("o", { title: "October", fields: { po_number: "7" } });
    expect(created.ok ? undefined : created.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
  });
});
