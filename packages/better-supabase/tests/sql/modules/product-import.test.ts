import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("product import", () => {
  const sql = renderBlocks(["catalog"])
    .map((file) => file.contents)
    .join("\n");

  it("falls back through prices and refuses a bad name or a duplicate sku", () => {
    const body = sql.slice(sql.indexOf('"import_product"'));

    expect(body).toContain("nullif(v_data ->> 'price', '')");
    expect(body).toContain("nullif(v_data ->> 'listPrice', '')");
    expect(body).toContain("lastPurchasePrice");
    expect(body).toContain("priceFallback");
    expect(body).toContain("mostly control characters");
    expect(body).toContain("a sku is already used");
    expect(body).toContain("[[:cntrl:]]");
  });
});
