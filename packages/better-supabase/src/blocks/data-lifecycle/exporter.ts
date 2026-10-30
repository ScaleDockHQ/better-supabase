import type { BlockTransport } from "../../core/block-transport.ts";
import type { AsyncResult, Result } from "../../core/result.ts";
import type { EventSink } from "../../events/index.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { DataExport, LifecycleStorage } from "./data-lifecycle.ts";

import { toCsv } from "../../core/csv.ts";
import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  errorText,
  isRecord,
  optionalText,
  recordOf,
  stringsOf,
} from "../shared.ts";
import { exportOf, stored } from "./data-lifecycle.ts";

export interface DataExporterOptions extends BlockTemporalOptions {
  /**
   * A service-role transport: the export functions are granted to
   * `service_role` only.
   */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to write the files. */
  readonly storage: LifecycleStorage;
  readonly schema?: string;
  /** Rows read per call. Default 1000. */
  readonly pageSize?: number;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
  /**
   * `ndjson` (default) writes one JSON object per line; `csv` writes RFC 4180
   * CSV with a header row, nested values as JSON and formula-looking text
   * prefixed with `'`, for people who open exports in a spreadsheet. A record
   * export's own `format` wins over this.
   */
  readonly format?: "ndjson" | "csv";
  readonly concurrency?: number;
}

/** The payload `job` expects. */
export interface DataExportJob {
  readonly exportId: string;
}

export interface DataExporter {
  /**
   * Writes one NDJSON file per table, then marks the export ready (which emits
   * `data_export.completed`). A failure marks it failed and returns the error.
   */
  run(exportId: string, signal?: AbortSignal): AsyncResult<DataExport>;
  /**
   * A jobs handler: `queue.work('data-exports', exporter.job)`. An export that
   * is no longer pending or failed (cancelled, deleted, running or ready)
   * completes the job; other errors throw so the queue retries.
   */
  readonly job: JobHandler<DataExportJob>;
  /**
   * An outbox sink that runs each `data_export.requested` export. An event for
   * an export that is no longer pending or failed is skipped, so it never holds
   * up the events behind it; other errors throw so the relay retries.
   */
  sink(): EventSink;
}

/** Runs requested exports with a service-role client. */
export function createDataExporter(options: DataExporterOptions): DataExporter {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const pageSize = options.pageSize ?? 1000;
  const concurrency = options.concurrency ?? 4;

  if (!Number.isInteger(concurrency) || concurrency < 1) {
    throw new TypeError(
      "createDataExporter: concurrency must be a whole number above zero",
    );
  }

  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;

  const write = async (
    claimed: DataExport,
    tables: readonly string[],
    signal: AbortSignal | undefined,
  ): Promise<Result<readonly string[]>> => {
    const bucket = options.storage.from(claimed.bucket);
    const csv = (claimed.format ?? options.format) === "csv";

    const exportTable = async (table: string): Promise<Result<string>> => {
      const lines: string[] = [];
      const records: Record<string, unknown>[] = [];
      let after: string | undefined;

      do {
        signal?.throwIfAborted();

        const page = await call(
          "data_export_rows",
          { id: claimed.id, table_name: table, after, page_size: pageSize },
          (value) => recordOf(value, "data_export_rows"),
        );

        if (!page.ok) {
          return page;
        }

        const rows = Array.isArray(page.data["rows"]) ? page.data["rows"] : [];

        for (const row of rows) {
          if (csv) {
            records.push(isRecord(row) ? row : { value: row });
          } else {
            lines.push(JSON.stringify(row));
          }
        }

        after = optionalText(page.data["after"]);
      } while (after !== undefined);

      const path = `${claimed.id}/${table}.${csv ? "csv" : "ndjson"}`;
      const contentType = csv ? "text/csv" : "application/x-ndjson";

      const body = new Blob(
        csv
          ? records.length === 0
            ? []
            : [toCsv(records)]
          : lines.length === 0
            ? []
            : [`${lines.join("\n")}\n`],
        { type: contentType },
      );

      const uploaded = await stored(
        bucket.upload(path, body, { contentType, upsert: true }),
      );

      return uploaded.ok ? ok(path) : uploaded;
    };

    const files: string[] = [];
    let failed: Result<readonly string[]> | undefined;
    let next = 0;
    let stopped = false;

    const worker = async (): Promise<void> => {
      while (!stopped && failed === undefined && next < tables.length) {
        const index = next;
        next += 1;
        let written: Result<string>;

        try {
          written = await exportTable(tables[index]!);
        } catch (cause) {
          stopped = true;
          throw cause;
        }

        if (!written.ok) {
          failed ??= written;

          return;
        }

        files[index] = written.data;
      }
    };

    await Promise.all(
      Array.from({ length: Math.min(concurrency, tables.length) }, worker),
    );

    return failed ?? ok(files);
  };

  const run = (
    exportId: string,
    signal?: AbortSignal,
  ): AsyncResult<DataExport> =>
    call("claim_data_export", { id: exportId }, (value) => value).andThen(
      async (value): Promise<Result<DataExport>> => {
        if (!isRecord(value)) {
          return err(
            dbError("not_found", "No pending export has this id", {
              hint: "DATA_EXPORT_NOT_FOUND",
            }),
          );
        }

        const claimed = exportOf(value);
        let written: Result<readonly string[]>;

        try {
          written = await write(claimed, stringsOf(value["tables"]), signal);
        } catch (cause) {
          written = err(
            dbError(signal?.aborted ? "aborted" : "raised", errorText(cause), {
              hint: "DATA_EXPORT_FAILED",
            }),
          );
        }

        if (!written.ok) {
          await call(
            "fail_data_export",
            { id: claimed.id, error: written.error.message },
            () => undefined,
          );

          return written;
        }

        return call(
          "complete_data_export",
          { id: claimed.id, files: written.data },
          exportOf,
        );
      },
    );

  const settle = async (ran: AsyncResult<DataExport>): Promise<void> => {
    const result = await ran;

    if (result.ok || result.error.hint === "DATA_EXPORT_NOT_FOUND") {
      return;
    }

    await ran.orThrow();
  };

  return {
    run,
    job: async (payload, _job, signal) => {
      await settle(run(payload.exportId, signal));
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;

          if (type !== "data_export.requested" || !isRecord(event.data)) {
            continue;
          }

          const id = optionalText(event.data["exportId"]);

          if (id !== undefined) {
            await settle(run(id));
          }
        }
      },
    }),
  };
}
