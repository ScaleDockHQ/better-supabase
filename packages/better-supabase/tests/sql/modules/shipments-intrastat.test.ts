import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[]): string =>
  renderBlocks([...names])
    .filter((file) => file.module === "shipments")
    .map((file) => file.contents)
    .join("\n");

describe("intrastat lines", () => {
  const sql = sqlOf(["catalog", "inventory", "shipments"]);

  it("derives lines and lists exceptions for missing data", () => {
    expect(sql).toContain('"prepare_intrastat"');

    for (const code of [
      "INTRASTAT_TRADE_CODE_MISSING",
      "INTRASTAT_COUNTRY_MISSING",
      "INTRASTAT_NET_MASS_MISSING",
      "INTRASTAT_VALUE_MISSING",
    ]) {
      expect(sql).toContain(code);
    }
  });

  it("derives arrival lines from receipts and lets manual lines win", () => {
    expect(sql).toContain("receipt_line_id");
    expect(sql).toContain("'receipt'");
    expect(sql).toContain("manual_line");
    expect(sql).toContain("'superseded'");
    expect(sql).toContain("prepare_intrastat");
    expect(sql).toContain("'supersedes'");
  });

  it("is left out without inventory", () => {
    expect(sqlOf(["shipments"])).not.toContain("intrastat_lines");
  });
});
