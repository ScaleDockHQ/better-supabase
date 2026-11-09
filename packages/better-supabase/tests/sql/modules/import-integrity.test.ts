import { describe, expect, it } from "vitest";

import { integrityReport } from "../../../src/blocks/imports/integrity.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

describe("import integrity", () => {
  it("checks duplicate keys, the ledger, invoices and archived parties", () => {
    const sql = renderBlocks(["imports", "ledger", "invoices", "contacts"])
      .map((file) => file.contents)
      .join("\n");

    for (const name of [
      "duplicate_keys",
      "unbalanced_ledger",
      "negative_invoice",
      "issued_without_number",
      "archived_without_date",
    ]) {
      expect(sql).toContain(name);
    }
  });

  it("reads the report shape a CLI prints", () => {
    expect(
      integrityReport({
        checks: [
          { name: "duplicate_keys", severity: "error", count: 1, ids: ["a"] },
        ],
      }).checks,
    ).toEqual([
      { name: "duplicate_keys", severity: "error", count: 1, ids: ["a"] },
    ]);
  });
});
