import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const payment = (permissions: Readonly<Record<string, string>>): string => {
  const sql = renderBlocks(["invoices"], {
    modules: { invoices: { permissions } },
  })
    .map((file) => file.contents)
    .join("\n");

  const start = sql.indexOf(
    'create or replace function "better_supabase"."record_invoice_payment"',
  );

  return sql.slice(start, sql.indexOf("$$;", start));
};

describe("record_invoice_payment", () => {
  it("checks only the payment key without a settle key", () => {
    const body = payment({ payment: "invoice.record_payment" });

    expect(body).toContain("'invoice.record_payment'");
    expect(body).not.toContain("record_invoice_payment.amount = (");
    expect(body).toContain(") is not true then");
    expect(body.indexOf("for update")).toBeGreaterThan(
      body.indexOf("INVOICE_FORBIDDEN"),
    );
  });

  it("lets the settle key pay the whole balance or replay a recorded payment", () => {
    const body = payment({
      payment: "invoice.record_payment",
      settle: "invoice.mark_paid",
    });

    expect(body).toContain("'invoice.mark_paid'");
    expect(body).toContain("record_invoice_payment.amount = (");
    expect(body).toContain("record_invoice_payment.amount > 0 and");
    expect(body).toContain("INVOICE_FORBIDDEN");
  });
});
