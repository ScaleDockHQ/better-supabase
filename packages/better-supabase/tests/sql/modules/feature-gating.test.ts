import { describe, expect, it, test } from "vitest";

import { moduleBody } from "../../../src/sql/index.ts";

const render = (module: string, tables: Record<string, null>): string =>
  moduleBody(module, {
    // SAFETY: the test passes only tables the module declares.
    modules: { [module]: { tables } },
  })!;

const lines = (sql: string): number => sql.split("\n").length;

describe.each([
  {
    module: "inventory",
    off: { allocations: null },
    gone: [
      "stock_allocations",
      "allocate_stock",
      "fulfill_allocation",
      "import_stock_allocation",
    ],
  },
  {
    module: "invoices",
    off: {
      eEndpoints: null,
      eDeliveries: null,
      dunningLevels: null,
      dunningRuns: null,
      dunningRunItems: null,
      dunningHistory: null,
    },
    gone: [
      "e_invoice_endpoints",
      "e_invoice_deliveries",
      "dunning_runs",
      "dunning_history",
    ],
  },
  {
    module: "accounting",
    off: { budgets: null, budgetLines: null },
    gone: [
      "accounting_budgets",
      "accounting_budget_lines",
      "save_accounting_budget",
      "accounting_budget_vs_actual",
    ],
  },
])("a disabled feature of $module", ({ module, off, gone }) => {
  const full = render(module, {});
  const gated = render(module, off);

  it.each(gone)("renders no %s", (name) => {
    expect(full).toContain(name);
    expect(gated).not.toContain(name);
  });

  it("renders fewer lines", () => {
    expect(lines(gated)).toBeLessThan(lines(full));
  });
});

test("keeps the budgets when only one of their tables is on", () => {
  expect(render("accounting", { budgetLines: null })).not.toContain(
    "save_accounting_budget",
  );
});
