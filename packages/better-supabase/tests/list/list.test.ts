import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery, UNSET } from "../../src/list/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);
const list = defineListQuery(betterSupabase, "customers", {
  search: ["name", "kvk"],
  facets: { status: "status", kvk: "kvk" },
  sorts: {
    name: { name: "asc" },
    newest: [{ createdAt: "desc" }, { id: "asc" }],
  },
  defaultSort: "newest",
  pageSize: 25,
});

describe("defineListQuery", () => {
  it("parses URL params with defaults, comma lists and repeated keys", () => {
    const result = list.parse(
      new URLSearchParams("q=  road  &status=active,lead&status=active&page=2"),
    );
    expect(result).toEqual({
      ok: true,
      value: {
        q: "road",
        sort: "newest",
        page: 2,
        size: 25,
        facets: { status: ["active", "lead"] },
      },
    });
    expect(list.parse({ sort: "name", size: "10" })).toMatchObject({
      ok: true,
      value: { sort: "name", size: 10 },
    });
    expect(list.parse(undefined)).toEqual({ ok: true, value: list.defaults });
  });

  it("parses typed input", () => {
    expect(
      list.parse({ q: "x", facets: { status: ["archived"] }, page: 3 }),
    ).toMatchObject({
      ok: true,
      value: { q: "x", page: 3, facets: { status: ["archived"] } },
    });
  });

  it("reports every problem with a path", () => {
    const result = list.parse(
      new URLSearchParams(`sort=oldest&page=0&size=500&status=bogus,${UNSET}`),
    );
    expect(result.issues?.map((issue) => issue.path)).toEqual([
      ["sort"],
      ["page"],
      ["size"],
      ["facets", "status"],
      ["facets", "status"],
    ]);
    expect(list.parse({ q: "x".repeat(201) }).issues).toEqual([
      { message: "At most 200 characters", path: ["q"] },
    ]);
  });

  it("round-trips through URL params, leaving out defaults", () => {
    const query = list.parse({
      q: "a,b",
      sort: "name",
      facets: { kvk: [UNSET, "1001"] },
    }).value!;
    const params = list.toSearchParams(query);
    expect(params.toString()).toBe("q=a%2Cb&sort=name&kvk=__unset__%2C1001");
    expect(list.parse(params).value).toEqual({
      ...query,
      facets: { kvk: [UNSET, "1001"] },
    });
    expect(list.toSearchParams(list.defaults).toString()).toBe("");
  });

  it("compiles to safe PostgREST filters and merges extra arguments", async () => {
    const { client, last } = capturingClient((request) => ({
      body: [{ id: "c1", name: "Acme" }],
      headers: request.headers.get("prefer")?.includes("count")
        ? { "content-range": "0-0/1" }
        : {},
    }));
    const db = betterSupabase.connect(client);
    const query = list.parse({
      q: "o,(x)",
      facets: { status: ["active"], kvk: [UNSET, "1001"] },
    }).value!;
    const page = await list
      .run(db, query, {
        select: ["id", "name"],
        where: { organizationId: "org-1" },
      })
      .orThrow();
    expect(page).toEqual({
      items: [{ id: "c1", name: "Acme" }],
      page: { number: 1, size: 25, total: 1, pages: 1, hasMore: false },
    });
    const params = last().params;
    expect(params.get("organization_id")).toBe("eq.org-1");
    expect(params.getAll("or")).toEqual([
      '(name.ilike."%o,(x)%",kvk.ilike."%o,(x)%")',
      '(kvk.in.("1001"),kvk.is.null)',
    ]);
    expect(params.get("status")).toBe('in.("active")');
    expect(params.get("order")).toBe("created_at.desc,id.asc");
    expect(params.get("limit")).toBe("26");
  });

  it("counts facet values next to the page in one wave", async () => {
    const faceted = defineListQuery(betterSupabase, "customers", {
      search: ["name"],
      facets: { status: "status", kvk: "kvk" },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      facetCounts: true,
      count: "planned",
    });
    const { client, requests } = capturingClient((request) =>
      request.params.get("select")?.includes("count()")
        ? {
            body: [
              { status: "active", kvk: "1001", _count: 3 },
              { status: "active", kvk: null, _count: 2 },
              { status: "lead", kvk: "1001", _count: 4 },
              { status: "lead", kvk: "2002", _count: 5 },
            ],
          }
        : { body: [{ id: "c1" }], headers: { "content-range": "0-0/1" } },
    );
    const db = betterSupabase.connect(client);
    const query = faceted.parse({
      q: "acme",
      facets: { status: ["active"] },
    }).value!;
    const page = await faceted
      .run(db, query, { select: ["id"], where: { organizationId: "org-1" } })
      .orThrow();
    expect(page.facetCounts).toEqual({
      status: { active: 5, lead: 9, archived: 0 },
      kvk: { "1001": 3, [UNSET]: 2 },
    });
    expect(db.$stats()).toMatchObject({ calls: 2, waves: 1 });

    const [pageRequest, groupRequest] = requests;
    expect(pageRequest!.headers.get("prefer")).toContain("count=planned");
    expect(pageRequest!.params.get("status")).toBe('in.("active")');
    expect(groupRequest!.params.get("status")).toBeNull();
    expect(groupRequest!.params.get("organization_id")).toBe("eq.org-1");
    expect(groupRequest!.params.toString()).toContain("acme");

    await faceted.run(db, query, { count: "estimated" }).orThrow();
    expect(requests[2]!.headers.get("prefer")).toContain("count=estimated");
  });

  it("fails the run when the facet counts fail", async () => {
    const faceted = defineListQuery(betterSupabase, "customers", {
      facets: { status: "status" },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      facetCounts: true,
    });
    const { client } = capturingClient((request) =>
      request.params.get("select")?.includes("count()")
        ? {
            status: 400,
            body: {
              code: "PGRST123",
              message: "Use of aggregate functions is not allowed",
            },
          }
        : { body: [] },
    );
    const result = await faceted.run(
      betterSupabase.connect(client),
      faceted.defaults,
    );
    expect(result.ok).toBe(false);
  });

  it("describes itself for OpenAPI, JSON Schema and UIs", () => {
    expect(list.openapi.map((parameter) => parameter.name)).toEqual([
      "q",
      "sort",
      "page",
      "size",
      "status",
      "kvk",
    ]);
    expect(
      list.openapi.find((parameter) => parameter.name === "status"),
    ).toMatchObject({
      style: "form",
      explode: false,
      schema: {
        type: "array",
        items: { enum: ["lead", "active", "archived"] },
      },
    });
    expect(list.jsonSchema).toMatchObject({
      properties: {
        sort: { enum: ["name", "newest"], default: "newest" },
        facets: { properties: { kvk: { items: { type: "string" } } } },
      },
    });
    expect(list.facets).toEqual([
      {
        key: "status",
        column: "status",
        nullable: false,
        values: ["lead", "active", "archived"],
      },
      { key: "kvk", column: "kvk", nullable: true },
    ]);
  });

  it("is a Standard Schema and builds nuqs parsers", async () => {
    const outcome = await list.schema["~standard"].validate({ sort: "name" });
    expect(outcome).toMatchObject({ value: { sort: "name" } });
    const created: unknown[] = [];
    const parsers = list.nuqs((spec) => {
      created.push(spec);
      return { spec };
    });
    expect(Object.keys(parsers)).toEqual([
      "q",
      "sort",
      "page",
      "after",
      "size",
      "status",
      "kvk",
    ]);
    expect(list.parsers.status.parse("a, b")).toEqual(["a", "b"]);
    expect(list.parsers.sort.parse("oldest")).toBeNull();
  });

  it("rejects broken definitions", () => {
    expect(() =>
      defineListQuery(betterSupabase, "customers", {
        sorts: { name: { name: "asc" } },
        defaultSort: "nope" as "name",
      }),
    ).toThrow(/defaultSort/);
    expect(() =>
      defineListQuery(betterSupabase, "customers", {
        facets: { page: "status" },
        sorts: { name: { name: "asc" } },
        defaultSort: "name",
      }),
    ).toThrow(/reserved/);
    expect(() =>
      // @ts-expect-error unknown table
      defineListQuery(betterSupabase, "nope", {
        sorts: { name: { name: "asc" } },
        defaultSort: "name",
      }),
    ).toThrow('defineListQuery: unknown table "nope"');
    expect(() =>
      defineListQuery(betterSupabase, "customers", {
        // @ts-expect-error unknown column
        facets: { color: "color" },
        sorts: { name: { name: "asc" } },
        defaultSort: "name",
      }),
    ).toThrow('defineListQuery: unknown column "customers.color"');
  });

  it("rejects inputs that are not objects or have bad values", () => {
    // @ts-expect-error not an object
    expect(list.parse("q=x")).toEqual({
      ok: false,
      issues: [{ message: "Expected an object or URL parameters" }],
    });
    expect(list.parse({ q: 5 as unknown as string }).issues).toEqual([
      { message: "Must be text", path: ["q"] },
    ]);
    expect(
      list.parse({ q: null as unknown as string }).value?.q,
    ).toBeUndefined();
    expect(list.parse({ q: "   " }).value).not.toHaveProperty("q");
    expect(
      list.parse({ facets: { status: "active" as unknown as string[] } }),
    ).toEqual({
      ok: false,
      issues: [
        { message: "Must be a list of values", path: ["facets", "status"] },
      ],
    });
    expect(
      list.parse({ facets: { status: [1] as unknown as string[] } }).issues,
    ).toEqual([
      { message: "Must be a list of values", path: ["facets", "status"] },
    ]);
  });

  it("reads a Next.js searchParams record with repeated keys as URL input", () => {
    expect(
      list.parse({
        status: ["active", "lead,archived"],
        page: "2",
        q: undefined,
      }),
    ).toEqual({
      ok: true,
      value: {
        sort: "newest",
        page: 2,
        size: 25,
        facets: { status: ["active", "lead", "archived"] },
      },
    });
  });

  it("accepts typed numbers and rejects fractions, text and empty sorts", () => {
    expect(list.parse({ page: 2, size: 10 })).toMatchObject({
      ok: true,
      value: { page: 2, size: 10 },
    });
    expect(list.parse({ sort: "" as "name" }).value?.sort).toBe("newest");
    expect(
      list
        .parse({ page: 1.5, size: "ten" as unknown as number })
        .issues?.map((issue) => issue.path),
    ).toEqual([["page"], ["size"]]);
    expect(list.parse(new URLSearchParams("page=&size=")).value).toMatchObject({
      page: 1,
      size: 25,
    });
  });

  it("builds filters for empty-only, mixed and full-text searches", () => {
    const empty = list.parse({ facets: { kvk: [UNSET] } }).value!;
    expect(list.args(empty)).toMatchObject({ where: { kvk: null } });
    const mixed = list.parse({ facets: { kvk: ["1", UNSET] } }).value!;
    expect(list.args(mixed)).toMatchObject({
      where: { OR: [{ kvk: { in: ["1"] } }, { kvk: null }] },
    });
    expect(list.args(list.defaults)).not.toHaveProperty("where");

    const fts = defineListQuery(betterSupabase, "customers", {
      search: { fts: "name", config: "dutch" },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });
    expect(fts.args(fts.parse({ q: "road" }).value!)).toMatchObject({
      where: { name: { search: { query: "road", config: "dutch" } } },
      count: "exact",
      page: 1,
      size: 50,
    });
    expect(fts.openapi[0]).toMatchObject({
      name: "q",
      description: "Full-text search (web search syntax).",
    });
    const plain = defineListQuery(betterSupabase, "customers", {
      search: { fts: "name" },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });
    expect(plain.args(plain.parse({ q: "road" }).value!)).toMatchObject({
      where: { name: { search: "road" } },
    });

    const none = defineListQuery(betterSupabase, "customers", {
      search: [],
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });
    expect(none.args(none.parse({ q: "road" }).value!)).not.toHaveProperty(
      "where",
    );
    const unsearchable = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });
    expect(unsearchable.openapi.map((parameter) => parameter.name)).toEqual([
      "sort",
      "page",
      "size",
    ]);
    expect(unsearchable.jsonSchema["properties"]).not.toHaveProperty("q");
    expect(unsearchable.jsonSchema["properties"]).not.toHaveProperty("facets");
  });

  it("writes non-default pages and sizes to URL params", () => {
    expect(
      list
        .toSearchParams({
          sort: "newest",
          page: 3,
          size: 10,
          facets: { status: [] },
        })
        .toString(),
    ).toBe("page=3&size=10");
  });

  it("parses each URL value with its parser", () => {
    expect(list.parsers.q.parse("  hi ")).toBe("hi");
    expect(list.parsers.q.parse("   ")).toBeNull();
    expect(list.parsers.q.serialize("hi")).toBe("hi");
    expect(list.parsers.sort.parse("name")).toBe("name");
    expect(list.parsers.sort.serialize("name")).toBe("name");
    expect(list.parsers.page.parse("4")).toBe(4);
    expect(list.parsers.page.parse("4a")).toBeNull();
    expect(list.parsers.size.serialize(10)).toBe("10");
    expect(list.parsers.status.parse(" , ")).toBeNull();
    expect(list.parsers.status.serialize(["a", "b"])).toBe("a,b");
  });

  it("reports issues through the Standard Schema", async () => {
    expect(await list.schema["~standard"].validate({ sort: "oldest" })).toEqual(
      {
        issues: [{ message: "Must be one of: name, newest", path: ["sort"] }],
      },
    );
  });

  it("adds empty facet counts when there are no facets", async () => {
    const counted = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      facetCounts: true,
    });
    const { client, requests } = capturingClient(() => ({
      body: [{ id: "c1" }],
      headers: { "content-range": "0-0/1" },
    }));
    const page = await counted
      .run(betterSupabase.connect(client), counted.defaults)
      .orThrow();
    expect(page.facetCounts).toEqual({});
    expect(page.items).toEqual([{ id: "c1" }]);
    expect(requests).toHaveLength(1);
  });

  it("counts empty values and rows without _count, filtering by other facets", async () => {
    const faceted = defineListQuery(betterSupabase, "customers", {
      facets: { status: "status", kvk: "kvk" },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      facetCounts: true,
    });
    const { client } = capturingClient((request) =>
      request.params.get("select")?.includes("count()")
        ? {
            body: [
              { status: "lead", kvk: null, _count: 2 },
              { status: "active", kvk: null },
              { status: "lead", kvk: "9", _count: 7 },
            ],
          }
        : { body: [], headers: { "content-range": "*/0" } },
    );
    const query = faceted.parse({ facets: { kvk: [UNSET] } }).value!;
    const page = await faceted
      .run(betterSupabase.connect(client), query)
      .orThrow();
    expect(page.facetCounts).toEqual({
      status: { lead: 2, active: 0, archived: 0 },
      kvk: { [UNSET]: 2, "9": 7 },
    });
  });

  it("pages by cursor when pagination is cursor", async () => {
    const cursorList = defineListQuery(betterSupabase, "customers", {
      sorts: { name: [{ name: "asc" }, { id: "asc" }] },
      defaultSort: "name",
      pagination: "cursor",
      pageSize: 1,
      maxPageSize: 2,
    });
    expect(cursorList.pagination).toBe("cursor");
    expect(cursorList.parse({ page: 2 }).issues).toEqual([
      { message: "This list pages with `after`, not `page`", path: ["page"] },
    ]);
    expect(cursorList.parse({ size: 3 }).ok).toBe(false);
    expect(cursorList.parse({ after: 1 } as never).issues).toEqual([
      { message: "Must be text", path: ["after"] },
    ]);
    expect(list.parse(new URLSearchParams("after=abc")).issues).toEqual([
      { message: "This list pages with `page`, not `after`", path: ["after"] },
    ]);
    const first = cursorList.parse(new URLSearchParams()).value!;
    expect(cursorList.args(first)).toEqual({
      orderBy: [{ name: "asc" }, { id: "asc" }],
      size: 1,
      after: null,
    });

    const { client, last } = capturingClient(() => ({
      body: [
        { id: "c1", name: "Acme" },
        { id: "c2", name: "Beta" },
      ],
    }));
    const db = betterSupabase.connect(client);
    const page = await cursorList
      .run(db, first, { select: ["id", "name"] })
      .orThrow();
    expect(page.items).toEqual([{ id: "c1", name: "Acme" }]);
    expect(page.hasMore).toBe(true);
    expect(last().headers.get("prefer") ?? "").not.toContain("count");

    const next = cursorList.parse(
      cursorList.toSearchParams({ after: page.nextCursor! }),
    ).value!;
    expect(next.after).toBe(page.nextCursor);
    await cursorList.run(db, next, { select: ["id", "name"] }).orThrow();
    expect(last().params.get("or")).toBe(
      '(name.gt."Acme",and(name.eq."Acme",id.gt."c1"))',
    );
    expect(cursorList.parsers.after.parse("")).toBeNull();
    expect(cursorList.parsers.after.serialize("x")).toBe("x");
    expect(cursorList.openapi.map((parameter) => parameter.name)).toEqual([
      "sort",
      "after",
      "size",
    ]);
    expect(Object.keys(cursorList.jsonSchema["properties"] as object)).toEqual([
      "sort",
      "after",
      "size",
    ]);
  });
});
