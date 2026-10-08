import { describe, expect, it } from "vitest";

import type { PlanFilter, PostgrestPlan } from "../../src/compile/postgrest.ts";
import type {
  Condition,
  Include,
  Operation,
  SelectOp,
  Selection,
} from "../../src/ir/types.ts";
import type { RelationMeta, TableMeta } from "../../src/schema/types.ts";

import {
  compilePostgrest,
  supportsMaxAffected,
} from "../../src/compile/postgrest.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { DbException } from "../../src/core/errors.ts";
import { capturingClient, query } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

function table(key: string): TableMeta {
  const found = schema.meta.tables[key];
  if (!found) throw new Error(`No fixture table ${key}`);
  return found;
}

function relation(from: TableMeta, name: string): RelationMeta {
  const found = from.relations[name];
  if (!found) throw new Error(`No relation ${name} on ${from.key}`);
  return found;
}

const customers = table("customers");
const notes = table("notes");
const organizations = table("organizations");
const notesOf = relation(customers, "notes");

const idOnly: Selection = {
  columns: [{ alias: "id", column: "id" }],
  includes: [],
};

function select(overrides: Partial<SelectOp> = {}): SelectOp {
  return {
    kind: "select",
    table: customers,
    selection: idOnly,
    where: undefined,
    orderBy: [],
    limit: undefined,
    offset: undefined,
    count: undefined,
    head: false,
    single: undefined,
    ...overrides,
  };
}

function include(overrides: Partial<Include> = {}): Include {
  return {
    alias: "notes",
    relation: notesOf,
    target: notes,
    selection: idOnly,
    where: undefined,
    orderBy: [],
    limit: undefined,
    required: false,
    ...overrides,
  };
}

const col = (
  column: string,
  op: Extract<Condition, { kind: "column" }>["op"],
  value: unknown,
): Condition => ({ kind: "column", column, op, value });

const jsonCol = (
  column: string,
  op: "contains" | "containedBy",
  value: unknown,
): Condition => ({ kind: "column", column, op, value, json: true });

const pathCol = (
  column: string,
  op: Extract<Condition, { kind: "column" }>["op"],
  value: unknown,
  path: readonly string[],
): Condition => ({ kind: "column", column, op, value, path });

const onNotes = (
  quantifier: "some" | "none" | "every",
  where: Condition | undefined,
): Condition => ({
  kind: "relation",
  name: "notes",
  relation: notesOf,
  target: notes,
  quantifier,
  where,
});

const filter = (path: string, operator: string, value: string): PlanFilter => ({
  kind: "filter",
  path,
  operator,
  value,
});

const orFilter = (
  expression: string,
  referencedTable?: string,
): PlanFilter => ({
  kind: "or",
  expression,
  referencedTable,
});

function invalid(fn: () => unknown): string {
  try {
    fn();
  } catch (error) {
    if (error instanceof DbException && error.kind === "invalid_request")
      return error.message;
    throw error;
  }
  throw new Error("Expected an invalid_request DbException");
}

const plan = (op: Operation): PostgrestPlan => compilePostgrest(op);
const EMBED = "notes!notes_customer_id_fkey";

