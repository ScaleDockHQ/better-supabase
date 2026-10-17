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
  if (value === null || value === undefined) {
    return "";
  }
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
  for (const row of rows) {
    for (const key of Object.keys(row)) {
      columns.add(key);
    }
  }
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

/**
 * Parses RFC 4180 CSV into rows of fields. A quoted field may contain
 * commas, CRLF and `""` for one quote. A trailing newline does not add a row.
 */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  let i = 0;
  const pushField = (): void => {
    row.push(field);
    field = "";
  };
  const pushRow = (): void => {
    pushField();
    rows.push(row);
    row = [];
  };
  while (i < text.length) {
    const char = text[i] ?? "";
    if (quoted) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        quoted = false;
        i += 1;
        continue;
      }
      field += char;
      i += 1;
      continue;
    }
    if (char === '"') {
      quoted = true;
      i += 1;
      continue;
    }
    if (char === ",") {
      pushField();
      i += 1;
      continue;
    }
    if (char === "\r") {
      if (text[i + 1] === "\n") {
        i += 1;
      }
      pushRow();
      i += 1;
      continue;
    }
    if (char === "\n") {
      pushRow();
      i += 1;
      continue;
    }
    field += char;
    i += 1;
  }
  if (quoted) {
    throw new TypeError("a quoted CSV field was not closed");
  }
  if (field !== "" || row.length > 0) {
    pushRow();
  }
  return rows;
}
