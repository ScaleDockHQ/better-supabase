import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("historical accounting import", () => {
  const sql = renderBlocks(["accounting"])
    .map((file) => file.contents)
    .join("\n");

  it("opens the fiscal year of an entry and refuses an unbalanced opening set", () => {
    expect(sql).toContain("ensure_import_periods");
    expect(sql).toContain("close_historical");
    expect(sql).toContain("for v_index in 0..11 loop");
    expect(sql).toContain("ACCOUNTING_ENTRY_UNBALANCED");
    expect(sql).toContain("import_run() is null");
  });
});
