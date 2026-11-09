import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("purchase orders", () => {
  it("numbers an order, cancels a quantity, keeps an exchange rate and receives stock", () => {
    const sql = renderBlocks(["inventory"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("exchange_rate");
    expect(sql).toContain("quantity_canceled");
    expect(sql).toContain("tax_code");
    expect(sql).toContain("purchase_orders_number_idx");
    expect(sql).toContain("'receipt'");
  });
});
