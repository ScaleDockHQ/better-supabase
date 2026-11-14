import { describe, expect, it } from "vitest";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import {
  defineEntityListQuery,
  defineEntityPage,
} from "../../src/list/entity-page.ts";

const surface = {
  sorts: ["residualScore", "number"],
  facets: ["status", "category"],
  filters: ["status", "category", "ownerId"],
  search: true,
};

const list = defineEntityListQuery(surface, {
  entity: "risks.risk",
  pageSize: 25,
  maxPageSize: 100,
});

describe("defineEntityPage", () => {
  it("adds the version and keeps the descriptor", () => {
    expect(
      defineEntityPage({ entity: "risks.risk", route: "/risks" }),
    ).toStrictEqual({ apiVersion: 1, entity: "risks.risk", route: "/risks" });
  });

  it("refuses an entity without a block and a route without a slash", () => {
    expect(() => defineEntityPage({ entity: "risk", route: "/risks" })).toThrow(
      /<block>\.<entity>/,
    );

    expect(() =>
      defineEntityPage({ entity: "risks.risk", route: "risks" }),
    ).toThrow(/must start with/);
  });
});

describe("parse", () => {
  it("reads q, sort, filters, after and limit", () => {
    const parsed = list.parse(
      new URLSearchParams(
        "q=fire&sort=residualScore:desc&status=open,closed&ownerId=u1&after=3&after=abc&limit=10",
      ),
    );

    expect(parsed).toStrictEqual({
      ok: true,
      value: {
        q: "fire",
        sort: { by: "residualScore", direction: "desc" },
        filters: { status: ["open", "closed"], ownerId: ["u1"] },
        after: ["3", "abc"],
        limit: 10,
      },
    });
  });

  it("reads a Next.js searchParams record and no input", () => {
    expect(list.parse({ status: ["open", "closed"], q: "x" })).toStrictEqual({
      ok: true,
      value: { q: "x", filters: { status: ["open", "closed"] } },
    });

    expect(list.parse(undefined)).toStrictEqual({ ok: true, value: {} });
  });

  it("names every undeclared sort, direction and limit", () => {
    const parsed = list.parse(new URLSearchParams("sort=color:down&limit=500"));

    expect(parsed.ok).toBe(false);

    expect(
      parsed.ok ? [] : parsed.issues.map((issue) => issue.path),
    ).toStrictEqual([["sort"], ["limit"]]);

    const unknown = list.parse(new URLSearchParams("sort=color"));

    expect(unknown.ok ? "" : unknown.issues[0]?.message).toContain(
      "use residualScore, number",
    );
  });

  it("refuses q when the entity has no search", () => {
    const quiet = defineEntityListQuery({ sorts: ["a"] }, { entity: "x.y" });
    const parsed = quiet.parse({ q: "x" });

    expect(parsed.ok ? "" : parsed.issues[0]?.message).toBe(
      "x.y has no search.",
    );
  });

  it("falls back to the facets when the entity declares no filters", () => {
    const facetsOnly = defineEntityListQuery(
      { facets: ["status"] },
      { entity: "x.y" },
    );

    expect(facetsOnly.parse({ status: "open" })).toStrictEqual({
      ok: true,
      value: { filters: { status: ["open"] } },
    });
  });

  it("round-trips through toSearchParams", () => {
    const value = {
      q: "fire",
      sort: { by: "number", direction: "asc" as const },
      filters: { status: ["open", "closed"] },
      after: ["1", "2"],
      limit: 5,
    };

    const params = list.toSearchParams(value);

    expect(list.parse(params)).toStrictEqual({ ok: true, value });
    expect(
      list.toSearchParams({ q: "", sort: { by: "number" } }).toString(),
    ).toBe("sort=number");
  });
});

describe("schema", () => {
  const validate = (value: unknown) => list.schema["~standard"].validate(value);

  it("accepts options and undefined", () => {
    expect(validate(undefined)).toStrictEqual({ value: {} });

    expect(
      validate({ q: "x", sort: { by: "number" }, filters: { status: ["a"] } }),
    ).toStrictEqual({
      value: { q: "x", sort: { by: "number" }, filters: { status: ["a"] } },
    });
  });

  it("reports wrong shapes and undeclared names", () => {
    const issues = (value: unknown): readonly unknown[] => {
      const result = validate(value);

      return "issues" in result && result.issues !== undefined
        ? result.issues.map((issue) => issue.path)
        : [];
    };

    expect(issues("text")).toStrictEqual([undefined]);

    expect(
      issues({ q: 1, sort: {}, filters: { a: "x" }, after: "1", limit: "9" }),
    ).toStrictEqual([["q"], ["sort"], ["filters"], ["after"], ["limit"]]);

    expect(
      issues({ sort: { by: "color" }, filters: { owner: ["x"] } }),
    ).toStrictEqual([["sort"], ["filters", "owner"]]);
  });
});

describe("run", () => {
  const page = { items: [{ id: "1" }], hasMore: false, nextCursor: null };
  const facets = [{ facet: "status", values: [] }];

  it("reads the page and the facets under the same filters, with the default limit", async () => {
    const calls: Record<string, unknown>[] = [];

    const result = await list.run(
      {
        page: (options) => {
          calls.push({ page: options });

          return AsyncResult.ok(page);
        },
        facets: (options) => {
          calls.push({ facets: options });

          return AsyncResult.ok(facets);
        },
      },
      { q: "x", filters: { status: ["open"] }, sort: { by: "number" } },
      { organizationId: "org" },
    );

    expect(result).toStrictEqual(ok({ page, facets }));

    expect(calls).toStrictEqual([
      {
        page: {
          q: "x",
          filters: { status: ["open"] },
          sort: { by: "number" },
          limit: 25,
          organizationId: "org",
        },
      },
      {
        facets: {
          q: "x",
          filters: { status: ["open"] },
          organizationId: "org",
        },
      },
    ]);
  });

  it("keeps a limit the caller sets and sends no filters it has none of", async () => {
    let seen: unknown;
    let seenFacets: unknown;

    await list.run(
      {
        page: (options) => {
          seen = options;

          return AsyncResult.ok(page);
        },
        facets: (options) => {
          seenFacets = options;

          return AsyncResult.ok(facets);
        },
      },
      { limit: 5 },
    );

    expect(seen).toStrictEqual({ limit: 5 });
    expect(seenFacets).toStrictEqual({});
  });

  it("returns the error of a read", async () => {
    const failure = dbError("not_found", "boom");

    const pageFails = await list.run(
      {
        page: () => AsyncResult.err(failure),
        facets: () => AsyncResult.ok(facets),
      },
      {},
    );

    const facetsFail = await list.run(
      {
        page: () => AsyncResult.ok(page),
        facets: () => AsyncResult.err(failure),
      },
      {},
    );

    expect(pageFails).toStrictEqual(err(failure));
    expect(facetsFail).toStrictEqual(err(failure));
  });
});
