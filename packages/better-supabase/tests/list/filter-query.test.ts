import { describe, expect, it } from "vitest";

import type { SelectOp } from "../../src/ir/types.ts";
import type { FilterQuery, FilterRule } from "../../src/list/index.ts";
import type { TableMeta } from "../../src/schema/types.ts";

import { compilePostgrest } from "../../src/compile/postgrest.ts";
import { compileSql } from "../../src/compile/sql.ts";
import { compileSqlite } from "../../src/compile/sqlite.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { builderFor } from "../../src/ir/build.ts";
import {
  checkFilterQuery,
  filterFieldsOf,
  filterWhere,
} from "../../src/list/filter-query.ts";
import {
  decodeFilterQuery,
  defineListQuery,
  encodeFilterQuery,
  FILTER_OPERATORS,
} from "../../src/list/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import reui from "./fixtures/reui-operators.json" with { type: "json" };

const betterSupabase = defineSupabase(schema);

function table(key: string): TableMeta {
  const found = schema.meta.tables[key];
  if (!found) throw new Error(`No fixture table ${key}`);
  return found;
}

const customers = table("customers");

const list = defineListQuery(betterSupabase, "customers", {
  search: ["name"],
  facets: { status: "status" },
  filters: {
    name: { type: "text", label: "Name" },
    status: { type: "select" },
    kvk: { type: "text" },
    archivedAt: { type: "date", label: "Archived" },
    createdAt: { type: "date" },
    contact: { type: "relation", column: "primaryContactId" },
  },
  sorts: { name: { name: "asc" } },
  defaultSort: "name",
});

let ids = 0;
function rule(
  path: string,
  operator: string,
  value?: unknown,
  negated?: boolean,
): FilterRule {
  ids += 1;
  return {
    id: `r${String(ids)}`,
    type: "rule",
    path: [path],
    operator,
    value,
    ...(negated === undefined ? {} : { negated }),
  };
}

function group(
  rules: FilterQuery["rules"],
  combinator: "and" | "or" = "and",
): FilterQuery {
  ids += 1;
  return { id: `g${String(ids)}`, type: "group", combinator, rules };
}

function selectOf(where: unknown): SelectOp {
  return {
    kind: "select",
    table: customers,
    selection: { columns: [{ alias: "id", column: "id" }], includes: [] },
    where: builderFor(schema.meta).where(customers, where),
    orderBy: [],
    limit: undefined,
    offset: undefined,
    count: undefined,
    head: false,
    single: undefined,
  };
}

const now = Temporal.Instant.from("2026-10-13T22:30:00Z");

describe("filter operators", () => {
  it("matches ReUI's operator table for every shared type", () => {
    const catalog: Record<string, readonly { value: string }[]> = reui.catalog;
    for (const type of [
      "text",
      "number",
      "select",
      "multiselect",
      "boolean",
      "date",
    ] as const) {
      expect(FILTER_OPERATORS[type]).toEqual(
        (catalog[type] ?? []).map((entry) => ({
          arity: "one",
          ...entry,
        })),
      );
    }
    expect(FILTER_OPERATORS.relation).toEqual(FILTER_OPERATORS.select);
  });
});

describe("filter fields", () => {
  it("rejects fields that do not fit their column", () => {
    expect(() =>
      filterFieldsOf(customers, { x: { type: "text", column: "nope" } }),
    ).toThrow(/column/);
    expect(() =>
      filterFieldsOf(customers, { name: { type: "multiselect" } }),
    ).toThrow(/array column/);
    expect(() => filterFieldsOf(customers, { name: { type: "date" } })).toThrow(
      /date/,
    );
    expect(() =>
      filterFieldsOf(customers, { name: { type: "text", operators: ["gt"] } }),
    ).toThrow(/gt/);
  });

  it("returns ReUI FilterField shapes with labels and enum options", () => {
    const fields = list.filterFields({
      fields: { status: "Status" },
      options: { status: { lead: "Lead" } },
    });
    const byKey = Object.fromEntries(fields.map((field) => [field.id, field]));
    expect(byKey["name"]).toMatchObject({
      id: "name",
      label: "Name",
      type: "text",
    });
    expect(byKey["status"]).toMatchObject({
      label: "Status",
      type: "select",
      options: [
        { value: "lead", label: "Lead" },
        { value: "active", label: "active" },
        { value: "archived", label: "archived" },
      ],
    });
    expect(byKey["contact"]).toMatchObject({
      type: "select",
      column: "primary_contact_id",
    });
    expect(byKey["archivedAt"]?.type).toBeUndefined();
    expect(byKey["archivedAt"]?.operators?.map((entry) => entry.value)).toEqual(
      FILTER_OPERATORS.date.map((entry) => entry.value),
    );
  });
});

