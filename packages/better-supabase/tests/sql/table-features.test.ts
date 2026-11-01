import { describe, expect, it } from "vitest";

import {
  createsTable,
  isTableFeature,
  setFeatureStatement,
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

describe("setFeatureStatement", () => {
  const file = "create table public.t (id uuid);\n";

  it("adds the audit call once and removes it again", () => {
    const on = setFeatureStatement(file, "public", "t", "audit", true);

    expect(on).toContain("select better_supabase.audit('public.t');");
    expect(setFeatureStatement(on, "public", "t", "audit", true)).toBe(on);
    expect(setFeatureStatement(on, "public", "t", "audit", false).trim()).toBe(
      file.trim(),
    );
  });

  it.each([
    ["events", "better_supabase.track_events('public.t')"],
    ["audit-reads", "better_supabase.record_subject_read('t', p_id"],
  ] as const)("adds and removes the %s statement", (feature, text) => {
    const on = setFeatureStatement(file, "public", "t", feature, true);

    expect(on).toContain(text);
    expect(setFeatureStatement(on, "public", "t", feature, true)).toBe(on);
    expect(setFeatureStatement(on, "public", "t", feature, false).trim()).toBe(
      file.trim(),
    );
  });

  it("leaves features without a statement alone", () => {
    expect(setFeatureStatement(file, "public", "t", "realtime", true)).toBe(
      file,
    );
  });
});
