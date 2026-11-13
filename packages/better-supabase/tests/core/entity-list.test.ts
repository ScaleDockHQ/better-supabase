import { describe, expect, it } from "vitest";

import type { BlockCall } from "../../src/core/block-helpers.ts";

import { listFilters, entityList } from "../../src/core/entity-list.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";

const SURFACE = {
  sorts: ["createdAt", "title"],
  facets: ["status", "kind"],
  filters: ["status", "kind"],
  search: true,
};

const SPEC = { entity: "thing", surface: SURFACE };

function facetOf(args: Record<string, unknown>): unknown {
  const filters = args["filters"];

  return typeof filters === "object" && filters !== null && "facet" in filters
    ? filters.facet
    : undefined;
}

function listOf(reply: (args: Record<string, unknown>) => unknown) {
  const calls: Record<string, unknown>[] = [];

  const call: BlockCall = (_fn, args, then) => {
    calls.push(args);

    return AsyncResult.from(async () => ok(await then(reply(args))));
  };

  const list = entityList({
    ...SPEC,
    call,
    tenant: () => AsyncResult.ok("org-1"),
    fn: "list_things",
    rowOf: (row) => ({ id: String(row["id"]) }),
  });

  return { list, calls };
}

describe("listFilters", () => {
  it("passes sort, list filters, text, cursor and limit to the SQL filters", () => {
    const result = listFilters(SPEC, {
      sort: { by: "title", direction: "desc" },
      filters: { status: ["open", "done"] },
      q: "pump",
      after: ["a", "b"],
      limit: 5,
    });

    expect(result).toEqual({
      ok: true,
      data: {
        sort: "title",
        direction: "desc",
        status: ["open", "done"],
        search: "pump",
        after: ["a", "b"],
        limit: 5,
      },
      error: null,
    });
  });

  it("adds the always-on filters of the block first", () => {
    const result = listFilters({ ...SPEC, base: { mine: true } });

    expect(result.ok && result.data).toEqual({ mine: true });
  });

  it("rejects an undeclared sort, filter or text search", () => {
    const sort = listFilters(SPEC, { sort: { by: "colour" } });
    const filter = listFilters(SPEC, { filters: { colour: ["red"] } });
    const text = listFilters({ entity: "thing", surface: {} }, { q: "x" });

    for (const result of [sort, filter, text]) {
      expect(result.ok).toBe(false);
      expect(result.error?.kind).toBe("invalid_input");
    }
  });

  it("ignores an empty text", () => {
    const result = listFilters({ entity: "thing", surface: {} }, { q: "" });

    expect(result.ok).toBe(true);
  });
});

describe("entityList", () => {
  it("reads a page and maps its rows", async () => {
    const { list, calls } = listOf(() => ({
      items: [{ id: "1" }],
      hasMore: false,
      nextCursor: null,
    }));

    const page = await list.page({ filters: { status: ["open"] } }).orThrow();

    expect(page.items).toEqual([{ id: "1" }]);
    expect(calls).toEqual([
      { tenant: "org-1", filters: { status: ["open"], paged: true } },
    ]);
  });

  it("counts every declared facet by default, in one call each", async () => {
    const { list, calls } = listOf((args) => ({
      facet: facetOf(args),
      values: [{ value: "a", count: { value: 4, exact: true } }],
    }));

    const facets = await list.facets({ q: "pump" }).orThrow();

    expect(facets.map((facet) => facet.facet)).toEqual(["status", "kind"]);
    expect(facets[0]?.values).toEqual([
      { value: "a", count: { value: 4, exact: true } },
    ]);
    expect(calls).toHaveLength(2);
    expect(calls[0]).toEqual({
      tenant: "org-1",
      filters: { search: "pump", facet: "status" },
    });
  });

  it("rejects a facet the entity does not declare without calling", async () => {
    const { list, calls } = listOf(() => ({}));

    const result = await list.facets({ facets: ["colour"] });

    expect(result.ok).toBe(false);
    expect(calls).toEqual([]);
  });

  it("returns the count with its exactness", async () => {
    const { list } = listOf(() => ({ value: 10_000, exact: false }));

    await expect(list.count().orThrow()).resolves.toEqual({
      value: 10_000,
      exact: false,
    });
  });

  it("fails a count the SQL answered with something else", async () => {
    const { list } = listOf(() => ({ value: "ten" }));

    const result = await list.count();

    expect(result.ok).toBe(false);
  });
});
