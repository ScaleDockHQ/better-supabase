import { describe, expect, it } from "vitest";

import {
  createExpenses,
  expensesBinding,
  expensesBlock,
} from "../../../src/blocks/expenses/index.ts";

function transport(calls: [string, Record<string, unknown>][]) {
  return {
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve([]);
    },
  };
}

describe("expensesBinding", () => {
  it("reads the member's reports in the block's organization", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const client = createExpenses({
      tenant: "org-1",
      transport: transport(calls),
    });

    const loaded = await expensesBinding.load(
      client,
      { type: "user", id: "s1" },
      undefined,
    );

    expect(loaded.ok && loaded.data).toEqual([]);

    expect(calls).toEqual([
      [
        "list_expense_reports",
        {
          tenant: "org-1",
          user_id: "s1",
          status: null,
          everyone: false,
          page_size: null,
        },
      ],
    ]);
    expect(expensesBlock.record).toBe(expensesBinding);
    expect(expensesBinding.events).toEqual(["expense_report.*"]);
  });

  it("fails without an organization", async () => {
    const client = createExpenses({ transport: transport([]) });

    const loaded = await expensesBinding.load(
      client,
      { type: "user", id: "s1" },
      undefined,
    );

    expect(loaded.ok).toBe(false);
  });
});
