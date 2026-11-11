import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { freeSort } from "../../src/list/order/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = createSupabase(schema);

const list = defineListQuery(betterSupabase, "customers", {
  facets: {
    status: "status",
    noteKind: { relation: "notes", column: "kind" },
    org: { relation: "organization", column: "slug" },
  },
  freeSort: freeSort(betterSupabase, "customers", {
    sortable: ["name", "createdAt", "status"],
  }),
  sorts: { newest: [{ createdAt: "desc" }, { id: "asc" }] },
  defaultSort: "newest",
  pageSize: 10,
});

describe("relation facets", () => {
  it("parse like any facet, with the related column's enum", () => {
    expect(list.facets.find((facet) => facet.key === "noteKind")).toMatchObject(
      {
        column: "kind",
        relation: { name: "notes", many: true },
        values: ["call", "meeting", "email"],
      },
    );
    expect(
      list.parse(new URLSearchParams("noteKind=call,meeting&org=acme")).value,
    ).toMatchObject({
      facets: { noteKind: ["call", "meeting"], org: ["acme"] },
    });
    expect(list.parse({ facets: { noteKind: ["fax"] } }).issues).toEqual([
      {
        message: "Must be one of: call, meeting, email",
        path: ["facets", "noteKind"],
      },
    ]);
    expect(list.parse({ facets: { noteKind: ["__unset__"] } }).ok).toBe(false);
  });

  it("filter through some for a to-many and through the row for a to-one relation", () => {
    const query = list.parse({
      facets: { noteKind: ["call"], org: ["acme"] },
    }).value!;

    expect(list.args(query)).toMatchObject({
      where: {
        AND: [
          { notes: { some: { kind: { in: ["call"] } } } },
          { organization: { slug: { in: ["acme"] } } },
        ],
      },
    });
  });

  it("send a relation filter to PostgREST as an inner embed", async () => {
    const { client, last } = capturingClient(() => ({ body: [] }));
    const db = betterSupabase.connect(client);

    await list
      .run(db, list.parse({ facets: { noteKind: ["call"] } }).value!)
      .orThrow();

    expect(last().params.toString()).toContain("notes");
  });

  it("have an empty count entry when facet counts are on", async () => {
    const counted = defineListQuery(betterSupabase, "customers", {
      facets: {
        status: "status",
        noteKind: { relation: "notes", column: "kind" },
      },
      sorts: { newest: [{ createdAt: "desc" }, { id: "asc" }] },
      defaultSort: "newest",
      facetCounts: true,
    });

    const { client } = capturingClient((request) => ({
      body: request.params.get("select")?.includes("count()")
        ? [{ status: "active", _count: 2 }]
        : [],
    }));

    const page = await counted
      .run(betterSupabase.connect(client), counted.defaults)
      .orThrow();

    expect(page.facetCounts.noteKind).toEqual({});
    expect(page.facetCounts.status).toMatchObject({ active: 2 });
  });

  it("reject an unknown relation or column", () => {
    expect(() =>
      defineListQuery(betterSupabase, "customers", {
        // @ts-expect-error -- not a relation of customers
        facets: { x: { relation: "nope", column: "kind" } },
        sorts: { newest: { id: "asc" } },
        defaultSort: "newest",
      }),
    ).toThrow(/unknown relation/u);
  });
});

describe("free multi-sort", () => {
  it("parses and round-trips the order parameter", () => {
    const result = list.parse(new URLSearchParams("order=status:desc,name"));

    expect(result.value?.order).toEqual([
      { column: "status", direction: "desc" },
      { column: "name", direction: "asc" },
    ]);
    expect(list.toSearchParams(result.value!).toString()).toBe(
      "order=status%3Adesc%2Cname%3Aasc",
    );
    expect(list.parsers.order?.parse("name:asc")).toEqual([
      { column: "name", direction: "asc" },
    ]);
    expect(list.parsers.order?.parse("name:up")).toBeNull();
  });

  it("appends the primary key as the tiebreak", () => {
    const query = list.parse({
      order: [
        { column: "status", direction: "desc" },
        { column: "name", direction: "asc" },
      ],
    }).value!;

    expect(list.args(query)).toMatchObject({
      orderBy: [{ status: "desc" }, { name: "asc" }, { id: "asc" }],
    });
    expect(list.args(list.defaults)).toMatchObject({
      orderBy: [{ createdAt: "desc" }, { id: "asc" }],
    });
  });

  it("refuses unknown, repeated and too many columns", () => {
    const paths = (input: string): unknown =>
      list
        .parse(new URLSearchParams(`order=${input}`))
        .issues?.map((issue) => issue.path);

    expect(paths("kvk:asc")).toEqual([["order"]]);
    expect(paths("name:asc,name:desc")).toEqual([["order"]]);
    expect(paths("name,status,createdAt,name")).toEqual([["order"]]);
    expect(paths("name:sideways")).toEqual([["order"]]);
  });

  it("is unavailable without freeSort, and the key is reserved with it", () => {
    const plain = defineListQuery(betterSupabase, "customers", {
      sorts: { newest: { id: "asc" } },
      defaultSort: "newest",
    });

    expect(plain.parse(new URLSearchParams("order=name")).issues).toEqual([
      { message: "This list has no free sort", path: ["order"] },
    ]);
    expect(plain.parsers.order).toBeUndefined();
    expect(() =>
      defineListQuery(betterSupabase, "customers", {
        facets: { order: "status" },
        freeSort: freeSort(betterSupabase, "customers", { sortable: ["name"] }),
        sorts: { newest: { id: "asc" } },
        defaultSort: "newest",
      }),
    ).toThrow(/reserved/u);
  });

  it("describes the order parameter in OpenAPI and the JSON schema", () => {
    expect(list.openapi.map((parameter) => parameter.name)).toContain("order");
    expect(list.jsonSchema).toMatchObject({
      properties: { order: { type: "array", maxItems: 3 } },
    });
  });
});
