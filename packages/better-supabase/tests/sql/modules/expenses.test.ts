import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (modules: readonly string[], module = "expenses"): string =>
  renderModules(modules, {})
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("expenses module", () => {
  it("evaluates the spend policy on submit and opens an approval", () => {
    const sql = sqlOf(["expenses"]);

    expect(sql).toContain("EXPENSE_POLICY_VIOLATION");
    expect(sql).toContain('"expense_report_violations"(');
    expect(sql).toContain('"open_approval"(');
  });

  it("posts approval and reimbursement on the ledger with keys per report", () => {
    const sql = sqlOf(["expenses"]);

    expect(sql).toContain(`'expense:' || v_row."id"::text || ':approved'`);
    expect(sql).toContain(`'expense:' || v_row."id"::text || ':reimbursed'`);
    expect(sql).toContain("'expenses:payable:'");
  });

  it("keeps the approval runner and the policy check internal", () => {
    const sql = sqlOf(["expenses"]);

    expect(sql).toMatch(
      /revoke execute on function "better_supabase"\."approve_expense_report"\(uuid\) from public, anon, authenticated/,
    );
  });

  it("runs the report's approval through the approvals module", () => {
    const approvals = sqlOf(["expenses"], "approvals");

    expect(approvals).toContain('"approve_expense_report"(');
  });

  it("counts receipts only when attachments is installed", () => {
    expect(sqlOf(["expenses"])).toContain(
      "a receipt threshold needs the attachments block",
    );
    expect(sqlOf(["expenses", "attachments"])).toContain(
      `"subject_type" = 'expense_line'`,
    );
  });
});