describe("compilePostgrest filters", () => {
  it.each<[string, Condition, PlanFilter]>([
    ["eq on a string", col("name", "eq", "Acme"), filter("name", "eq", "Acme")],
    ["neq on a number", col("name", "neq", 3), filter("name", "neq", "3")],
    ["gt on a bigint", col("id", "gt", 10n), filter("id", "gt", "10")],
    ["gte on a boolean", col("id", "gte", true), filter("id", "gte", "true")],
    [
      "lt on an Instant",
      col("created_at", "lt", Temporal.Instant.from("2026-01-02T03:04:05Z")),
      filter("created_at", "lt", "2026-01-02T03:04:05Z"),
    ],
    [
      "lte on an object",
      col("id", "lte", { a: 1 }),
      filter("id", "lte", '{"a":1}'),
    ],
    ["like", col("name", "like", "A%"), filter("name", "like", "A%")],
    ["ilike", col("name", "ilike", "%a%"), filter("name", "ilike", "%a%")],
    ["match", col("name", "match", "^A.+$"), filter("name", "match", "^A.+$")],
    ["imatch", col("name", "imatch", "^a"), filter("name", "imatch", "^a")],
    [
      "in with quoting",
      col("name", "in", ["a", 'q"x', "back\\slash", null]),
      filter("name", "in", '(a,"q\\"x","back\\\\slash","null")'),
    ],
    [
      "in with bare values",
      col("id", "in", [
        "6f1c2b9e-0d4a-4f7e-9b1a-2c3d4e5f6a7b",
        12,
        1.5,
        true,
        "2026-01-02T03:04:05.123Z",
        "a@b.test",
        "NULL",
        "two words",
        "a,b",
        "f(x)",
        "",
      ]),
      filter(
        "id",
        "in",
        '(6f1c2b9e-0d4a-4f7e-9b1a-2c3d4e5f6a7b,12,1.5,true,2026-01-02T03:04:05.123Z,a@b.test,"NULL","two words","a,b","f(x)","")',
      ),
    ],
    ["is null", col("kvk", "is", null), filter("kvk", "is", "null")],
    ["is false", col("kvk", "is", false), filter("kvk", "is", "false")],
    [
      "contains an array",
      col("tags", "contains", ["a", "b"]),
      filter("tags", "cs", '{"a","b"}'),
    ],
    [
      "contains json",
      col("metadata", "contains", { plan: "pro" }),
      filter("metadata", "cs", '{"plan":"pro"}'),
    ],
    [
      "contains a json array",
      jsonCol("parts", "contains", [{ type: "x" }]),
      filter("parts", "cs", '[{"type":"x"}]'),
    ],
    [
      "containedBy a json array",
      jsonCol("parts", "containedBy", ["a", "b"]),
      filter("parts", "cd", '["a","b"]'),
    ],
    [
      "a json path",
      pathCol("metadata", "eq", "u1", ["authz", "subject", "id"]),
      filter("metadata->authz->subject->>id", "eq", "u1"),
    ],
    [
      "a json path null check",
      { kind: "not", item: pathCol("metadata", "is", null, ["authz"]) },
      filter("metadata->>authz", "not.is", "null"),
    ],
    [
      "a json path in list",
      pathCol("metadata", "in", ["a", "b c"], ["tier"]),
      filter("metadata->>tier", "in", '(a,"b c")'),
    ],
    [
      "containedBy",
      col("tags", "containedBy", ["a"]),
      filter("tags", "cd", '{"a"}'),
    ],
    ["overlaps", col("tags", "overlaps", ["a"]), filter("tags", "ov", '{"a"}')],
    [
      "fts",
      col("name", "fts", "acme corp"),
      filter("name", "wfts", "acme corp"),
    ],
    [
      "fts with a config",
      {
        kind: "column",
        column: "name",
        op: "fts",
        value: "acme",
        config: "dutch",
      },
      filter("name", "wfts(dutch)", "acme"),
    ],
    [
      "a negated column",
      { kind: "not", item: col("name", "eq", "Acme") },
      filter("name", "not.eq", "Acme"),
    ],
  ])("%s", (_name, where, expected) => {
    expect(plan(select({ where })).filters).toEqual([expected]);
  });

  it("splits a top-level and into separate filters", () => {
    expect(
      plan(
        select({
          where: {
            kind: "and",
            items: [col("name", "eq", "A"), col("kvk", "is", null)],
          },
        }),
      ).filters,
    ).toEqual([filter("name", "eq", "A"), filter("kvk", "is", "null")]);
  });

  it.each<[string, Condition, string]>([
    [
      "an or of columns",
      { kind: "or", items: [col("name", "eq", "A"), col("name", "eq", "B,C")] },
      'name.eq."A",name.eq."B,C"',
    ],
    [
      "an or with json paths",
      {
        kind: "or",
        items: [
          pathCol("metadata", "eq", "a.b", ["owner", "id"]),
          { kind: "not", item: pathCol("metadata", "is", null, ["owner"]) },
        ],
      },
      'metadata->owner->>id.eq."a.b",metadata->>owner.not.is.null',
    ],
    [
      "an or with a json array",
      {
        kind: "or",
        items: [
          jsonCol("parts", "contains", [{ type: "x" }]),
          col("name", "eq", "A"),
        ],
      },
      'parts.cs."[{\\"type\\":\\"x\\"}]",name.eq."A"',
    ],
    [
      "an or with nested logic",
      {
        kind: "or",
        items: [
          {
            kind: "and",
            items: [col("status", "in", ["lead"]), col("kvk", "is", null)],
          },
          { kind: "not", item: col("name", "like", "x%") },
          {
            kind: "not",
            item: {
              kind: "and",
              items: [col("id", "eq", 1), col("id", "eq", 2)],
            },
          },
          col("metadata", "contains", { a: 1 }),
          col("tags", "overlaps", ["t"]),
        ],
      },
      'and(status.in.(lead),kvk.is.null),name.not.like."x%",not.and(id.eq."1",id.eq."2"),metadata.cs."{\\"a\\":1}",tags.ov.{"t"}',
    ],
    [
      "an or with array elements that hold braces",
      {
        kind: "or",
        items: [
          col("tags", "contains", ["a}", "b"]),
          col("tags", "overlaps", ["{c"]),
        ],
      },
      'tags.cs."{\\"a}\\",\\"b\\"}",tags.ov."{\\"{c\\"}"',
    ],
  ])("renders %s as a logic tree", (_name, where, expression) => {
    expect(plan(select({ where })).filters).toEqual([orFilter(expression)]);
  });

  it("wraps a negated and in an or filter", () => {
    expect(
      plan(
        select({
          where: {
            kind: "not",
            item: {
              kind: "and",
              items: [col("name", "eq", "A"), col("kvk", "is", null)],
            },
          },
        }),
      ).filters,
    ).toEqual([orFilter('not.and(name.eq."A",kvk.is.null)')]);
  });

  it.each<[string, Condition, string]>([
    ["in without an array", col("status", "in", "lead"), '"in" needs an array'],
    [
      "is with a string",
      col("kvk", "is", "x"),
      '"is" needs null, true or false',
    ],
  ])("rejects %s", (_name, where, message) => {
    expect(invalid(() => plan(select({ where })))).toBe(message);
  });

  it("marks a filter that can never match", () => {
    expect(plan(select({ where: col("id", "in", []) }))).toMatchObject({
      never: true,
      filters: [],
      select: "id",
    });
  });
});

