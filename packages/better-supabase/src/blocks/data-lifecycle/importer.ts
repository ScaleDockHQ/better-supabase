import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { ImportItem } from "../imports/define-import.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  blockCall,
  errorText,
  isRecord,
  recordOf,
  stringsOf,
} from "../shared.ts";

/** The import source every restore writes under (ADR 0141). */
export const RESTORE_SOURCE = "restore";

/** The import entity of a restored row; `data_lifecycle` contributes it. */
const RESTORE_ENTITY = "data_lifecycle_row";

/**
 * One file of an export. A `Blob` or `File` fits; so does `{ name, text: async
 * () => ... }`. The name is `<schema.table>.ndjson`, with an optional folder
 * (`<export id>/public.orders.ndjson`).
 */
export interface RestoreFile {
  readonly name: string;
  text(): Promise<string>;
}

export interface DataImporterOptions {
  /**
   * A service-role transport: `restore_data_row`, `data_restore_tables` and the
   * import functions are granted to `service_role` only.
   */
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Rows written per call. Default 500. */
  readonly batchSize?: number;
}

export interface RestoreOptions {
  /** The organization to restore into. Every row gets its tenant column. */
  readonly organizationId: string;
  readonly files: readonly RestoreFile[];
  /**
   * Validate and run every write inside a rolled-back run, then report the
   * counts. Unknown tables and columns are reported instead of refused.
   */
  readonly dryRun?: boolean;
  /** Restore only these tables (`schema.table`); other files are skipped. */
  readonly tables?: readonly string[];
  readonly signal?: AbortSignal;
}

export interface RestoreRowError {
  /** The row's key: its primary key values, or a content hash. */
  readonly key: string | null;
  readonly code: string;
  readonly message: string;
}

export interface RestoreTableReport {
  readonly table: string;
  /** Rows in the file. */
  readonly rows: number;
  readonly inserted: number;
  readonly updated: number;
  /** Rows whose content the source map already holds: nothing was written. */
  readonly unchanged: number;
  /** Rows a user changed after the last restore: left as they are. */
  readonly conflicted: number;
  /** Columns of the file the table does not take. */
  readonly unknownColumns: readonly string[];
  readonly errors: readonly RestoreRowError[];
}

export interface RestoreReport {
  readonly dryRun: boolean;
  readonly runId: string;
  /** Tables of the files this installation does not export. */
  readonly unknownTables: readonly string[];
  readonly tables: readonly RestoreTableReport[];
  readonly written: number;
}

export interface DataImporter {
  /**
   * Reads the NDJSON-per-table export format, checks table and column names
   * against `data_lifecycle_tables()`, and writes each row through the import
   * record map with `source = 'restore'` in import mode. A second restore of
   * the same files writes nothing. CSV files fail with `DATA_RESTORE_CSV`: the
   * CSV export is lossy.
   */
  restore(options: RestoreOptions): AsyncResult<RestoreReport>;
}

interface RestorableTable {
  readonly name: string;
  readonly columns: ReadonlySet<string>;
  readonly keyColumns: readonly string[];
  readonly references: readonly string[];
}

interface ParsedFile {
  readonly table: string;
  readonly rows: readonly {
    readonly row: Record<string, unknown>;
    readonly line: string;
  }[];
}

const FILE = /^(?:.*\/)?([^/]+?)\.(ndjson|jsonl|csv)$/;

const hex = (bytes: ArrayBuffer): string =>
  [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

const sha256 = async (text: string): Promise<string> =>
  hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));

function tablesOf(value: unknown): Map<string, RestorableTable> {
  const tables = new Map<string, RestorableTable>();

  for (const entry of Array.isArray(value) ? value : []) {
    const row = recordOf(entry, "data_restore_tables");
    const name = String(row["name"]);

    tables.set(name, {
      name,
      columns: new Set(stringsOf(row["columns"])),
      keyColumns: stringsOf(row["keyColumns"]),
      references: stringsOf(row["references"]),
    });
  }

  return tables;
}

/** Parents before children; a cycle keeps its name order. */
function orderOf(
  names: readonly string[],
  tables: ReadonlyMap<string, RestorableTable>,
): readonly string[] {
  const wanted = new Set(names);
  const done = new Set<string>();
  const ordered: string[] = [];

  const visit = (name: string, path: ReadonlySet<string>): void => {
    if (done.has(name) || path.has(name)) {
      return;
    }

    const next = new Set(path).add(name);

    for (const parent of tables.get(name)?.references ?? []) {
      if (wanted.has(parent)) {
        visit(parent, next);
      }
    }

    done.add(name);
    ordered.push(name);
  };

  for (const name of names.toSorted()) {
    visit(name, new Set());
  }

  return ordered;
}

