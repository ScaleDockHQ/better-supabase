import type { Selection } from "../ir/types.ts";
import type { SchemaMeta } from "../schema/types.ts";
import type { Result } from "./result.ts";

import { builderFor } from "../ir/build.ts";
import { decodeRows } from "../ir/codec.ts";
import { DbException, dbError } from "./errors.ts";
import { isRecord } from "./guards.ts";
import { err, ok } from "./result.ts";

/**
 * `db.$decode(table)`: reads rows that did not come from the repository, such
 * as `$client` or `queryRaw` results with database names, into the table's
 * shape.
 */
export interface DbDecoder<T> {
  /** One row, or a `validation` error when `value` is not an object. */
  row(value: unknown): Result<T>;
  /** Every row, or the first error. */
  rows(value: unknown): Result<T[]>;
}

/** The first column key a row carries: the app name, else the database name. */
function aliased(
  selection: Selection,
  row: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  for (const { alias, column } of selection.columns) {
    if (alias in row) {
      out[alias] = row[alias];
    } else if (column in row) {
      out[alias] = row[column];
    }
  }

  return out;
}

/**
 * A decoder for `table` over its full selection: database column names become
 * the configured names, and the column codecs run (`int8` to `bigint`,
 * timestamps to `Temporal`).
 */
export function dbDecoder<T>(meta: SchemaMeta, table: string): DbDecoder<T> {
  const tableMeta = meta.tables[table];

  if (!tableMeta) {
    throw new TypeError(`better-supabase: $decode: unknown table "${table}"`);
  }

  const selection = builderFor(meta).selection(tableMeta, undefined, undefined);

  const invalid = (message: string) =>
    err(dbError("validation", message, { issues: [{ message }], table }));

  const decodeOne = (value: unknown): Result<T> => {
    if (!isRecord(value)) {
      return invalid(`${table}: expected a row object`);
    }

    try {
      const [row] = decodeRows(selection, [aliased(selection, value)]);

      // SAFETY: the decoded row has the table's selection, which `T` types.
      return ok(row as T);
    } catch (cause) {
      if (cause instanceof DbException) {
        return err(cause.error);
      }

      throw cause;
    }
  };

  return {
    row: decodeOne,
    rows: (value) => {
      if (!Array.isArray(value)) {
        return invalid(`${table}: expected a list of rows`);
      }

      const items: readonly unknown[] = value;
      const out: T[] = [];

      for (const item of items) {
        const decoded = decodeOne(item);

        if (!decoded.ok) {
          return decoded;
        }

        out.push(decoded.data);
      }

      return ok(out);
    },
  };
}
