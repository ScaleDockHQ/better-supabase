import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("ledger entries", () => {
  it("indexes entries by tenant and effective time and reads them by id", () => {
    const text = renderBlocks(["ledger"])
      .map((file) => file.contents)
      .join("\n");

    expect(text).toContain('"effective_at"');
    expect(text).toContain("get_many");
    expect(text).toMatch(/ledger_entries[\s\S]*tenant_id[\s\S]*effective_at/);
  });
});