async function parse(
  file: RestoreFile,
  table: string,
): Promise<Result<ParsedFile>> {
  const rows: { row: Record<string, unknown>; line: string }[] = [];
  const lines = (await file.text()).split("\n");

  for (const [index, raw] of lines.entries()) {
    const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;

    if (line.trim() === "") {
      continue;
    }

    let value: unknown;

    try {
      value = JSON.parse(line);
    } catch {
      value = undefined;
    }

    if (!isRecord(value)) {
      return err(
        dbError(
          "validation",
          `${file.name} line ${index + 1} is not a JSON object`,
          {
            issues: [
              { message: "not a JSON object", path: [file.name, index + 1] },
            ],
            hint: "DATA_RESTORE_FORMAT",
          },
        ),
      );
    }

    rows.push({ row: value, line });
  }

  return ok({ table, rows });
}

async function keyOf(
  table: RestorableTable,
  row: Record<string, unknown>,
  line: string,
): Promise<string> {
  const values = table.keyColumns.map((column) => row[column]);

  return values.length > 0 &&
    values.every((value) => value !== null && value !== undefined)
    ? `${table.name}:${JSON.stringify(values)}`
    : `${table.name}#${await sha256(line)}`;
}

/**
 * Restores an organization export through the import record map. The importer
 * uses a service-role transport; the `imports` and `data-lifecycle` blocks must
 * both be installed.
 */
