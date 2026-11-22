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
        gating: "tables.budgets: null",
      },
    ]);
  });

  it("names the option that switches the feature on", () => {
    expect(
      unusedDeclaredColumns({
        modules: {
          notifications: { columns: { recipients: { address: "email" } } },
        },
      }),
    ).toEqual([
      {
        block: "notifications",
        table: "recipients",
        logical: "address",
        column: "email",
        gating: "options.externalRecipients",
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

  it("skips block instances and blocks that do not render", () => {
    expect(
      unusedDeclaredColumns({
        modules: {
          books: { block: "accounting" },
          nope: { columns: { things: { name: "title" } } },
        },
      }),
    ).toEqual([]);
  });
});
