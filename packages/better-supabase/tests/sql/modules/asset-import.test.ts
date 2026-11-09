import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("asset import", () => {
  it("stores make, model, ownership and identifiers", () => {
    const sql = renderBlocks(["assets"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("make");
    expect(sql).toContain("model_year");
    expect(sql).toContain("'trade_in'");
    expect(sql).toContain("asset_identifiers");
    expect(sql).toContain("import_asset");
    expect(sql).toContain("import_asset_identifier");
  });
});