describe("compilePostgrest relation filters", () => {
  it.each<[string, Condition, string, PlanFilter[]]>([
    [
      "some",
      onNotes("some", col("body", "eq", "x")),
      `id,_bs1:${EMBED}!inner()`,
      [filter("_bs1.body", "eq", "x")],
    ],
    [
      "none",
      onNotes("none", col("body", "eq", "x")),
      `id,_bs1:${EMBED}()`,
      [filter("_bs1.body", "eq", "x"), filter("_bs1", "is", "null")],
    ],
    [
      "none without a filter",
      onNotes("none", undefined),
      `id,_bs1:${EMBED}()`,
      [filter("_bs1", "is", "null")],
    ],
    [
      "every",
      onNotes("every", col("body", "eq", "x")),
      `id,_bs1:${EMBED}()`,
      [filter("_bs1.body", "not.eq", "x"), filter("_bs1", "is", "null")],
    ],
    [
      "not some",
      { kind: "not", item: onNotes("some", col("body", "eq", "x")) },
      `id,_bs1:${EMBED}()`,
      [filter("_bs1.body", "eq", "x"), filter("_bs1", "is", "null")],
    ],
    [
      "not none",
      { kind: "not", item: onNotes("none", col("body", "eq", "x")) },
      `id,_bs1:${EMBED}!inner()`,
      [filter("_bs1.body", "eq", "x")],
    ],
    [
      "not every",
      { kind: "not", item: onNotes("every", col("body", "eq", "x")) },
      `id,_bs1:${EMBED}!inner()`,
      [filter("_bs1.body", "not.eq", "x")],
    ],
  ])("%s", (_name, where, selected, filters) => {
    const result = plan(select({ where }));
    expect(result.select).toBe(selected);
    expect(result.filters).toEqual(filters);
  });

  it("nests a relation filter inside a relation filter", () => {
    const organizationOf = relation(notes, "organization");
    const where = onNotes("some", {
      kind: "relation",
      name: "organization",
      relation: organizationOf,
      target: organizations,
      quantifier: "some",
      where: col("slug", "eq", "acme"),
    });
    const result = plan(select({ where }));
    expect(result.select).toBe(
      `id,_bs1:${EMBED}!inner(_bs2:organizations!notes_organization_id_fkey!inner())`,
    );
    expect(result.filters).toEqual([filter("_bs1._bs2.slug", "eq", "acme")]);
  });

  it.each<[string, Condition, string, PlanFilter[]]>([
    [
      "some",
      onNotes("some", col("body", "eq", "x")),
      "_bs1.not.is.null",
      [filter("_bs1.body", "eq", "x")],
    ],
    ["none", onNotes("none", undefined), "_bs1.is.null", []],
    [
      "every",
      onNotes("every", col("body", "eq", "x")),
      "_bs1.is.null",
      [filter("_bs1.body", "not.eq", "x")],
    ],
    [
      "not some",
      { kind: "not", item: onNotes("some", col("body", "eq", "x")) },
      "_bs1.is.null",
      [filter("_bs1.body", "eq", "x")],
    ],
  ])(
    "puts the null check of %s in an or",
    (_name, relationTerm, term, filters) => {
      const result = plan(
        select({
          where: { kind: "or", items: [relationTerm, col("name", "eq", "A")] },
        }),
      );
      expect(result.select).toBe(`id,_bs1:${EMBED}()`);
      expect(result.filters).toEqual([
        ...filters,
        orFilter(`${term},name.eq."A"`),
      ]);
    },
  );

  it("resolves relation paths in an or inside an include", () => {
    const where: Condition = {
      kind: "or",
      items: [
        {
          kind: "relation",
          name: "organization",
          relation: relation(notes, "organization"),
          target: organizations,
          quantifier: "some",
          where: col("slug", "eq", "acme"),
        },
        col("body", "eq", "x"),
      ],
    };
    const result = plan(
      select({ selection: { columns: [], includes: [include({ where })] } }),
    );
    expect(result.select).toBe(
      `notes:${EMBED}(id,_bs1:organizations!notes_organization_id_fkey())`,
    );
    expect(result.filters).toEqual([
      filter("notes._bs1.slug", "eq", "acme"),
      orFilter('_bs1.not.is.null,body.eq."x"', "notes"),
    ]);
  });
});

