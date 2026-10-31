import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  names: readonly string[],
  module: string,
  layout: BlockSqlLayout = {},
): string =>
  renderBlocks([...names], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("purchasing in inventory", () => {
  it("adds requisitions, receipts and a drop ship address", () => {
    const sql = sqlOf(["catalog", "inventory", "outbox"], "inventory");

    expect(sql).toContain('"better_supabase"."purchase_requisitions"');
    expect(sql).toContain('"better_supabase"."purchase_requisition_lines"');
    expect(sql).toContain('"better_supabase"."inventory_receipts"');
    expect(sql).toContain('"better_supabase"."inventory_receipt_lines"');
    expect(sql).toContain('"better_supabase"."request_purchase"(');
    expect(sql).toContain(
      '"better_supabase"."purchase_order_from_requisitions"(',
    );
    expect(sql).toContain("'inventory_receipt.created'");
    expect(sql).toContain("'receiptId', v_receipt");
    expect(sql).toContain('"ship_to" jsonb');
  });

  it("decides requisitions through approvals when installed", () => {
    const sql = sqlOf(["catalog", "inventory", "approvals"], "inventory");

    expect(sql).toContain('"better_supabase"."open_approval"(');
    expect(sql).toContain("INVENTORY_REQUISITION_APPROVAL_PENDING");
    expect(sqlOf(["catalog", "inventory"], "inventory")).not.toContain(
      "open_approval",
    );
  });

  it("refuses a blocked supplier with contacts installed", () => {
    const sql = sqlOf(["catalog", "inventory", "contacts"], "inventory");

    expect(sql).toContain("PURCHASE_ORDER_SUPPLIER_BLOCKED");
    expect(sqlOf(["catalog", "inventory"], "inventory")).not.toContain(
      "PURCHASE_ORDER_SUPPLIER_BLOCKED",
    );
  });

  it("opens an incoming inspection of options.receiptInspection", () => {
    const layout = (kind: string): BlockSqlLayout => ({
      modules: { inventory: { options: { receiptInspection: kind } } },
    });

    expect(
      sqlOf(
        ["catalog", "inventory", "inspections"],
        "inventory",
        layout("inspection"),
      ),
    ).toContain('"better_supabase"."schedule_inspection"(');
    expect(() =>
      sqlOf(["catalog", "inventory", "inspections"], "inventory", {
        ...layout("nope"),
      }),
    ).toThrow(/receiptInspection/);
    expect(() =>
      sqlOf(["catalog", "inventory"], "inventory", layout("inspection")),
    ).toThrow(/needs the inspections block/);
  });
});

describe("purchase bills in invoices", () => {
  const names = ["catalog", "inventory", "contacts", "invoices"];

  it("numbers per direction and gates payment on the match", () => {
    const sql = sqlOf([...names, "outbox"], "invoices");

    expect(sql).toContain("\"direction\" text not null default 'sales'");
    expect(sql).toContain('"tenant_id", "direction", "kind", "number"');
    expect(sql).toContain('"better_supabase"."purchase_bill_match"(');
    expect(sql).toContain("INVOICE_MATCH_FAILED");
    expect(sql).toContain("'invoice.match_checked'");
    expect(sql).toContain("'invoices.purchase'");
    expect(sql).toContain("'invoices.override_match'");
  });

  it("checks the sales credit limit with contacts installed", () => {
    expect(sqlOf(names, "invoices")).toContain("INVOICE_CREDIT_LIMIT_EXCEEDED");
    expect(sqlOf(["catalog", "invoices"], "invoices")).not.toContain(
      "INVOICE_CREDIT_LIMIT_EXCEEDED",
    );
  });

  it("validates options.matchTolerance", () => {
    const layout = (matchTolerance: unknown): BlockSqlLayout => ({
      modules: { invoices: { options: { matchTolerance } } },
    });

    expect(sqlOf(names, "invoices", layout({ bps: 250 }))).toContain(
      "* 250 / 10000.0",
    );
    expect(() => sqlOf(names, "invoices", layout({ bps: -1 }))).toThrow(
      /matchTolerance.bps/,
    );
  });
});

describe("purchasing in orders and manufacturing", () => {
  it("checks the order credit limit and drafts drop ship purchase orders", () => {
    const sql = sqlOf(["catalog", "inventory", "contacts", "orders"], "orders");

    expect(sql).toContain("ORDER_CREDIT_LIMIT_EXCEEDED");
    expect(sql).toContain('"better_supabase"."purchase_order_from_order"(');
  });

  it("turns purchase suggestions into requisitions on request", () => {
    const names = ["catalog", "inventory", "manufacturing"];

    const layout: BlockSqlLayout = {
      modules: {
        manufacturing: { options: { purchaseSuggestions: "requisition" } },
      },
    };

    expect(sqlOf(names, "manufacturing", layout)).toContain(
      '"better_supabase"."request_purchase"(',
    );
    expect(sqlOf(names, "manufacturing")).not.toContain("request_purchase");
    expect(() =>
      sqlOf(names, "manufacturing", {
        modules: { manufacturing: { options: { purchaseSuggestions: "x" } } },
      }),
    ).toThrow(/purchaseSuggestions/);
  });
});
