import { AsyncResult, ok } from "better-supabase";
import { describe, expect, it } from "vitest";

import { loadedPager } from "@/lib/loaded-pager";

interface Row {
  readonly name: string;
  readonly kind: string;
}

const rows: readonly Row[] = [
  { name: "Charlie", kind: "a" },
  { name: "Alpha", kind: "b" },
  { name: "Bravo", kind: "a" },
];

const pager = () =>
  loadedPager(() => AsyncResult.from(async () => ok(rows)), {
    search: (row) => row.name,
    facets: { kind: (row) => row.kind },
    sorts: { name: (a, b) => a.name.localeCompare(b.name) },
  });

describe("loadedPager", () => {
  it("searches, filters, sorts and pages with an offset cursor", async () => {
    const first = await pager().page({
      sort: { by: "name" },
      filters: { kind: ["a"] },
      limit: 1,
    });

    expect(first.ok && first.data.items.map((row) => row.name)).toEqual([
      "Bravo",
    ]);

    expect(first.ok && first.data.nextCursor).toEqual(["1"]);

    const next = await pager().page({
      sort: { by: "name", direction: "desc" },
      filters: { kind: ["a"] },
      limit: 1,
      after: ["1"],
    });

    expect(next.ok && next.data.items.map((row) => row.name)).toEqual([
      "Bravo",
    ]);

    expect(next.ok && next.data.hasMore).toBe(false);

    const searched = await pager().page({ q: "alp", limit: 5 });

    expect(searched.ok && searched.data.items).toHaveLength(1);
  });

  it("counts a facet without its own filter", async () => {
    const facets = await pager().facets({ filters: { kind: ["a"] } });

    expect(
      facets.ok &&
        facets.data[0]?.values.map((value) => value.value).toSorted(),
    ).toEqual(["a", "b"]);
  });
});
