import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { renderBlocks } from "../../src/sql/render.ts";

const MODULES = [
  "orders",
  "quotes",
  "invoices",
  "shipments",
  "billable-time",
  "inventory",
  "catalog",
];

const render = (layout: BlockSqlLayout, names = MODULES): string =>
  renderBlocks(names, layout)
    .map((file) => file.contents)
    .join("\n");

describe("variants and collective invoicing across layouts", () => {
  it("installs the variant and source functions by default", () => {
    const sql = render({});

    for (const fn of [
      "create_quote_variant",
      "select_quote_variant",
      "list_quote_variants",
      "set_order_variant",
      "select_order_variant",
      "list_order_variants",
      "invoice_from_sources",
      "sources_ready_to_invoice",
    ]) {
      expect(sql).toContain(fn);
    }

    expect(sql).toContain("invoice_line_sources");
    expect(sql).toContain("QUOTE_VARIANT_NOT_SELECTED");
  });

  it("leaves variants out where the tables have no variant columns", () => {
    const sql = render({
      modules: {
        orders: {
          columns: {
            orders: { variantOf: null, variantLabel: null, isSelected: null },
          },
        },
        quotes: {
          columns: {
            quotes: { variantOf: null, variantLabel: null, isSelected: null },
          },
        },
      },
    });

    expect(sql).not.toContain("set_order_variant");
    expect(sql).not.toContain("create_quote_variant");
    expect(sql).not.toContain("QUOTE_VARIANT_NOT_SELECTED");
    expect(sql).toContain("invoice_from_sources");
  });

  it("skips what the installed modules can't supply", () => {
    const sql = render({}, ["orders", "invoices"]);

    expect(sql).toContain("invoice_from_sources");
    expect(sql).not.toContain("claim_time_for_invoice");
  });
});
