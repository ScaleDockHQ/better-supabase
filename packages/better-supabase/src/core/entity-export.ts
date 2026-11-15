import type { ListPage, PageOptions } from "./block-helpers.ts";
import type { CsvOptions } from "./csv.ts";
import type { AsyncResult } from "./result.ts";

import { csvColumns, csvHeader, csvLines } from "./csv.ts";
import { DbException } from "./db-exception.ts";
import { dbError } from "./errors.ts";

/**
 * How an export writes its rows (ADR 1029). The default is CSV; a format that
 * is line oriented, like NDJSON or TSV, supplies its own pieces.
 */
export interface ExportFormat {
  /** The `Content-Type` of `exportResponse`. */
  readonly contentType: string;
  /** Text written once before the first row. */
  readonly header?: (columns: readonly string[]) => string;
  /** The text of one page of rows, in `columns`. */
  readonly rows: (
    items: readonly Readonly<Record<string, unknown>>[],
    columns: readonly string[],
    escapeFormulas: boolean,
  ) => string;
}

/** RFC 4180 CSV with CRLF line ends: the format an export uses by default. */
export const csvFormat: ExportFormat = {
  contentType: "text/csv; charset=utf-8",
  header: csvHeader,
  rows: csvLines,
};

/** One JSON object per line, with the `columns` as the only keys. */
export const ndjsonFormat: ExportFormat = {
  contentType: "application/x-ndjson; charset=utf-8",
  rows: (items, columns) =>
    items
      .map(
        (item) =>
          `${JSON.stringify(Object.fromEntries(columns.map((column) => [column, item[column] ?? null])))}\n`,
      )
      .join(""),
};

/** The most rows an export writes when the entity declares no cap. */
export const EXPORT_ROW_CAP = 100_000;

/**
 * What `export(options)` takes (ADR 0855): the filters, search and sort of
 * `page`, without the cursor, and the CSV columns.
 */
export interface ExportOptions
  extends
    Pick<PageOptions, "q" | "filters" | "sort">,
    Pick<CsvOptions, "columns" | "escapeFormulas"> {
  /** How the rows are written. Default {@link csvFormat}. */
  readonly format?: ExportFormat;
  /** Rows per `page` call. Default 200. */
  readonly pageSize?: number;
  /**
   * The most rows written; an export that reaches it ends with a truncation
   * error. Default {@link EXPORT_ROW_CAP}.
   */
  readonly maxRows?: number;
}

/** The `page` an export reads. */
export type ExportPage = (
  options: PageOptions,
) => AsyncResult<ListPage<unknown>>;

/** The `export` method an entity declares (ADR 0855). */
export type EntityExport = (options?: ExportOptions) => ReadableStream<string>;

/**
 * Streams the rows `page` returns for the same filters as CSV, one page at a
 * time, so memory stays at one page. The header comes from `columns` or from
 * the first page. The stream errors with a `DbException` when a page fails or
 * the row cap is reached; text already written stays valid CSV.
 */
export function exportCsv(
  page: ExportPage,
  options: ExportOptions = {},
): ReadableStream<string> {
  const {
    pageSize = 200,
    maxRows = EXPORT_ROW_CAP,
    format = csvFormat,
  } = options;

  let after: readonly string[] | undefined;
  let columns = options.columns;
  let written = 0;
  let finished = false;

  return new ReadableStream<string>(
    {
      async pull(controller) {
        if (finished) {
          controller.close();

          return;
        }

        const result = await page({
          ...(options.q === undefined ? {} : { q: options.q }),
          ...(options.filters === undefined
            ? {}
            : { filters: options.filters }),
          ...(options.sort === undefined ? {} : { sort: options.sort }),
          ...(after === undefined ? {} : { after }),
          limit: Math.min(pageSize, maxRows - written + 1),
        });

        if (!result.ok) {
          controller.error(new DbException(result.error));

          return;
        }

        const items = result.data.items
          .slice(0, maxRows - written)
          .map((item) =>
            typeof item === "object" && item !== null
              ? Object.fromEntries(Object.entries(item))
              : {},
          );

        const truncated =
          items.length < result.data.items.length ||
          (written + items.length >= maxRows && result.data.hasMore);

        let chunk = "";

        columns ??= csvColumns(items);

        if (written === 0) {
          chunk += format.header?.(columns) ?? "";
        }

        chunk += format.rows(items, columns, options.escapeFormulas ?? true);
        written += items.length;
        after = result.data.nextCursor ?? undefined;

        if (chunk !== "") {
          controller.enqueue(chunk);
        }

        if (truncated) {
          controller.error(
            new DbException(
              dbError(
                "invalid_input",
                `An export holds at most ${String(maxRows)} rows; narrow the filters`,
                { hint: "EXPORT_ROW_CAP" },
              ),
            ),
          );

          return;
        }

        if (!result.data.hasMore || after === undefined) {
          finished = true;
          controller.close();
        }
      },
    },
    { highWaterMark: 0 },
  );
}

/**
 * The download route's response: `exportCsv` as `text/csv` (or the content type
 * of `options.format`) with the file name in `Content-Disposition`. A route is
 * `() => exportResponse(entity.page, ...)`.
 */
export function exportResponse(
  page: ExportPage,
  filename: string,
  options: ExportOptions = {},
): Response {
  const safe = filename.replaceAll(/[^\w.-]/g, "_");

  return new Response(
    exportCsv(page, options).pipeThrough(new TextEncoderStream()),
    {
      headers: {
        "Content-Type": (options.format ?? csvFormat).contentType,
        "Content-Disposition": `attachment; filename="${safe}"`,
        "Cache-Control": "no-store",
      },
    },
  );
}
