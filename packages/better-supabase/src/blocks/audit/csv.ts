import type { AuditColumns, AuditDetails, AuditRecord } from "./client.ts";

import { toCsv } from "../csv.ts";

/** A CSV export column: a key, or a key and the header to write for it. */
export type AuditCsvColumn =
  | string
  | { readonly key: string; readonly label: string };

/** How `export({ format: "csv" })` writes its rows. */
export interface AuditCsvOptions<Columns extends AuditColumns = AuditColumns> {
  /**
   * The columns, in order: a key of the record (`eventType`),
   * `columns.<name>` for a column `metadataColumns` fills, or
   * `restricted.<field>` (`ip`, `userAgent`, `sessionId`, `metadata`, `old`,
   * `new` or `changes`) for a caller who may reveal the entries. A restricted
   * column reads each page through `reveal_audit_entries`, which records
   * `audit.revealed`, and is empty for entries the caller may not reveal.
   * Defaults to the built-in columns.
   */
  readonly columns?: readonly AuditCsvColumn[];
  /** Lines written before the header row, one cell each, such as a title. */
  readonly preamble?: readonly string[];
  /**
   * The row to write, by column key. It gets the default row, the record and
   * its restricted details (only with a restricted column).
   */
  readonly formatRow?: (
    row: Readonly<Record<string, unknown>>,
    record: AuditRecord<Columns>,
    details: AuditDetails | undefined,
  ) => Readonly<Record<string, unknown>>;
}

const DEFAULT_COLUMNS: readonly string[] = [
  "id",
  "occurredAt",
  "op",
  "eventType",
  "category",
  "outcome",
  "actorId",
  "actorLabel",
  "actorRole",
  "actorKind",
  "tenant",
  "tenantLabel",
  "table",
  "record",
  "targetType",
  "targetLabel",
  "summary",
  "changed",
  "source",
  "requestId",
  "correlationId",
  "impersonatedBy",
  "metadata",
];

const keyOf = (column: AuditCsvColumn): string =>
  typeof column === "string" ? column : column.key;

/** Whether the columns read restricted details. */
export const revealsDetails = (
  columns: readonly AuditCsvColumn[] | undefined,
): boolean =>
  (columns ?? []).some((column) => keyOf(column).startsWith("restricted."));

function defaultRow<Columns extends AuditColumns>(
  record: AuditRecord<Columns>,
  keys: readonly string[],
  details: AuditDetails | undefined,
): Record<string, unknown> {
  const row: Record<string, unknown> = {
    ...record,
    occurredAt: record.occurredAt.toString(),
    changed: record.changed?.join(" "),
  };
  for (const key of keys) {
    const [scope, ...rest] = key.split(".");
    const name = rest.join(".");
    if (scope === "columns" && name !== "") row[key] = record.columns?.[name];
    if (scope === "restricted" && name !== "")
      row[key] = new Map(Object.entries(details ?? {})).get(name);
  }
  return row;
}

/** One cell per line, escaped like the rows. */
const lines = (values: readonly string[]): string =>
  values
    .map((value) => {
      const csv = toCsv([{ value }], { columns: ["value"] });
      return csv.slice(csv.indexOf("\r\n") + 2);
    })
    .join("");

/** A page of CSV, with the preamble and header row on the first. */
export function csvPage<Columns extends AuditColumns>(
  entries: readonly AuditRecord<Columns>[],
  options: AuditCsvOptions<Columns>,
  details: ReadonlyMap<string, AuditDetails> | undefined,
  first: boolean,
): string {
  const columns = options.columns ?? DEFAULT_COLUMNS;
  const keys = columns.map(keyOf);
  const rows = entries.map((record) => {
    const found = details?.get(record.id);
    const row = defaultRow(record, keys, found);
    return options.formatRow ? options.formatRow(row, record, found) : row;
  });
  const csv = toCsv(rows, { columns: keys });
  const body = csv.slice(csv.indexOf("\r\n") + 2);
  if (!first) return body;
  const header = toCsv([], {
    columns: columns.map((column) =>
      typeof column === "string" ? column : column.label,
    ),
  });
  return `${lines(options.preamble ?? [])}${header}${body}`;
}
