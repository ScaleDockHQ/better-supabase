import { describe, expect, it } from "vitest";

import { unusedDeclaredColumns } from "../../src/sql/index.ts";

describe("unusedDeclaredColumns", () => {
  it("reports a mapped column of a feature that is off", () => {
    expect(
      unusedDeclaredColumns({
        modules: {
          accounting: {
            tables: { budgets: null, budgetLines: null },
            columns: { budgets: { name: "title" } },
          },
        },
      }),
    ).toEqual([
      {
        block: "accounting",
        table: "budgets",
        logical: "name",
        column: "title",
      },
    ]);
  });

  it("keeps a mapped column the render reads", () => {
    expect(
      unusedDeclaredColumns({
        modules: { accounting: { columns: { budgets: { name: "title" } } } },
      }),
    ).toEqual([]);
  });

  it("reports nothing without a columns entry", () => {
    expect(unusedDeclaredColumns({ modules: { accounting: {} } })).toEqual([]);
  });
});
