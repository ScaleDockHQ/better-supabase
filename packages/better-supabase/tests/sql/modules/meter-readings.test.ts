import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("meter readings", () => {
  it("stores a lower reading with IMPORT_SERIES_DECREASE", () => {
    const sql = renderBlocks(["assets", "imports"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("IMPORT_SERIES_DECREASE");
    expect(sql).toContain("import_meter_reading");
    expect(sql).toContain("ASSET_METER_DECREASE_REASON");
    expect(sql).toContain("when 'meter_reading' then");
  });
});
