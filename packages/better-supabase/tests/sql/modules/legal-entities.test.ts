import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "settings", "legal-entities"];

const withOn = (on: readonly string[]): Layout => ({
  modules: { "legal-entities": { options: { on } } },
});

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "legal-entities")
    .map((file) => file.contents)
    .join("\n");

describe("legal-entities module", () => {
  it("keeps one default legal entity per organization", () => {
    const sql = sqlOf();

    expect(sql).toMatch(/unique index[^;]*"is_default"/is);
    expect(sql).toContain('"better_supabase"."legal_entity_of"(');
    expect(sql).toContain('"better_supabase"."resolve_setting"(');
  });

  it("adds no legal_entity_id column without options.on", () => {
    expect(sqlOf()).not.toContain("add column if not exists");
  });

  it("adds a nullable legal_entity_id to the tables options.on names", () => {
    const sql = sqlOf(withOn(["numbering"]), [
      ...BASE.slice(0, -1),
      "numbering",
      "legal-entities",
    ]);

    expect(sql).toMatch(
      /alter table "better_supabase"\."number_sequences" add column if not exists legal_entity_id uuid;/,
    );
  });

  it("refuses an unknown key and a module that isn't installed", () => {
    expect(() => sqlOf(withOn(["nothing"]))).toThrow(/not one of/);
    expect(() => sqlOf(withOn(["invoices"]))).toThrow(/needs the invoices/);
  });

  it("renders nothing in custom mode", () => {
    expect(sqlOf({ modules: { "legal-entities": { mode: "custom" } } })).toBe(
      "",
    );
  });

  it("refuses custom-mode settings or a custom-mode target table", () => {
    expect(() => sqlOf({ modules: { settings: { mode: "custom" } } })).toThrow(
      /settings can't be in custom mode/,
    );
    expect(() =>
      sqlOf(
        {
          modules: {
            "legal-entities": { options: { on: ["numbering"] } },
            numbering: { mode: "custom" },
          },
        },
        [...BASE.slice(0, -1), "numbering", "legal-entities"],
      ),
    ).toThrow(/numbering can't be in custom mode/);
  });
});
