import { describe, expect, it } from "vitest";

import {
  createsTable,
  isTableFeature,
  setTableFeature,
  tableFeatures,
} from "../../src/sql/table-features.ts";

const TABLE = "create table public.invoices (id uuid primary key);\n";

describe("setTableFeature", () => {
  it("appends a comment when the file has none", () => {
    const sql = setTableFeature(TABLE, "public", "invoices", "realtime", true);

    expect(sql).toBe(
      `${TABLE}\ncomment on table public.invoices is '@bsb realtime';\n`,
    );
  });

  it("rewrites the comment and keeps the free text", () => {
    const before = `${TABLE}comment on table public.invoices is 'It''s billing. @bsb audit';\n`;

    const after = setTableFeature(
      before,
      "public",
      "invoices",
      "realtime",
      true,
    );

    expect(after).toContain("'It''s billing. @bsb audit; realtime'");
    expect(tableFeatures(after, "public", "invoices")).toEqual([
      "audit",
      "realtime",
    ]);
  });

  it("turns a feature off and leaves a state it already has", () => {
    const on = setTableFeature(TABLE, "public", "invoices", "audit", true);

    expect(setTableFeature(on, "public", "invoices", "audit", true)).toBe(on);
    expect(
      tableFeatures(
        setTableFeature(on, "public", "invoices", "audit", false),
        "public",
        "invoices",
      ),
    ).toEqual([]);
    expect(setTableFeature(TABLE, "public", "invoices", "audit", false)).toBe(
      TABLE,
    );
  });

  it("matches a quoted or unqualified name", () => {
    const before = `${TABLE}comment on table "invoices" is '@bsb json';\n`;

    expect(tableFeatures(before, "public", "invoices")).toEqual(["json"]);
  });
});

describe("helpers", () => {
  it("finds the table and checks feature names", () => {
    expect(createsTable(TABLE, "public", "invoices")).toBe(true);
    expect(createsTable(TABLE, "public", "orders")).toBe(false);
    expect(isTableFeature("realtime")).toBe(true);
    expect(isTableFeature("nope")).toBe(false);
  });
});
