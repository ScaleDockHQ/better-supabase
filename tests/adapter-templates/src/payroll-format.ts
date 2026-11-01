import type { PayrollExportFormat } from "better-supabase/blocks/payroll-export";

/**
 * A `PayrollExportFormat` that writes the file layout of one payroll provider
 * (ADR 0155). `render` is pure: the same run gives the same bytes, because the
 * block hashes the file and locks the run behind that hash.
 */
export const examplePayrollFormat: PayrollExportFormat = {
  apiVersion: 1,
  name: "example-payroll",
  render(run) {
    const rows = run.lines
      .filter((line) => line.paid)
      .map(
        (line) =>
          `${line.employeeId ?? line.userId ?? "unknown"}|${line.code ?? line.kind}|${line.quantity.toFixed(2)}|${line.unit}`,
      );

    return {
      filename: `payroll-${run.periodFrom.toString()}-${run.periodTo.toString()}.txt`,
      contentType: "text/plain",
      body: `${rows.join("\n")}\n`,
    };
  },
};
