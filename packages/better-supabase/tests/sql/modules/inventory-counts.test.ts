import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sql = renderBlocks(["catalog", "inventory"])
  .filter((file) => file.module === "inventory")
  .map((file) => file.contents)
  .join("\n");

describe("stock counts", () => {
  it("stores a generated variance of counted minus expected", () => {
    expect(sql).toContain("generated always as");
    expect(sql).toMatch(/"counted"\s*-\s*"expected"|counted\s*-\s*expected/);
  });

  it("posts adjustments once through the stock function", () => {
    expect(sql).toContain('"post_stock_count"(count uuid)');
    expect(sql).toContain("'posted', false");
    expect(sql).toContain("'stock_count'");
  });

  it("registers an import target", () => {
    expect(sql).toContain("import_stock_count");
  });
});
