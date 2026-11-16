import type { FacetResult } from "better-supabase/blocks";

import { AsyncResult, ok } from "better-supabase";
import { sortsOf } from "better-supabase/blocks";

import type { EntityPager } from "@/lib/block-entity-page";

const PAGE_SIZE = 25;

/** How a list a block returns whole is searched, filtered and sorted. */
export interface LoadedSpec<Item> {
  /** The text a search matches. */
  readonly search: (item: Item) => string;
  /** The value of each facet, by the facet's filter name. */
  readonly facets?: Readonly<Record<string, (item: Item) => string>>;
  /** Ascending comparators by sort name; `direction: "desc"` reverses one. */
  readonly sorts: Readonly<Record<string, (a: Item, b: Item) => number>>;
}

/**
 * The thin per-page read for a block with no `page` method (a registry, a
 * ranked read, a read-by-key list): it loads the list once per request, then
 * searches, filters, sorts and pages it for `pageEntityRows`, with the offset
 * of the next row as the cursor. Prefer a block's own `page`.
 */
export function loadedPager<Item>(
  load: () => AsyncResult<readonly Item[]>,
  spec: LoadedSpec<Item>,
): EntityPager<Item> {
  let loaded: AsyncResult<readonly Item[]> | undefined;

  const items = (): AsyncResult<readonly Item[]> => (loaded ??= load());

  const matches = (
    item: Item,
    q: string | undefined,
    filters: Readonly<Record<string, readonly string[]>>,
    skip?: string,
  ): boolean => {
    const needle = q?.trim().toLowerCase() ?? "";

    if (needle !== "" && !spec.search(item).toLowerCase().includes(needle)) {
      return false;
    }

    return Object.entries(filters).every(([name, values]) => {
      const read = spec.facets?.[name];

      return (
        name === skip ||
        read === undefined ||
        values.length === 0 ||
        values.includes(read(item))
      );
    });
  };

  return {
    page: (options) =>
      AsyncResult.from(async () => {
        const all = await items();

        if (!all.ok) {
          return all;
        }

        const selected = all.data.filter((item) =>
          matches(item, options.q, options.filters ?? {}),
        );

        const [term] = sortsOf(options.sort);

        const compare = term === undefined ? undefined : spec.sorts[term.by];

        const sorted =
          compare === undefined
            ? selected
            : selected.toSorted((a, b) =>
                term?.direction === "desc" ? compare(b, a) : compare(a, b),
              );

        const limit = options.limit ?? PAGE_SIZE;
        const start = Number(options.after?.[0] ?? 0);
        const end = start + limit;

        return ok({
          items: sorted.slice(start, end),
          hasMore: end < sorted.length,
          nextCursor: end < sorted.length ? [String(end)] : null,
        });
      }),
    facets: (options) =>
      AsyncResult.from(async () => {
        const all = await items();

        if (!all.ok) {
          return all;
        }

        const results = Object.entries(spec.facets ?? {}).map(
          ([name, read]): FacetResult => {
            const counts = new Map<string, number>();

            for (const item of all.data) {
              if (matches(item, options.q, options.filters ?? {}, name)) {
                const value = read(item);
                counts.set(value, (counts.get(value) ?? 0) + 1);
              }
            }

            return {
              facet: name,
              values: [...counts].map(([value, count]) => ({
                value,
                count: { value: count, exact: true },
              })),
            };
          },
        );

        return ok(results);
      }),
  };
}
