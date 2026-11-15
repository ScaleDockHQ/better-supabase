import type { Count, FacetResult, ListPage } from "../../core/block-helpers.ts";
import type { PageSort } from "../../core/page-sort.ts";
import type { Result } from "../../core/result.ts";
import type { Check, ConformanceReport } from "../conformance.ts";

import { isRecord } from "../../core/guards.ts";
import { MAX_PAGE_SORTS } from "../../core/page-sort.ts";
import { conform, expect, Violation } from "../conformance.ts";

/** The options of `page` the kit sends (the block list contract, ADR 1077). */
export interface BlockListPageOptions {
  readonly q?: string;
  readonly sort?: PageSort | readonly PageSort[];
  readonly filters?: Readonly<Record<string, readonly string[]>>;
  readonly after?: readonly string[];
  readonly limit?: number;
}

/**
 * The list surface of one block entity: what `entityList` builds, plus the
 * `get` the block exposes for the same entity. Only `page` is required; the kit
 * skips the checks of a read the target does not have, and `testBlockList`
 * options say which of them the entity declares.
 */
export interface BlockListTarget<Item> {
  readonly page: (
    options?: BlockListPageOptions,
  ) => PromiseLike<Result<ListPage<Item>>>;
  readonly count?: (
    options?: Pick<BlockListPageOptions, "filters" | "q">,
  ) => PromiseLike<Result<Count>>;
  readonly facets?: (
    options?: Pick<BlockListPageOptions, "filters" | "q"> & {
      readonly facets?: readonly string[];
    },
  ) => PromiseLike<Result<readonly FacetResult[]>>;
  /** `ok(null)` or a `not_found` error both mean the id is unknown. */
  readonly get?: (id: string) => PromiseLike<Result<Item | null | undefined>>;
}

export interface TestBlockListOptions<Item> {
  /** The entity, for the report's subject: `leave.requests`. */
  readonly name: string;
  readonly target: BlockListTarget<Item>;
  /** A sort declared by the entity. Needs two or more rows to mean anything. */
  readonly sorts?: readonly string[];
  /**
   * A facet column and, per value, how many seeded rows hold it. The kit checks
   * `facets` reports the same counts.
   */
  readonly facets?: Readonly<Record<string, Readonly<Record<string, number>>>>;
  /**
   * An array filter: a column with two seeded values. The kit checks the union
   * of the two single-value reads equals the two-value read.
   */
  readonly arrayFilter?: {
    readonly column: string;
    readonly values: readonly [string, string];
  };
  /**
   * A search that matches some seeded rows and not all of them. Leave it out
   * when the entity declares no `q`.
   */
  readonly search?: string;
  /** Default `item.id`. */
  readonly idOf?: (item: Item) => string;
  /**
   * Rows seeded in the tenant the target reads. At least 3 so a page of 1 has a
   * next page and a keyset walk crosses a boundary.
   */
  readonly rows: number;
}

const DEFAULT_ID = (item: unknown): string => {
  const id = isRecord(item) ? item["id"] : undefined;

  expect(
    typeof id === "string",
    "a row has no string `id`; pass `idOf` to testBlockList",
  );

  return id;
};

async function read<T>(call: PromiseLike<Result<T>>, what: string): Promise<T> {
  const result = await call;

  if (!result.ok) {
    throw new Violation(
      `${what} returned an error: ${result.error.kind}: ${result.error.message}`,
    );
  }

  return result.data;
}

/**
 * Runs the block list contract (ADR 1077) against one entity's list surface
 * over seeded rows: a typed `page` with a keyset cursor, a single sort and a
 * list of sorts, array filters, `q`, `count`, `facets` and `get`. Throws a
 * `ConformanceError` that lists every failed check.
 */