describe("compilePostgrest selections and includes", () => {
  it.each<[string, Selection, string]>([
    [
      "renamed and cast columns",
      {
        columns: [
          { alias: "fullName", column: "full_name" },
          { alias: "id", column: "id", cast: "text" },
          { alias: "total", column: "amount", cast: "text" },
        ],
        includes: [],
      },
      "fullName:full_name,id::text,total:amount::text",
    ],
    ["no columns", { columns: [], includes: [] }, "*"],
    [
      "an aggregate",
      {
        columns: [{ alias: "status", column: "status" }],
        includes: [],
        aggregate: {
          count: true,
          measures: [
            {
              fn: "sum",
              key: "_sum_id",
              alias: "id",
              column: "id",
              cast: "text",
            },
          ],
        },
      },
      "status,_count:count(),_sum_id:id.sum()::text",
    ],
    [
      "an aggregate without count",
      {
        columns: [],
        includes: [],
        aggregate: {
          count: false,
          measures: [
            { fn: "max", key: "_max_name", alias: "name", column: "name" },
          ],
        },
      },
      "_max_name:name.max()",
    ],
    [
      "count, aggregate, required and nested includes",
      {
        columns: [{ alias: "id", column: "id" }],
        includes: [
          include({
            alias: "_count_notes",
            count: "notes",
            selection: { columns: [], includes: [] },
          }),
          include({
            alias: "_sum_notes",
            selection: {
              columns: [],
              includes: [],
              aggregate: {
                count: false,
                measures: [{ fn: "sum", key: "id", alias: "id", column: "id" }],
              },
            },
            aggregate: { fn: "sum", name: "notes" },
          }),
          include({
            required: true,
            selection: {
              columns: [{ alias: "id", column: "id" }],
              includes: [
                include({
                  alias: "organization",
                  relation: relation(notes, "organization"),
                  target: organizations,
                }),
              ],
            },
          }),
        ],
      },
      `id,_count_notes:${EMBED}(count),_sum_notes:${EMBED}(id:id.sum()),notes:${EMBED}!inner(id,organization:organizations!notes_organization_id_fkey(id))`,
    ],
  ])("renders %s", (_name, selection, expected) => {
    expect(plan(select({ selection })).select).toBe(expected);
  });

  it("scopes include filters, order and limit to the embed path", () => {
    const nested = include({
      alias: "organization",
      relation: relation(notes, "organization"),
      target: organizations,
      where: col("slug", "eq", "acme"),
    });
    const result = plan(
      select({
        selection: {
          columns: [],
          includes: [
            include({
              selection: {
                columns: [{ alias: "id", column: "id" }],
                includes: [nested],
              },
              where: col("body", "eq", "x"),
              orderBy: [
                { column: "created_at", direction: "desc", nulls: "first" },
                { column: "id", direction: "asc" },
              ],
              limit: 5,
            }),
          ],
        },
      }),
    );
    expect(result.filters).toEqual([
      filter("notes.organization.slug", "eq", "acme"),
      filter("notes.body", "eq", "x"),
    ]);
    expect(result.orders).toEqual([
      {
        column: "created_at",
        ascending: false,
        nullsFirst: true,
        referencedTable: "notes",
      },
      {
        column: "id",
        ascending: true,
        nullsFirst: undefined,
        referencedTable: "notes",
      },
    ]);
    expect(result.limits).toEqual([{ count: 5, referencedTable: "notes" }]);
  });

  it("empties an include whose filter never matches", () => {
    const result = plan(
      select({
        selection: {
          columns: [],
          includes: [include({ where: col("id", "in", []) })],
        },
      }),
    );
    expect(result.filters).toEqual([
      filter("notes.id", "is", "null"),
      filter("notes.id", "not.is", "null"),
    ]);
    expect(result.never).toBe(false);
  });

  it("rejects an impossible include filter on a table without a primary key", () => {
    const keyless: TableMeta = { ...notes, primaryKey: [] };
    expect(
      invalid(() =>
        plan(
          select({
            selection: {
              columns: [],
              includes: [
                include({ target: keyless, where: col("id", "in", []) }),
              ],
            },
          }),
        ),
      ),
    ).toBe('Cannot filter "notes" to nothing');
  });
});

