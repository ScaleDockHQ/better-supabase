import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/index.ts";

type Layout = NonNullable<Parameters<typeof renderBlocks>[1]>;

const sqlOf = (
  modules: readonly string[],
  layout: Layout,
  module: string,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("cancel_approval reaches the subject", () => {
  const expenses: Layout = {
    modules: {
      expenses: {
        tables: { reports: null, lines: null },
        options: { standaloneApprovals: true },
      },
    },
  };

  it("withdraws a submitted expense", () => {
    const names = ["approvals", "expenses"];
    const approvals = sqlOf(names, expenses, "approvals");
    const own = sqlOf(names, expenses, "expenses");

    expect(approvals).toContain(`"expense_approval_cancelled"(`);
    expect(own).toContain(
      'function "better_supabase"."expense_approval_cancelled"',
    );
  });

  it("opens a week again that is kept in a status column", () => {
    const layout: Layout = {
      modules: { "time-entries": { options: { owner: "employee" } } },
    };

    const names = ["approvals", "employees", "time-entries"];

    expect(sqlOf(names, layout, "approvals")).toContain(
      `"timesheet_approval_cancelled"(`,
    );

    const own = sqlOf(names, layout, "time-entries");
    expect(own).toContain("timesheet_approval_cancelled");
  });

  it("leaves the hook out without approvals", () => {
    expect(sqlOf(["time-entries"], {}, "time-entries")).not.toContain(
      "timesheet_approval_cancelled",
    );
  });
});
