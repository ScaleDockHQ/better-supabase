export interface CsvOptions {
  /**
   * The columns in order. Defaults to every key of the rows, in the order
   * they first appear.
   */
  readonly columns?: readonly string[];
  /**
   * Prefixes a text cell that starts with `=`, `+`, `-`, `@`, a tab or a
   * carriage return with `'`, so a spreadsheet shows it instead of running
   * it as a formula (CSV injection). Default true.
   */
  readonly escapeFormulas?: boolean;
}

const FORMULA = /^[=+\-@\t\r]/;

function cell(value: unknown, escapeFormulas: boolean): string {
  if (value === null || value === undefined) return "";
  let text =
    typeof value === "string"
      ? value
      : typeof value === "number" ||
          typeof value === "boolean" ||
          typeof value === "bigint"
        ? String(value)
        : JSON.stringify(value);
  if (escapeFormulas && typeof value === "string" && FORMULA.test(text)) {
    text = `'${text}`;
  }
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

/** The columns of `rows`: every key, in the order it first appears. */
export function csvColumns(
  rows: readonly Readonly<Record<string, unknown>>[],
): string[] {
  const columns = new Set<string>();
  for (const row of rows) for (const key of Object.keys(row)) columns.add(key);
  return [...columns];
}

/**
 * RFC 4180 CSV with a header row and CRLF line ends. Objects and arrays are
 * written as JSON, null and undefined as empty cells.
 */
export function toCsv(
  rows: readonly Readonly<Record<string, unknown>>[],
  options: CsvOptions = {},
): string {
  const columns = options.columns ?? csvColumns(rows);
  const escape = options.escapeFormulas ?? true;
  const lines = [
    columns.map((column) => cell(column, false)).join(","),
    ...rows.map((row) =>
      columns.map((column) => cell(row[column], escape)).join(","),
    ),
  ];
  return `${lines.join("\r\n")}\r\n`;
}