export function createDataImporter(options: DataImporterOptions): DataImporter {
  const batchSize = options.batchSize ?? 500;

  if (!Number.isInteger(batchSize) || batchSize < 1) {
    throw new TypeError(
      "createDataImporter: batchSize must be a whole number above zero",
    );
  }

  const call = blockCall(options.transport, options.schema, options.mappers);

  const textOfId = (row: Record<string, unknown>): string => {
    const id = row["id"];

    if (typeof id !== "string") {
      throw new TypeError("start_import_run returned no run id");
    }

    return id;
  };

  const countOf = (value: unknown): number =>
    typeof value === "number" && Number.isFinite(value) ? value : 0;

  const imports = {
    start: (organizationId: string, dryRun: boolean) =>
      call(
        "start_import_run",
        { tenant: organizationId, source: RESTORE_SOURCE, options: { dryRun } },
        (value) => textOfId(recordOf(value, "start_import_run")),
      ),
    markRunning: (id: string) =>
      call("mark_import_running", { id }, (value) => value === true),
    upsertBatch: (run: string, items: readonly ImportItem[]) =>
      call(
        "import_upsert_batch",
        {
          run,
          entity: RESTORE_ENTITY,
          items: items.map((item) => ({
            key: item.key,
            scope: "",
            data: item.data,
            refs: {},
          })),
        },
        (value) => {
          const row = recordOf(value, "import_upsert_batch");
          const failed = Array.isArray(row["errors"]) ? row["errors"] : [];

          return {
            inserted: countOf(row["inserted"]),
            updated: countOf(row["updated"]),
            unchanged: countOf(row["unchanged"]),
            conflicted: countOf(row["conflicted"]),
            errors: failed
              .filter(isRecord)
              .map((error): RestoreRowError => ({
                key: typeof error["key"] === "string" ? error["key"] : null,
                code: String(error["code"] ?? ""),
                message: String(error["message"] ?? ""),
              })),
          };
        },
      ),
    finish: (run: string) => call("finish_import_run", { run }, () => true),
    cancel: (id: string) =>
      call("cancel_import_run", { id }, (value) => value === true),
  };

  const restore = async (
    restoreOptions: RestoreOptions,
  ): Promise<Result<RestoreReport>> => {
    const dryRun = restoreOptions.dryRun === true;

    const only =
      restoreOptions.tables === undefined
        ? undefined
        : new Set(restoreOptions.tables);

    const named: { file: RestoreFile; table: string }[] = [];

    for (const file of restoreOptions.files) {
      const match = FILE.exec(file.name);

      if (match === null) {
        return err(
          dbError("invalid_request", `${file.name} is not an export file`, {
            hint: "DATA_RESTORE_FORMAT",
          }),
        );
      }

      if (match[2] === "csv") {
        return err(
          dbError(
            "unsupported",
            `${file.name} is CSV, which is lossy: nulls and empty text look the same, a leading ' guards formulas, and JSON values have no type. Export as ndjson to restore.`,
            { hint: "DATA_RESTORE_CSV" },
          ),
        );
      }

      const table = match[1] ?? "";

      if (only === undefined || only.has(table)) {
        named.push({ file, table });
      }
    }

    const seen = new Set<string>();

    for (const { table } of named) {
      if (seen.has(table)) {
        return err(
          dbError("invalid_request", `Two files hold the table ${table}`, {
            hint: "DATA_RESTORE_FORMAT",
          }),
        );
      }

      seen.add(table);
    }

    const known = await call("data_restore_tables", {}, tablesOf);

    if (!known.ok) {
      return known;
    }

    const tables = known.data;

    const unknownTables = named
      .map(({ table }) => table)
      .filter((table) => !tables.has(table))
      .toSorted();

    const parsed = new Map<string, ParsedFile>();

    for (const { file, table } of named) {
      if (!tables.has(table)) {
        continue;
      }

      const result = await parse(file, table);

      if (!result.ok) {
        return result;
      }

      parsed.set(table, result.data);
    }

    const unknownColumns = new Map<string, readonly string[]>();

    for (const [table, file] of parsed) {
      const columns = tables.get(table)?.columns ?? new Set<string>();

      const extra = new Set(
        file.rows.flatMap(({ row }) =>
          Object.keys(row).filter((column) => !columns.has(column)),
        ),
      );

      unknownColumns.set(table, [...extra].toSorted());
    }

    const problems = [
      ...unknownTables.map((table) => ({
        message: `No exported table is named ${table}`,
        path: [table],
      })),
      ...[...unknownColumns].flatMap(([table, columns]) =>
        columns.map((column) => ({
          message: `The table ${table} has no restorable column ${column}`,
          path: [table, column],
        })),
      ),
    ];

    if (problems.length > 0 && !dryRun) {
      return err(
        dbError(
          "validation",
          "The files hold tables or columns that cannot be restored",
          { issues: problems, hint: "DATA_RESTORE_UNKNOWN" },
        ),
      );
    }

    const run = await imports.start(restoreOptions.organizationId, dryRun);

    if (!run.ok) {
      return run;
    }

    const runId = run.data;
    const reports: RestoreTableReport[] = [];

    const write = async (): Promise<Result<RestoreReport>> => {
      const running = await imports.markRunning(runId);

      if (!running.ok) {
        return running;
      }

      for (const name of orderOf([...parsed.keys()], tables)) {
        const table = tables.get(name);
        const file = parsed.get(name);

        if (table === undefined || file === undefined) {
          continue;
        }

        let inserted = 0;
        let updated = 0;
        let unchanged = 0;
        let conflicted = 0;
        const errors: RestoreRowError[] = [];

        for (let start = 0; start < file.rows.length; start += batchSize) {
          restoreOptions.signal?.throwIfAborted();

          const items: ImportItem[] = await Promise.all(
            file.rows
              .slice(start, start + batchSize)
              .map(async ({ row, line }): Promise<ImportItem> => ({
                key: await keyOf(table, row, line),
                data: { table: name, row },
              })),
          );

          const batch = await imports.upsertBatch(runId, items);

          if (!batch.ok) {
            return batch;
          }

          inserted += batch.data.inserted;
          updated += batch.data.updated;
          unchanged += batch.data.unchanged;
          conflicted += batch.data.conflicted;
          errors.push(...batch.data.errors);
        }

        reports.push({
          table: name,
          rows: file.rows.length,
          inserted,
          updated,
          unchanged,
          conflicted,
          unknownColumns: unknownColumns.get(name) ?? [],
          errors,
        });
      }

      const finished = await imports.finish(runId);

      if (!finished.ok) {
        return finished;
      }

      return ok({
        dryRun,
        runId,
        unknownTables,
        tables: reports,
        written: reports.reduce(
          (sum, report) => sum + report.inserted + report.updated,
          0,
        ),
      });
    };

    let result: Result<RestoreReport>;

    try {
      result = await write();
    } catch (cause) {
      result = err(
        dbError(
          restoreOptions.signal?.aborted ? "aborted" : "raised",
          errorText(cause),
          { hint: "DATA_RESTORE_FAILED" },
        ),
      );
    }

    if (!result.ok) {
      await imports.cancel(runId);
    }

    return result;
  };

  return {
    restore: (restoreOptions) =>
      AsyncResult.from(() => restore(restoreOptions)),
  };
}