describe("parsing filter trees", () => {
  it("checks operators against field types and drops unfinished rules", () => {
    const tree = group([
      rule("name", "contains", "acme"),
      rule("name", "", undefined),
      group([], "or"),
      group([rule("status", "is_any_of", ["lead", "active"])], "or"),
    ]);
    const result = list.parse({ filter: tree });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.filter?.rules).toHaveLength(2);

    expect(
      list.parse({ filter: group([rule("name", "gt", "a")]) }),
    ).toMatchObject({
      ok: false,
      issues: [{ path: ["filter", "rules", 0, "operator"] }],
    });
    expect(
      list.parse({ filter: group([rule("status", "is", "deleted")]) }).ok,
    ).toBe(false);
    expect(list.parse({ filter: group([rule("nope", "is", "x")]) }).ok).toBe(
      false,
    );
    expect(
      list.parse({ filter: rule("name", "contains", "a") as never }),
    ).toMatchObject({ ok: false, issues: [{ path: ["filter"] }] });
    expect(
      list.parse({ filter: group([rule("status", "is_any_of", "lead")]) }).ok,
    ).toBe(false);
  });

  it("caps depth and rule count", () => {
    let deep: FilterQuery = group([rule("name", "contains", "a")]);
    for (let level = 0; level < 4; level += 1) deep = group([deep]);
    expect(list.parse({ filter: deep }).ok).toBe(false);

    const wide = group(
      Array.from({ length: 51 }, () => rule("name", "contains", "a")),
    );
    expect(list.parse({ filter: wide }).ok).toBe(false);

    const issues: { message: string }[] = [];
    checkFilterQuery(
      group([rule("name", "contains", "a"), rule("name", "contains", "b")]),
      filterFieldsOf(customers, { name: { type: "text" } }),
      { maxDepth: 4, maxRules: 1, maxValueLength: 200, maxValues: 50 },
      issues,
    );
    expect(issues).not.toHaveLength(0);
  });

  it("round-trips through the URL as base64url JSON", () => {
    const tree = group([
      rule("name", "contains", "café"),
      rule("archivedAt", "is_after", { relative: { unit: "day", offset: -7 } }),
    ]);
    const parsed = list.parse({ filter: tree });
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) return;
    const params = list.toSearchParams(parsed.value);
    const encoded = params.get("filter") ?? "";
    expect(encoded).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(decodeFilterQuery(encoded)).toEqual(tree);
    expect(list.parse(params)).toEqual(parsed);

    expect(list.parsers.filter?.parse(encodeFilterQuery(tree))).toEqual(tree);
    expect(list.parsers.filter?.parse("%%%")).toBeNull();
    expect(list.parse(new URLSearchParams("filter=%%%")).ok).toBe(false);
  });

  it("rejects an unknown time zone", () => {
    expect(list.parse({}, { timeZone: "Mars/Olympus" })).toMatchObject({
      ok: false,
      issues: [{ path: ["timeZone"] }],
    });
    expect(list.parse({}, { timeZone: "Europe/Amsterdam" })).toMatchObject({
      ok: true,
      value: { timeZone: "Europe/Amsterdam" },
    });
  });

  it("rejects a filter on a list without filters", () => {
    const plain = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
    });
    expect(
      plain.parse({ filter: group([rule("name", "contains", "a")]) }).ok,
    ).toBe(false);
    expect(plain.openapi.some((param) => param.name === "filter")).toBe(false);
  });
});

