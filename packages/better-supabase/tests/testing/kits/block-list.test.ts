import { describe, expect, it } from "vitest";

import type { ListPage } from "../../../src/core/block-helpers.ts";
import type { PageSort } from "../../../src/core/page-sort.ts";
import type {
  BlockListPageOptions,
  BlockListTarget,
} from "../../../src/testing/kits/block-list.ts";

import { dbError } from "../../../src/core/errors.ts";
import { err, ok } from "../../../src/core/result.ts";
import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testBlockList } from "../../../src/testing/kits/block-list.ts";

interface Row {
  readonly id: string;
  readonly title: string;
  readonly status: string;
  readonly rank: number;
}

const ROWS: readonly Row[] = [
  { id: "a", title: "alpha", status: "open", rank: 3 },
  { id: "b", title: "beta", status: "open", rank: 1 },
  { id: "c", title: "gamma", status: "closed", rank: 2 },
  { id: "d", title: "delta", status: "paused", rank: 4 },
];

const sortsOf = (sort: BlockListPageOptions["sort"]): readonly PageSort[] =>
  sort === undefined ? [] : "by" in sort ? [sort] : sort;

/** A list over an array that follows the contract. */
function memoryList(): BlockListTarget<Row> {
  const select = (options: BlockListPageOptions = {}): Row[] => {
    let rows = ROWS.filter((row) =>
      Object.entries(options.filters ?? {}).every(([column, values]) =>
        // SAFETY: the test filters columns that hold strings.
        values.includes(
          String((row as unknown as Record<string, unknown>)[column]),
        ),
      ),
    );

    if (options.q !== undefined) {
      const q = options.q;
      rows = rows.filter((row) => row.title.includes(q));
    }

    const [term] = sortsOf(options.sort);
    const by = term?.by === "rank" ? "rank" : "id";
    const sign = term?.direction === "desc" ? -1 : 1;

    return rows.toSorted((x, y) =>
      x[by] === y[by]
        ? x.id.localeCompare(y.id) * sign
        : (x[by] > y[by] ? 1 : -1) * sign,
    );
  };

  return {
    page: (options = {}) => {
      const rows = select(options);
      const start = options.after === undefined ? 0 : Number(options.after[0]);
      const limit = options.limit ?? 2;
      const items = rows.slice(start, start + limit);
      const hasMore = start + limit < rows.length;

      const page: ListPage<Row> = {
        items,
        hasMore,
        nextCursor: hasMore ? [String(start + limit)] : null,
        ...(options.sort === undefined
          ? {}
          : {
              sorted: {
                applied: sortsOf(options.sort).slice(0, 1),
                ignored: sortsOf(options.sort).slice(1),
              },
            }),
      };

      return Promise.resolve(ok(page));
    },
    count: (options) =>
      Promise.resolve(ok({ value: select(options).length, exact: true })),
    facets: () =>
      Promise.resolve(
        ok([
          {
            facet: "status",
            values: ["open", "closed", "paused"].map((value) => ({
              value,
              count: {
                value: ROWS.filter((row) => row.status === value).length,
                exact: true,
              },
            })),
          },
        ]),
      ),
    get: (id) => {
      const row = ROWS.find((item) => item.id === id);

      return Promise.resolve(
        row === undefined ? err(dbError("not_found", "no row")) : ok(row),
      );
    },
  };
}

const options = {
  name: "demo.rows",
  rows: ROWS.length,
  sorts: ["rank", "id"],
  facets: { status: { open: 2, closed: 1, paused: 1 } },
  arrayFilter: { column: "status", values: ["closed", "paused"] as const },
  search: "ta",
};

describe("testBlockList", () => {
  it("passes a list that follows the contract", async () => {
    const report = await testBlockList({ ...options, target: memoryList() });

    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks.length).toBeGreaterThan(8);
  });

  it("fails a page that ignores the cursor and a get that never misses", async () => {
    const target: BlockListTarget<Row> = {
      ...memoryList(),
      page: (pageOptions) => memoryList().page({ ...pageOptions, after: [] }),
      get: (id) =>
        Promise.resolve(ok(ROWS.find((row) => row.id === id) ?? ROWS[0])),
    };

    const error = await testBlockList({ ...options, target }).then(
      () => undefined,
      (cause: unknown) => cause,
    );

    expect(error).toBeInstanceOf(ConformanceError);

    const failed = (error as ConformanceError).report.checks
      .filter((check) => !check.ok)
      .map((check) => check.name);

    expect(failed).toContain("following nextCursor walks every row once");
    expect(failed).toContain(
      "get returns the row the list returned, and not_found for an unknown id",
    );
  });

  it("fails a list of sorts the page does not report", async () => {
    const base = memoryList();

    const target: BlockListTarget<Row> = {
      ...base,
      page: async (pageOptions) => {
        const result = await base.page(pageOptions);

        if (!result.ok) {
          return result;
        }

        const { sorted: _sorted, ...rest } = result.data;

        return ok(rest);
      },
    };

    await expect(testBlockList({ ...options, target })).rejects.toThrow(
      /does not say which sorts/,
    );
  });
});
