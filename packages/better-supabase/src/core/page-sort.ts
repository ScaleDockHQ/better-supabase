/** One term of a sort: a column from the entity's `sorts` and its direction. */
export interface PageSort {
  readonly by: string;
  readonly direction?: "asc" | "desc";
}

/** What a page did with the sorts it was asked for (ADR 0896). */
export interface SortReport {
  readonly applied: readonly PageSort[];
  readonly ignored: readonly PageSort[];
}

/** The most terms a list of sorts may hold. */
export const MAX_PAGE_SORTS = 3;

/** The terms of `sort` as a list: none, the one sort, or the list as given. */
export function sortsOf(
  sort: PageSort | readonly PageSort[] | undefined,
): readonly PageSort[] {
  if (sort === undefined) {
    return [];
  }

  return "by" in sort ? [sort] : sort;
}