describe("compilePostgrest paging", () => {
  it.each<[string, Partial<SelectOp>, Pick<PostgrestPlan, "limits" | "range">]>(
    [
      ["no paging", {}, { limits: [], range: undefined }],
      [
        "a limit",
        { limit: 10 },
        {
          limits: [{ count: 10, referencedTable: undefined }],
          range: undefined,
        },
      ],
      [
        "an offset and a limit",
        { limit: 10, offset: 20 },
        { limits: [], range: { from: 20, to: 29 } },
      ],
      [
        "an offset",
        { offset: 5 },
        { limits: [], range: { from: 5, to: Number.MAX_SAFE_INTEGER } },
      ],
    ],
  )("%s", (_name, overrides, expected) => {
    expect(plan(select(overrides))).toMatchObject(expected);
  });

  it("orders top-level columns", () => {
    expect(
      plan(
        select({
          orderBy: [{ column: "name", direction: "desc", nulls: "last" }],
        }),
      ).orders,
    ).toEqual([
      {
        column: "name",
        ascending: false,
        nullsFirst: false,
        referencedTable: undefined,
      },
    ]);
  });

  it("orders groups by the row count", () => {
    expect(
      plan(
        select({
          orderBy: [
            { column: "*", direction: "desc", aggregate: "count" },
            { column: "status", direction: "asc" },
          ],
        }),
      ).orders,
    ).toEqual([
      {
        column: "count",
        ascending: false,
        nullsFirst: undefined,
        referencedTable: undefined,
      },
      {
        column: "status",
        ascending: true,
        nullsFirst: undefined,
        referencedTable: undefined,
      },
    ]);
  });

  it("rejects a count order on a table with a count column", () => {
    const tallies: TableMeta = {
      ...customers,
      columns: {
        ...customers.columns,
        total: {
          db: "count",
          type: "int4",
          nullable: false,
          hasDefault: false,
        },
      },
    };
    expect(
      invalid(() =>
        plan(
          select({
            table: tallies,
            orderBy: [{ column: "*", direction: "desc", aggregate: "count" }],
          }),
        ),
      ),
    ).toBe(
      'PostgREST can\'t sort "customers" by _count because the table has a column named "count"; sort by a groupBy column or use the postgres adapter',
    );
  });

  it("rejects a measure order", () => {
    expect(
      invalid(() =>
        plan(
          select({
            orderBy: [{ column: "id", direction: "desc", aggregate: "sum" }],
          }),
        ),
      ),
    ).toBe(
      'PostgREST can\'t sort "customers" by _sum; sort by _count or a groupBy column, or use the postgres adapter',
    );
  });
});

