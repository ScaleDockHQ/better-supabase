import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { RFQS } from "../../../src/sql/modules/rfqs.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "rfqs"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "rfqs")
    .map((file) => file.contents)
    .join("\n");

describe("rfqs module", () => {
  it("renders the tables and the status checks", () => {
    const sql = sqlOf();

    expect(sql).toContain("rfqs");
    expect(sql).toContain("rfq_lines");
    expect(sql).toContain("rfq_suppliers");
    expect(sql).toContain("rfq_quotes");
    expect(sql).toContain("rfq_quote_lines");
    expect(sql).toContain("'draft', 'open', 'closed', 'awarded', 'cancelled'");
    expect(sql).toContain("'submitted', 'withdrawn', 'awarded', 'rejected'");
  });

  it("totals a quote from unit amounts and quantities", () => {
    expect(sqlOf()).toContain("round(sum(");
  });

  it("refuses to create a purchase order without the inventory block", () => {
    expect(sqlOf()).toContain("needs the inventory block");
    expect(sqlOf()).not.toContain("save_purchase_order");
  });

  it("creates the purchase order through inventory when it is installed", () => {
    const sql = sqlOf([...BASE, "inventory"]);

    expect(sql).toContain("save_purchase_order");
    expect(sql).toContain("every line needs a variantId");
  });

  it("checks suppliers against contacts only when it is installed", () => {
    expect(sqlOf()).not.toContain("RFQ_SUPPLIER_INVALID");
    expect(sqlOf([...BASE, "contacts"])).toContain("RFQ_SUPPLIER_INVALID");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { rfqs: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(RFQS.build(context, {})).toBe("");
    const [contract] = customContracts(["rfqs"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_rfq",
        "record_rfq_quote",
        "compare_rfq",
        "award_rfq",
      ]),
    );
  });
});
