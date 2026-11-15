import { ok } from "better-supabase";
import { describe, expect, it } from "vitest";

import type { BlockListSpec } from "@/lib/array-list";

import { arrayReads } from "@/lib/array-reads";

interface Item {
  readonly name: string;
  readonly kind: string;
  readonly size: number;
}

const items: readonly Item[] = [
  { name: "beta", kind: "a", size: 2 },
  { name: "alpha", kind: "b", size: 3 },
  { name: "gamma", kind: "a", size: 1 },
];

const spec: BlockListSpec<Item> = {
  search: (item) => item.name,
  facet: (item) => item.kind,
  defaultSort: "name",
  sorts: {
    name: (a, b) => a.name.localeCompare(b.name),
    size: (a, b) => b.size - a.size,
  },
};

function reads() {
  return arrayReads({
    load: () => Promise.resolve(ok(items)) as never,
    facet: "kind",
    spec,
    wire: (item) => item.name,
  });
}

describe("arrayReads", () => {
  it("sorts by the default sort and pages by offset", async () => {
    const first = await reads().page({ tenant: "t", limit: 2 });

    expect(first.ok && first.data.items).toEqual(["alpha", "beta"]);
    expect(first.ok && first.data.nextCursor).toEqual(["2"]);

    const second = await reads().page({ tenant: "t", limit: 2, after: ["2"] });

    expect(second.ok && second.data.items).toEqual(["gamma"]);
    expect(second.ok && second.data.hasMore).toBe(false);
  });

  it("applies the first sort term, the facet filter and the search", async () => {
    const sorted = await reads().page({
      tenant: "t",
      sort: [{ by: "size", direction: "desc" }, { by: "name" }],
    });

    expect(sorted.ok && sorted.data.items).toEqual(["alpha", "beta", "gamma"]);

    const filtered = await reads().page({
      tenant: "t",
      q: "ta",
      filters: { kind: ["a"] },
    });

    expect(filtered.ok && filtered.data.items).toEqual(["beta"]);
  });

  it("counts the facet after the search and answers nothing without a tenant", async () => {
    const counted = await reads().facets({ tenant: "t", q: "a" });

    expect(counted.ok && counted.data).toEqual([
      {
        facet: "kind",
        values: [
          { value: "a", count: { value: 2, exact: true } },
          { value: "b", count: { value: 1, exact: true } },
        ],
      },
    ]);

    const none = await reads().page({});

    expect(none.ok && none.data.items).toEqual([]);
  });
});
