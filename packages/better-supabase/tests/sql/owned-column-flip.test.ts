import { describe, expect, it } from "vitest";

import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

const MODULES = { invoices: {} };

describe("ctx.has over an owned table (ADR 0325 step 2)", () => {
  it("has the invoices module registered", () => {
    expect(SQL_MODULES["invoices"]).toBeDefined();
  });

  const own = (columns?: readonly string[]) =>
    moduleContext(
      "invoices",
      {
        modules: MODULES,
        ownTables: { "better_supabase.invoices": "app.sql" },
        ...(columns
          ? { ownColumns: { "better_supabase.invoices": columns } }
          : {}),
      },
      ["invoices"],
    );

  it("turns a feature off when the app's table lacks its column", () => {
    expect(own(["id", "number"]).has("invoices", "direction")).toBe(false);
  });

  it("keeps the feature when the app declares the column", () => {
    expect(own(["id", "direction"]).has("invoices", "direction")).toBe(true);
  });

  it("keeps it when the table's columns are unknown", () => {
    expect(own().has("invoices", "direction")).toBe(true);
  });

  it("leaves a table the block owns alone", () => {
    const ctx = moduleContext("invoices", { modules: MODULES }, ["invoices"]);

    expect(ctx.has("invoices", "direction")).toBe(true);
  });
});
