import type { Result } from "better-supabase";
import type { PageOptions } from "better-supabase/blocks";

import { ok } from "better-supabase";

import type { Mutable } from "@/lib/block-status-list";

/** One page of a block list, with the cursor of the next one. */
export interface BlockPage<Row> {
  readonly items: readonly Row[];
  readonly nextCursor: string | null;
}

/**
 * The URL form of a keyset cursor (`nextCursor` of a block page), so the list's
 * `after` parameter carries it unchanged.
 */
export function encodeCursor(cursor: readonly string[] | null): string | null {
  return cursor === null ? null : JSON.stringify(cursor);
}

/** The keyset cursor an `after` parameter holds; none for a malformed one. */
function decodeCursor(
  after: string | undefined,
): readonly string[] | undefined {
  if (after === undefined) {
    return undefined;
  }

  try {
    const parsed: unknown = JSON.parse(after);

    return Array.isArray(parsed) &&
      parsed.every((part): part is string => typeof part === "string")
      ? parsed
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The block page options of a list query: its search text, the keyset cursor
 * `after` holds, `limit` rows, and the selected values of each facet as list
 * filters (a facet with no value leaves its filter off).
 */
export function pageOptionsOf(
  query: {
    readonly q?: string | undefined;
    readonly after?: string | undefined;
  },
  limit: number,
  filters: Readonly<Record<string, readonly string[]>> = {},
): PageOptions {
  const options: Mutable<PageOptions> = { limit };

  if (query.q !== undefined) {
    options.q = query.q;
  }

  const after = decodeCursor(query.after);

  if (after !== undefined) {
    options.after = after;
  }

  const set = Object.fromEntries(
    Object.entries(filters).filter(([, values]) => values.length > 0),
  );

  if (Object.keys(set).length > 0) {
    options.filters = set;
  }

  return options;
}

interface Dated {
  readonly createdAt: { readonly epochNanoseconds: bigint } & {
    toString(): string;
  };
}

/**
 * A page of a block list that takes one status and pages back from a
 * `createdAt`. With several statuses it asks the block once per status, in
 * parallel, and merges the answers newest first, so a multi-select facet still
 * costs one wave. `size + 1` rows per status tell whether another page follows;
 * the cursor is the `createdAt` of the last row of this page.
 */
export async function pageOverStatuses<Row extends Dated, Out>({
  statuses,
  size,
  fetchPage,
  map,
}: {
  /** The selected facet values; none means every status. */
  statuses: readonly string[] | undefined;
  size: number;
  /** One block call. `status` is `undefined` when no facet narrows the list. */
  fetchPage: (
    status: string | undefined,
    take: number,
  ) => PromiseLike<Result<readonly Row[]>>;
  /** The serializable row the page and the list route send. */
  map: (row: Row) => Out;
}): Promise<Result<BlockPage<Out>>> {
  const wanted = statuses && statuses.length > 0 ? statuses : [undefined];

  const results = await Promise.all(
    wanted.map((status) => fetchPage(status, size + 1)),
  );

  const rows: Row[] = [];

  for (const result of results) {
    if (!result.ok) {
      return result;
    }

    rows.push(...result.data);
  }

  rows.sort((a, b) => {
    const left = a.createdAt.epochNanoseconds;
    const right = b.createdAt.epochNanoseconds;

    return left === right ? 0 : left < right ? 1 : -1;
  });

  const taken = rows.slice(0, size);
  const last = taken.at(-1);

  return ok({
    items: taken.map((row) => map(row)),
    nextCursor:
      rows.length > size && last !== undefined
        ? last.createdAt.toString()
        : null,
  });
}
