import type { Args, Row } from "./runner.ts";

/** The page size and row offset of a list call, or the reason its arguments are invalid. */
export function pageWindow(
  args: Args,
): { size: number; offset: number } | { invalid: string } {
  if (args["offset"] !== undefined || args["limit"] !== undefined) {
    if (args["page"] !== undefined || args["size"] !== undefined) {
      return { invalid: 'Pass "offset" and "limit" or "page" and "size"' };
    }
    const limit = Number(args["limit"]);
    if (!Number.isInteger(limit) || limit < 1) {
      return { invalid: '"limit" must be a positive integer' };
    }
    const offset = Number(args["offset"]);
    if (!Number.isInteger(offset) || offset < 0) {
      return { invalid: '"offset" must be a non-negative integer' };
    }
    return { size: limit, offset };
  }
  const size = Number(args["size"]);
  if (!Number.isInteger(size) || size < 1) {
    return { invalid: '"size" must be a positive integer' };
  }
  const number = args["page"] === undefined ? 1 : Number(args["page"]);
  if (!Number.isInteger(number) || number < 1) {
    return { invalid: '"page" must be a positive integer' };
  }
  return { size, offset: (number - 1) * size };
}

/** The `{ items, page }` answer of an offset page from the rows read with one extra row. */
export function offsetEnvelope(
  rows: readonly Row[],
  total: number | null,
  size: number,
  offset: number,
): {
  readonly items: readonly Row[];
  readonly page: {
    readonly number: number;
    readonly size: number;
    readonly total: number | null;
    readonly pages: number | null;
    readonly hasMore: boolean;
  };
} {
  return {
    items: rows.slice(0, size),
    page: {
      number: Math.floor(offset / size) + 1,
      size,
      total,
      pages: total === null ? null : Math.max(1, Math.ceil(total / size)),
      hasMore: rows.length > size,
    },
  };
}

/** A copy of the row without the given keys. */
export function strip(row: Row, keys: readonly string[]): Row {
  const copy: Row = {};
  for (const key in row) {
    if (!keys.includes(key) && Object.hasOwn(row, key)) {
      copy[key] = row[key];
    }
  }
  return copy;
}
