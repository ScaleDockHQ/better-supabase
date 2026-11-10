import type { CursorPage } from "../../core/repository-types.ts";
import type { Result } from "../../core/result.ts";

import { AsyncResult, err, ok } from "../../core/result.ts";

/** A page the export reads: what a cursor list returns. */
export interface ExportPage<Row> {
  readonly items: readonly Row[];
  readonly nextCursor: string | null;
  readonly hasMore: boolean;
}

/** One CSV column: its header and how to read the cell from a row. */
export interface ExportColumn<Row> {
  readonly header: string;
  readonly value: (row: Row) => unknown;
}

export interface ListExportOptions<Row> {
  /**
   * Reads one page after `after` (undefined for the first), of at most `size`
   * rows, for example `(after, size) => list.run(db, { ...query, after, size
   * })`.
   */
  readonly page: (
    after: string | undefined,
    size: number,
  ) => PromiseLike<Result<ExportPage<Row>>>;
  readonly columns: readonly ExportColumn<Row>[];
  /** The download's file name. Default `export.csv`. */
  readonly filename?: string;
  /** Rows per page, 1 to 1,000. Default 500. */
  readonly pageSize?: number;
  /** The most rows the file holds; the file ends there. Default 100,000. */
  readonly maxRows?: number;
  /** Start the file with a byte order mark, for Excel. Default false. */
  readonly bom?: boolean;
}

const DEFAULT_PAGE_SIZE = 500;
const MAX_PAGE_SIZE = 1000;
const DEFAULT_MAX_ROWS = 100_000;
const FORMULA_START = /^[=+\-@\t\r]/u;

/** One CSV cell: quoted when it needs it, and defused when a sheet would run it. */
export function csvCell(value: unknown): string {
  let text: string;

  if (value === null || value === undefined) {
    return "";
  }

  if (typeof value === "string") {
    text = value;
  } else if (value instanceof Date) {
    text = value.toISOString();
  } else if (typeof value === "object") {
    text =
      Object.getPrototypeOf(value) === Object.prototype || Array.isArray(value)
        ? JSON.stringify(value)
        : String(value);
  } else {
    text = String(value);
  }

  // A sheet runs a cell that starts with one of these as a formula.
  if (typeof value === "string" && FORMULA_START.test(text)) {
    text = `'${text}`;
  }

  return /[",\r\n]/u.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function csvLine(cells: readonly string[]): string {
  return `${cells.join(",")}\r\n`;
}

const safeName = (name: string): string =>
  name.replaceAll(/[^\w.-]+/gu, "_") || "export.csv";

/**
 * A CSV download of a cursor list, read page by page so a large list is never
 * held in memory (ADR 0662). The first page is read before the response starts,
 * so a failed read is a normal error response, not a broken file.
 */
export async function exportListCsv<Row>(
  options: ListExportOptions<Row>,
): Promise<Response> {
  const size = Math.min(
    Math.max(Math.trunc(options.pageSize ?? DEFAULT_PAGE_SIZE), 1),
    MAX_PAGE_SIZE,
  );

  const maxRows = Math.max(Math.trunc(options.maxRows ?? DEFAULT_MAX_ROWS), 0);

  const first = await options.page(undefined, size);

  if (!first.ok) {
    return Response.json(
      { error: first.error },
      { status: first.error.status },
    );
  }

  const encoder = new TextEncoder();
  let page = first.data;
  let written = 0;

  const rowsOf = (current: ExportPage<Row>): string => {
    const take = current.items.slice(0, Math.max(maxRows - written, 0));
    written += take.length;

    return take
      .map((row) =>
        csvLine(options.columns.map((column) => csvCell(column.value(row)))),
      )
      .join("");
  };

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const head = csvLine(
        options.columns.map((column) => csvCell(column.header)),
      );

      controller.enqueue(
        encoder.encode(
          `${options.bom === true ? "\uFEFF" : ""}${head}${rowsOf(page)}`,
        ),
      );

      if (!page.hasMore || page.nextCursor === null || written >= maxRows) {
        controller.close();
      }
    },
    async pull(controller) {
      if (!page.hasMore || page.nextCursor === null || written >= maxRows) {
        return;
      }

      const next = await options.page(page.nextCursor, size);

      if (!next.ok) {
        controller.error(new Error(next.error.message));

        return;
      }

      page = next.data;
      controller.enqueue(encoder.encode(rowsOf(page)));

      if (!page.hasMore || page.nextCursor === null || written >= maxRows) {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="${safeName(options.filename ?? "export.csv")}"`,
      "cache-control": "no-store",
    },
  });
}

/** A page of ids in display order, from a search or an RPC. */
export interface IdPage {
  readonly ids: readonly string[];
  readonly nextCursor: string | null;
  readonly hasMore: boolean;
}

export interface PageFromIdsOptions<Row> {
  /** The ids of one page, in display order. */
  readonly ids: PromiseLike<Result<IdPage>>;
  /**
   * Loads the rows of those ids, for example the `rpc` tag's
   * `get_<table>_by_ids`.
   */
  readonly rows: (
    ids: readonly string[],
  ) => PromiseLike<Result<readonly Row[]>>;
  readonly idOf: (row: Row) => string;
}

/**
 * A cursor page whose ids come from one source and whose rows come from an id
 * function (ADR 0662). Rows come back in the order of the ids; an id whose row
 * is missing or hidden by row security is left out, so a page can hold fewer
 * rows than ids.
 */
export function pageFromIds<Row>(
  options: PageFromIdsOptions<Row>,
): AsyncResult<CursorPage<Row>> {
  return AsyncResult.from(async () => {
    const found = await options.ids;

    if (!found.ok) {
      return err(found.error);
    }

    const { ids, nextCursor, hasMore } = found.data;

    if (ids.length === 0) {
      return ok({ items: [], nextCursor, hasMore });
    }

    const loaded = await options.rows(ids);

    if (!loaded.ok) {
      return err(loaded.error);
    }

    const byId = new Map(loaded.data.map((row) => [options.idOf(row), row]));

    return ok({
      items: ids.flatMap((id) => {
        const row = byId.get(id);

        return row === undefined ? [] : [row];
      }),
      nextCursor,
      hasMore,
    });
  });
}