describe("compilePostgrest mutations", () => {
  it("selects nothing for an insert without returning", () => {
    expect(
      plan({
        kind: "insert",
        table: customers,
        rows: [{ name: "A" }],
        returning: undefined,
        onConflict: undefined,
        defaultToNull: false,
      }),
    ).toEqual({
      select: undefined,
      filters: [],
      orders: [],
      limits: [],
      range: undefined,
      never: false,
    });
  });

  it("selects the returning columns of an insert", () => {
    expect(
      plan({
        kind: "insert",
        table: customers,
        rows: [{ name: "A" }],
        returning: idOnly,
        onConflict: undefined,
        defaultToNull: false,
      }).select,
    ).toBe("id");
  });

  it("filters an update and a delete by column", () => {
    expect(
      plan({
        kind: "update",
        table: customers,
        set: { name: "B" },
        where: col("id", "eq", "c1"),
        returning: idOnly,
      }),
    ).toMatchObject({
      select: "id",
      filters: [filter("id", "eq", "c1")],
      never: false,
    });
    expect(
      plan({
        kind: "delete",
        table: customers,
        where: col("id", "in", []),
        returning: undefined,
      }),
    ).toMatchObject({ select: undefined, never: true });
  });

  it("carries maxAffected on updates and deletes", () => {
    expect(
      plan({
        kind: "update",
        table: customers,
        set: { name: "B" },
        where: col("status", "eq", "lead"),
        returning: undefined,
        maxAffected: 10,
      }).maxAffected,
    ).toBe(10);
    const remove: Operation = {
      kind: "delete",
      table: customers,
      where: undefined,
      returning: undefined,
      maxAffected: 0,
    };
    expect(plan(remove).maxAffected).toBe(0);
    expect(
      compilePostgrest(remove, { postgrestVersion: "13.0.4" }).maxAffected,
    ).toBe(0);
    const { maxAffected: _, ...unbounded } = remove;
    expect(plan(unbounded)).not.toHaveProperty("maxAffected");
  });

  it("rejects an invalid maxAffected and PostgREST before 13", () => {
    const remove: Operation = {
      kind: "delete",
      table: customers,
      where: undefined,
      returning: undefined,
      maxAffected: -1,
    };
    expect(invalid(() => plan(remove))).toBe(
      '"maxAffected" must be a non-negative integer, got -1',
    );
    expect(
      invalid(() =>
        compilePostgrest(
          { ...remove, maxAffected: 5 },
          { postgrestVersion: "12.2.3" },
        ),
      ),
    ).toMatch(/PostgREST 13/);
  });

  it.each([
    [undefined, true],
    ["13", true],
    ["14.1", true],
    ["12.2.3", false],
    ["v11", false],
    ["unknown", true],
  ])("supportsMaxAffected(%j) is %s", (version, expected) => {
    expect(supportsMaxAffected(version)).toBe(expected);
  });

  it.each(["update", "delete"] as const)(
    "rejects a relation filter in %s",
    (kind) => {
      const where = onNotes("some", col("body", "eq", "x"));
      const op: Operation =
        kind === "update"
          ? {
              kind,
              table: customers,
              set: { name: "B" },
              where,
              returning: undefined,
            }
          : { kind, table: customers, where, returning: undefined };
      expect(invalid(() => plan(op))).toBe(
        `Relation filters are not supported in ${kind} on PostgREST; filter by key instead`,
      );
    },
  );
});

describe("compilePostgrest through supabase-js", () => {
  it("sends the plan as PostgREST query parameters", async () => {
    const { client, last } = capturingClient();
    const db = defineSupabase(schema).connect(client);
    await db.customers
      .findMany({
        select: ["id"],
        where: {
          OR: [{ name: { startsWith: "A" } }, { kvk: null }],
          notes: { none: { body: "spam" } },
        },
        orderBy: { name: { direction: "desc", nulls: "last" } },
        limit: 10,
        offset: 20,
      })
      .orThrow();
    expect(query(last())).toEqual([
      `select=id,_bs1:${EMBED}()`,
      'or=(name.like."A%",kvk.is.null)',
      "_bs1.body=eq.spam",
      "_bs1=is.null",
      "order=name.desc.nullslast",
      "offset=20",
      "limit=10",
    ]);
  });

  it("sends Dates as ISO text, null in a list as is.null and * literally", async () => {
    const { client, last } = capturingClient();
    const db = defineSupabase(schema).connect(client);
    await db.customers
      .findMany({
        select: ["id"],
        where: {
          name: { contains: "50*off" },
          kvk: { in: ["1", null] as never, notIn: [null] as never },
          createdAt: { gte: new Date("2026-01-02T03:04:05Z") as never },
        },
      })
      .orThrow();
    expect(query(last())).toEqual([
      "select=id",
      "name=imatch.^.*50\\*off.*$",
      "or=(kvk.in.(1),kvk.is.null)",
      "kvk=not.is.null",
      "created_at=gte.2026-01-02T03:04:05.000Z",
      "order=id.asc",
    ]);
    expect(
      await db.customers.findMany({
        where: { createdAt: { gte: new Date("nope") as never } },
      }),
    ).toMatchObject({ error: { kind: "invalid_value" } });
  });
});