export function testBlockList<Item>(
  options: TestBlockListOptions<Item>,
): Promise<ConformanceReport> {
  const { target, rows, sorts = [], arrayFilter, search } = options;
  const idOf = options.idOf ?? ((item: Item) => DEFAULT_ID(item));
  const idsOf = (page: ListPage<Item>): string[] => page.items.map(idOf);

  const all = async (extra: BlockListPageOptions = {}): Promise<string[]> =>
    idsOf(await read(target.page({ ...extra, limit: rows + 5 }), "page"));

  const checks: Check[] = [
    [
      "page returns items, hasMore and nextCursor",
      async () => {
        const page = await read(target.page(), "page");

        expect(Array.isArray(page.items), "items is not an array");
        expect(typeof page.hasMore === "boolean", "hasMore is not a boolean");
        expect(
          page.nextCursor === null || Array.isArray(page.nextCursor),
          "nextCursor is neither null nor a list",
        );
        expect(
          page.hasMore === (page.nextCursor !== null),
          "hasMore and nextCursor disagree",
        );
      },
    ],
    [
      "the seeded rows are all there",
      async () => {
        const ids = await all();

        expect(ids.length === rows, `${ids.length} rows read, ${rows} seeded`);
        expect(new Set(ids).size === ids.length, "a row appears twice");
      },
    ],
    [
      "limit is respected",
      async () => {
        const page = await read(target.page({ limit: 1 }), "page");

        expect(page.items.length === 1, `${page.items.length} rows, not 1`);
        expect(page.hasMore, "hasMore is false with rows left");
      },
    ],
    [
      "following nextCursor walks every row once",
      async () => {
        const seen: string[] = [];
        let after: readonly string[] | undefined;

        for (let step = 0; step <= rows; step += 1) {
          const page = await read(
            target.page({ limit: 1, ...(after ? { after } : {}) }),
            "page",
          );

          seen.push(...idsOf(page));

          if (page.nextCursor === null) {
            break;
          }

          after = page.nextCursor;
        }

        expect(seen.length === rows, `${seen.length} rows walked of ${rows}`);
        expect(new Set(seen).size === seen.length, "a cursor repeated a row");
        expect(
          JSON.stringify(seen) === JSON.stringify(await all()),
          "the walk and one big page are in different orders",
        );
      },
    ],
  ];

  for (const by of sorts) {
    checks.push([
      `sort "${by}" reverses with direction`,
      async () => {
        const asc = await all({ sort: { by, direction: "asc" } });
        const desc = await all({ sort: { by, direction: "desc" } });

        expect(asc.length === desc.length, "the sorts read different rows");
        expect(
          JSON.stringify(asc.toReversed()) === JSON.stringify(desc),
          `"${by}" asc reversed is not desc (ties need a stable id order)`,
        );
      },
    ]);
  }

  if (sorts.length >= 2) {
    const terms = sorts.slice(0, MAX_PAGE_SORTS);

    checks.push([
      "a list of sorts is accepted and reported",
      async () => {
        const sort: readonly PageSort[] = terms.map((by, index) => ({
          by,
          direction: index % 2 === 0 ? "asc" : "desc",
        }));

        const { sorted } = await read(
          target.page({ sort, limit: rows }),
          "page",
        );

        expect(
          sorted !== undefined,
          "the page does not say which sorts it applied (ADR 0896)",
        );

        const reported = sorted.applied.length + sorted.ignored.length;

        expect(
          reported === sort.length,
          `applied and ignored hold ${reported} of ${sort.length} sorts`,
        );
      },
    ]);
  }

  if (arrayFilter !== undefined) {
    const { column, values } = arrayFilter;

    checks.push([
      "an array filter matches any of its values",
      async () => {
        const [a, b, both] = await Promise.all([
          all({ filters: { [column]: [values[0]] } }),
          all({ filters: { [column]: [values[1]] } }),
          all({ filters: { [column]: [...values] } }),
        ]);

        const union = new Set([...a, ...b]);

        expect(a.length > 0 && b.length > 0, "a value matches no seeded row");
        expect(
          both.length === union.size && both.every((id) => union.has(id)),
          `"${column}" with two values reads ${both.length} rows, the union is ${union.size}`,
        );
      },
    ]);
  }

  if (search !== undefined) {
    checks.push([
      "q narrows the rows",
      async () => {
        const found = await all({ q: search });

        expect(found.length > 0, "q matched no seeded row");
        expect(found.length < rows, "q matched every row");
      },
    ]);
  }

  const { count } = target;

  if (count !== undefined) {
    checks.push([
      "count returns { value, exact } for the same filters",
      async () => {
        const total = await read(count(), "count");

        expect(typeof total.value === "number", "value is not a number");
        expect(typeof total.exact === "boolean", "exact is not a boolean");
        expect(
          !total.exact || total.value === rows,
          `an exact count of ${total.value} for ${rows} rows`,
        );

        const found = await all(search === undefined ? {} : { q: search });

        const narrowed = await read(
          count(search === undefined ? {} : { q: search }),
          "count",
        );

        expect(
          !narrowed.exact || narrowed.value === found.length,
          "count and page disagree under the same filters",
        );
      },
    ]);
  }

  const { facets } = target;

  if (facets !== undefined && options.facets !== undefined) {
    const expected = options.facets;

    checks.push([
      "facets report the seeded counts",
      async () => {
        const names = Object.keys(expected);
        const results = await read(facets({ facets: names }), "facets");

        for (const [name, counts] of Object.entries(expected)) {
          const found = results.find((entry) => entry.facet === name);

          expect(found !== undefined, `no result for facet "${name}"`);

          for (const [value, wanted] of Object.entries(counts)) {
            const entry = found.values.find((item) => item.value === value);

            expect(
              entry?.count.value === wanted,
              `facet "${name}" value "${value}" is ${entry?.count.value}, not ${wanted}`,
            );
          }
        }
      },
    ]);
  }

  const { get } = target;

  if (get !== undefined) {
    checks.push([
      "get returns the row the list returned, and not_found for an unknown id",
      async () => {
        const [first] = (await read(target.page({ limit: 1 }), "page")).items;

        expect(first !== undefined, "no row to get");

        const found = await read(get(idOf(first)), "get");

        expect(
          found !== null && found !== undefined && idOf(found) === idOf(first),
          "get returned another row",
        );

        const missing = await get("00000000-0000-4000-8000-000000000000");

        expect(
          missing.ok
            ? missing.data === null || missing.data === undefined
            : missing.error.kind === "not_found",
          "get of an unknown id neither returned null nor a not_found error",
        );
      },
    ]);
  }

  return conform(`BlockList "${options.name}"`, checks);
}
