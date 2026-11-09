import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[]): string =>
  renderBlocks([...names])
    .map((file) => file.contents)
    .join("\n");

describe("imported document updates", () => {
  it("keeps a document unless the item asks to apply", () => {
    const invoices = sqlOf(["invoices"]);
    const quotes = sqlOf(["quotes"]);
    const orders = sqlOf(["orders"]);

    for (const sql of [invoices, quotes, orders]) {
      expect(sql).toContain("IMPORT_DOCUMENT_CHANGED");
      expect(sql).toContain("is distinct from 'apply'");
    }

    expect(invoices).toContain("set_invoice_lines");
    expect(quotes).toContain("set_quote_lines");
    expect(orders).toContain("repost");
    expect(invoices).toContain("'void', 'paid'");
    expect(invoices).toContain("settlement");
    expect(invoices).toContain("supplied_on");
    expect(invoices).toContain("= 'product'");
  });
});