describe("compiling filter trees", () => {
  const fields = list.filters;

  it("compiles operators, negation and nullable inverses to where input", () => {
    const where = filterWhere(
      group([
        rule("name", "contains", "acme"),
        rule("kvk", "not_contains", "99"),
        rule("status", "is", "lead", true),
        group(
          [rule("kvk", "empty"), rule("contact", "is_none_of", ["c1"])],
          "or",
        ),
      ]),
      fields,
    );
    expect(where).toEqual({
      AND: [
        { name: { contains: "acme" } },
        {
          OR: [{ NOT: { kvk: { contains: "99" } } }, { kvk: { isNull: true } }],
        },
        { NOT: { status: { eq: "lead" } } },
        {
          OR: [
            { OR: [{ kvk: { isNull: true } }, { kvk: { eq: "" } }] },
            {
              OR: [
                { NOT: { primaryContactId: { in: ["c1"] } } },
                { primaryContactId: { isNull: true } },
              ],
            },
          ],
        },
      ],
    });
  });

  it("resolves relative dates in the request time zone", () => {
    const tree = group([
      rule("createdAt", "is", { relative: { unit: "day", offset: -1 } }),
    ]);
    expect(
      filterWhere(tree, fields, { now, timeZone: "Europe/Amsterdam" }),
    ).toEqual({
      createdAt: { gte: "2026-10-12T22:00:00Z", lt: "2026-10-13T22:00:00Z" },
    });
    expect(filterWhere(tree, fields, { now })).toEqual({
      createdAt: { gte: "2026-10-12T00:00:00Z", lt: "2026-10-13T00:00:00Z" },
    });
    const between = filterWhere(
      group([
        rule("createdAt", "between", [
          { date: "2026-01-01" },
          { date: "2026-01-31" },
        ]),
      ]),
      fields,
      { now },
    );
    expect(between).toEqual({
      createdAt: { gte: "2026-01-01T00:00:00Z", lt: "2026-02-01T00:00:00Z" },
    });
  });

  it("keeps relative dates relative until args runs", () => {
    const parsed = list.parse(
      {
        filter: group([
          rule("archivedAt", "is_before", {
            relative: { unit: "week", offset: 0 },
          }),
        ]),
      },
      { timeZone: "UTC" },
    );
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) return;
    expect(list.args(parsed.value, { now }).where).toEqual({
      archivedAt: { lt: "2026-10-13T00:00:00Z" },
    });
  });

  it("compiles to PostgREST, SQL and SQLite through the IR", () => {
    const where = filterWhere(
      group(
        [
          rule("name", "starts_with", "Ac"),
          rule("status", "is_any_of", ["lead", "active"]),
        ],
        "or",
      ),
      fields,
    );
    const op = selectOf(where);

    const postgrest = compilePostgrest(op);
    expect(JSON.stringify(postgrest)).toMatch(/name\.ilike\.\\"Ac%\\"/);
    expect(JSON.stringify(postgrest)).toMatch(/status\.in\.\(lead,active\)/);

    const sql = compileSql(op);
    expect(sql.rows?.text).toMatch(/"name" ilike/);
    expect(sql.rows?.text).toMatch(/ or /);

    const sqlite = compileSqlite(op);
    expect(sqlite.kind === "select" ? sqlite.rows?.text : "").toMatch(
      /"name" like \? escape '\\' or t0\."status" in \(\?, \?\)/,
    );
  });

  it("supports multiselect on array columns", () => {
    const tagged: TableMeta = {
      ...customers,
      columns: {
        ...customers.columns,
        labels: {
          db: "labels",
          type: "text",
          nullable: false,
          hasDefault: false,
          array: true,
        },
      },
    };
    const multi = filterFieldsOf(tagged, { labels: { type: "multiselect" } });
    expect(
      filterWhere(
        group([
          rule("labels", "has_all_of", ["a", "b"]),
          rule("labels", "has_none_of", ["c"]),
        ]),
        multi,
      ),
    ).toEqual({
      AND: [
        { labels: { hasEvery: ["a", "b"] } },
        { NOT: { labels: { hasSome: ["c"] } } },
      ],
    });
  });
});

describe("describing the filter parameter", () => {
  it("adds an OpenAPI parameter and a JSON Schema property", () => {
    expect(list.openapi.find((param) => param.name === "filter")).toMatchObject(
      { in: "query", schema: { type: "string" } },
    );
    const json = list.jsonSchema as {
      properties: Record<string, unknown>;
      $defs: Record<string, unknown>;
    };
    expect(json.properties["filter"]).toEqual({ $ref: "#/$defs/filterGroup" });
    expect(Object.keys(json.$defs)).toEqual(
      expect.arrayContaining(["filterGroup", "filterRule"]),
    );
  });
});
