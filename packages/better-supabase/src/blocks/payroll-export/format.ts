import type { PayrollLine, PayrollRun } from "./payroll-export.ts";

/** A rendered export: what to save or send to the payroll provider. */
export interface PayrollExportFile {
  /** A file name without a path, such as `payroll-2026-10.csv`. */
  readonly filename: string;
  /** The media type, such as `text/csv`. */
  readonly contentType: string;
  readonly body: string;
}

/**
 * Renders the lines of a run in the file layout of one payroll provider.
 * Versioned: a breaking change ships a new `apiVersion`. `better-supabase`
 * bundles a CSV reference format; a provider package implements the layout of
 * its own import file, and `exportRun` calls it, hashes the file and locks the
 * run.
 */
export interface PayrollExportFormat {
  readonly apiVersion: 1;
  /** The format's name, such as `loonzaken-csv`; kept on the run. */
  readonly name: string;
  render(run: PayrollRun): PayrollExportFile | Promise<PayrollExportFile>;
}

/** Checks the format's `apiVersion` before rendering with it. */
export function payrollFormatOf(
  format: PayrollExportFormat,
): PayrollExportFormat {
  const version: unknown = format.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `payroll export format "${format.name}" targets payroll export format API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the format for API 1.`,
    );
  }

  return format;
}

export interface CsvPayrollFormatOptions {
  /** Default `;`, which spreadsheets in most European locales open directly. */
  readonly delimiter?: "," | ";" | "\t";
  /** The decimal separator of quantities. Default `.`. */
  readonly decimal?: "." | ",";
  /** The name the format keeps on the run. Default `csv`. */
  readonly name?: string;
}

const COLUMNS = [
  "employee_id",
  "user_id",
  "employee_name",
  "kind",
  "code",
  "paid",
  "unit",
  "quantity",
] as const;

function cell(value: string, delimiter: string): string {
  // A cell that starts with a formula character would run in a spreadsheet.
  const safe = /^[=+@-]/.test(value) ? `'${value}` : value;

  return /["\r\n]/.test(safe) || safe.includes(delimiter)
    ? `"${safe.replaceAll('"', '""')}"`
    : safe;
}

function row(
  line: PayrollLine,
  options: Required<CsvPayrollFormatOptions>,
): string {
  const quantity = line.quantity.toFixed(2).replace(".", options.decimal);

  return [
    line.employeeId ?? "",
    line.userId ?? "",
    line.employeeName ?? "",
    line.kind,
    line.code ?? "",
    line.paid ? "yes" : "no",
    line.unit,
    quantity,
  ]
    .map((value) => cell(value, options.delimiter))
    .join(options.delimiter);
}

/**
 * The reference `PayrollExportFormat`: one CSV row per line with the employee,
 * kind, leave code, unit and quantity, and a header. Provider formats follow
 * the same shape.
 */
export function csvPayrollFormat(
  options: CsvPayrollFormatOptions = {},
): PayrollExportFormat {
  const resolved: Required<CsvPayrollFormatOptions> = {
    delimiter: options.delimiter ?? ";",
    decimal: options.decimal ?? ".",
    name: options.name ?? "csv",
  };

  return {
    apiVersion: 1,
    name: resolved.name,
    render: (run) => ({
      filename: `payroll-${run.periodFrom.toString()}-${run.periodTo.toString()}.csv`,
      contentType: "text/csv",
      body: `${[COLUMNS.join(resolved.delimiter), ...run.lines.map((line) => row(line, resolved))].join("\r\n")}\r\n`,
    }),
  };
}
