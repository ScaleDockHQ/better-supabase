import type { Result } from "better-supabase";

import { ok } from "better-supabase";

/** One page of a block list, with the cursor of the next one. */
export interface BlockPage<Row> {
  readonly items: readonly Row[];
  readonly nextCursor: string | null;
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
