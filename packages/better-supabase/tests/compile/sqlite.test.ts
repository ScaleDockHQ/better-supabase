import { describe, expect, it } from "vitest";

import type { Condition, SelectOp } from "../../src/ir/types.ts";
import type { TableMeta } from "../../src/schema/types.ts";

import {
  compileSqlite,
  keyPages,
  likeToGlob,
  quoteSqliteIdent,
  sqliteValue,
  type SqlitePlan,
} from "../../src/compile/sqlite.ts";
import { DbException } from "../../src/core/errors.ts";
import { sqliteCompiler } from "../../src/powersync/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

function table(key: string): TableMeta {
  const found = schema.meta.tables[key];
  if (!found) throw new Error(`No fixture table ${key}`);
  return found;
}

const customers = table("customers");
const notes = table("notes");

function select(overrides: Partial<SelectOp> = {}): SelectOp {
  return {
    kind: "select",
    table: customers,
    selection: { columns: [{ alias: "id", column: "id" }], includes: [] },
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

const col = (
  column: string,
  op: Extract<Condition, { kind: "column" }>["op"],
  value: unknown,
): Condition => ({ kind: "column", column, op, value });

function selectPlan(plan: SqlitePlan) {
  if (plan.kind !== "select")
    throw new Error(`expected select, got ${plan.kind}`);
  return plan;
}

function unsupportedOf(run: () => unknown): unknown {
  try {
    run();
  } catch (cause) {
    if (cause instanceof DbException) return cause.error;
    throw cause;
  }
  throw new Error("expected an unsupported error");
}

describe("compileSqlite", () => {
  it("compiles a select with filters, Postgres null ordering and paging", () => {
    const plan = selectPlan(
      sqliteCompiler.compile(
        select({
          where: {
            kind: "and",
            items: [
              col("name", "ilike", "%a\\%%"),
              col("kvk", "like", "10_*"),
              col("status", "in", ["lead", "active"]),
              { kind: "not", item: col("archived_at", "is", null) },
              col("created_at", "gte", "2026-01-01T00:00:00Z"),
            ],
          },
          orderBy: [
            { column: "name", direction: "asc" },
            { column: "created_at", direction: "desc" },
          ],
          limit: 10,
          offset: 20,
          count: "exact",
        }),
      ),
    );
    expect(plan.rows?.text).toBe(
      'select t0."id" as "id" from "customers" as t0 where (t0."name" like ? escape \'\\\' and t0."kvk" glob ? and t0."status" in (?, ?) and not t0."archived_at" is null and julianday(t0."created_at") >= julianday(?)) order by t0."name" collate nocase asc nulls last, julianday(t0."created_at") desc nulls first limit 10 offset 20',
    );
    expect(plan.rows?.params).toEqual([
      "%a\\%%",
      "10?[*]",
      "lead",
      "active",
      "2026-01-01T00:00:00Z",
    ]);
    expect(plan.count?.text).toBe(
      'select count(*) as count from "customers" as t0 where (t0."name" like ? escape \'\\\' and t0."kvk" glob ? and t0."status" in (?, ?) and not t0."archived_at" is null and julianday(t0."created_at") >= julianday(?))',
    );
  });

  it("compiles head counts, offsets without a limit and never-matching filters", () => {
    expect(
      selectPlan(compileSqlite(select({ head: true, count: "exact" }))),
    ).toMatchObject({ rows: undefined, columns: [] });
    expect(selectPlan(compileSqlite(select({ offset: 5 }))).rows?.text).toMatch(
      /limit -1 offset 5$/,
    );
    expect(compileSqlite(select({ where: { kind: "or", items: [] } }))).toEqual(
      { kind: "never" },
    );
    expect(compileSqlite(select({ where: col("status", "in", []) }))).toEqual({
      kind: "never",
    });
    expect(
      selectPlan(
        compileSqlite(
          select({
            where: {
              kind: "or",
              items: [col("status", "in", []), col("name", "eq", "A")],
            },
          }),
        ),
      ).rows?.text,
    ).toContain('where t0."name" = ?');
  });

  it("compiles neq, boolean is, and empty groups under not", () => {
    const where = (condition: Condition) =>
      selectPlan(compileSqlite(select({ where: condition }))).rows?.text;
    expect(where(col("name", "neq", "A"))).toMatch(/where t0\."name" <> \?$/);
    expect(where(col("archived_at", "is", true))).toMatch(/is 1$/);
    expect(where(col("archived_at", "is", false))).toMatch(/is 0$/);
    const all = 'select t0."id" as "id" from "customers" as t0';
    expect(where({ kind: "not", item: col("status", "in", []) })).toBe(all);
    expect(where({ kind: "and", items: [] })).toBe(all);
    expect(where({ kind: "not", item: { kind: "or", items: [] } })).toBe(all);
    expect(
      compileSqlite(
        select({ where: { kind: "not", item: { kind: "and", items: [] } } }),
      ),
    ).toEqual({ kind: "never" });
  });

  it("names tables through tableName", () => {
    expect(
      selectPlan(
        compileSqlite(select(), { tableName: (meta) => `ps_${meta.name}` }),
      ).rows?.text,
    ).toContain('from "ps_customers"');
  });

  it("returns unsupported for includes, full-text search and function sources", () => {
    const notesRelation = customers.relations["notes"]!;
    expect(
      unsupportedOf(() =>
        compileSqlite(
          select({
            selection: {
              columns: [],
              includes: [
                {
                  alias: "notes",
                  relation: notesRelation,
                  target: notes,
                  selection: { columns: [], includes: [] },
                  where: undefined,
                  orderBy: [],
                  limit: undefined,
                  required: false,
                },
              ],
            },
          }),
        ),
      ),
    ).toMatchObject({ kind: "unsupported", table: "customers" });
    expect(
      unsupportedOf(() =>
        compileSqlite(
          select({
            where: {
              kind: "column",
              column: "metadata",
              op: "eq",
              value: "x",
              path: ["a"],
            },
          }),
        ),
      ),
    ).toMatchObject({ kind: "unsupported", details: "a json path filter" });
    expect(
      unsupportedOf(() =>
        compileSqlite(
          select({
            orderBy: [
              {
                column: "name",
                direction: "asc",
                relation: {
                  name: "organization",
                  relation: customers.relations["organization"]!,
                  target: customers,
                },
              },
            ],
          }),
        ),
      ),
    ).toMatchObject({ kind: "unsupported" });
    expect(
      unsupportedOf(() =>
        compileSqlite(select({ where: col("name", "imatch", "^a") })),
      ),
    ).toMatchObject({
      kind: "unsupported",
      details: "a regular expression filter",
    });
    expect(
      unsupportedOf(() =>
        compileSqlite(select({ where: col("name", "fts", "acme") })),
      ),
    ).toMatchObject({ kind: "unsupported", details: "full-text search" });
    expect(
      unsupportedOf(() =>
        compileSqlite(
          select({ source: { schema: "public", name: "search", args: {} } }),
        ),
      ),
    ).toMatchObject({ kind: "unsupported" });
    expect(
      unsupportedOf(() =>
        compileSqlite(
          select({ where: col("metadata", "containedBy", { tier: "pro" }) }),
        ),
      ),
    ).toMatchObject({ kind: "unsupported" });
    expect(
      unsupportedOf(() =>
        compileSqlite(
          select({ where: col("metadata", "contains", { a: { b: 1 } }) }),
        ),
      ),
    ).toMatchObject({ kind: "unsupported" });
    expect(
      unsupportedOf(() =>
        compileSqlite(select({ where: col("metadata", "contains", [null]) })),
      ),
    ).toMatchObject({ kind: "unsupported" });
  });

  it("rejects invalid input", () => {
    expect(() =>
      compileSqlite(select({ where: col("status", "in", "lead") })),
    ).toThrow(/"in" needs an array/);
    expect(() =>
      compileSqlite(select({ where: col("status", "is", "x") })),
    ).toThrow(/"is" needs/);
    expect(() => compileSqlite(select({ limit: -1 }))).toThrow(/non-negative/);
    expect(() =>
      compileSqlite({
        kind: "insert",
        table: customers,
        rows: [{ name: "A" }],
        returning: undefined,
        onConflict: undefined,
        defaultToNull: false,
      }),
    ).toThrow(/needs id/);
    expect(() =>
      compileSqlite({
        kind: "update",
        table: customers,
        set: {},
        where: undefined,
        returning: undefined,
      }),
    ).toThrow(/sets no columns/);
  });

  it("compiles aggregates with group by", () => {
    const plan = selectPlan(
      compileSqlite(
        select({
          selection: {
            columns: [{ alias: "status", column: "status" }],
            includes: [],
            aggregate: {
              count: true,
              measures: [
                {
                  key: "max_created",
                  alias: "max_created",
                  fn: "max",
                  column: "created_at",
                },
                {
                  key: "min_name",
                  alias: "min_name",
                  fn: "min",
                  column: "name",
                  cast: "text",
                },
              ],
            },
          },
        }),
      ),
    );
    expect(plan.rows?.text).toBe(
      'select t0."status" as "status", count(*) as "_count", max(t0."created_at") as "max_created", cast(min(t0."name") as text) as "min_name" from "customers" as t0 group by t0."status"',
    );
    expect(plan.columns.map((column) => column.decode)).toEqual([
      "raw",
      "raw",
      "timestamptz",
      "raw",
    ]);
  });
});

describe("SQLite semantics", () => {
  const { sqlite } = createSqlite(schema.meta);
  sqlite.exec(`
    insert into notes (id, organization_id, customer_id, kind, body, attachments) values
      (1, 'o', 'c', 'call', 'Call Ann', '["a","b"]'),
      (2, 'o', 'c', 'email', 'mail', '["b"]'),
      (3, 'o', 'c', 'email', 'MAIL', '[]'),
      (4, 'o', 'c', 'email', 'none', null);
    insert into customers (id, organization_id, name, created_at, metadata) values
      ('c1', 'o', 'A', '2026-03-08T06:59:59Z', '{"tier":"pro","source":null}'),
      ('c2', 'o', 'B', '2026-03-08 02:30:00-05:00', '{"tier":"free"}'),
      ('c3', 'o', 'C', '2026-03-09T03:59:59.999+00:00', '{}');
  `);

  function ids(where: Condition, from: TableMeta = notes): unknown[] {
    const plan = selectPlan(
      compileSqlite(
        select({
          table: from,
          where,
          orderBy: [{ column: "id", direction: "asc" }],
        }),
      ),
    );
    return sqlite
      .prepare(plan.rows!.text)
      .all(...(plan.rows!.params as never[]))
      .map((row) => row["id"]);
  }

  it("matches like case-sensitively and ilike case-insensitively", () => {
    expect(ids(col("body", "like", "%ail"))).toEqual([2]);
    expect(ids(col("body", "ilike", "%ail"))).toEqual([2, 3]);
    expect(ids(col("body", "like", "Call\\_%"))).toEqual([]);
  });

  it("reads JSON arrays like Postgres array operators", () => {
    expect(ids(col("attachments", "contains", ["b"]))).toEqual([1, 2]);
    expect(ids(col("attachments", "contains", ["a", "b"]))).toEqual([1]);
    expect(ids(col("attachments", "contains", []))).toEqual([1, 2, 3]);
    expect(ids(col("attachments", "overlaps", ["a", "z"]))).toEqual([1]);
    expect(ids(col("attachments", "overlaps", []))).toEqual([]);
    expect(ids(col("attachments", "containedBy", ["b"]))).toEqual([2, 3]);
    expect(ids(col("attachments", "containedBy", []))).toEqual([3]);
  });

  it("reads JSON objects with contains", () => {
    expect(
      ids(col("metadata", "contains", { tier: "pro" }), customers),
    ).toEqual(["c1"]);
    expect(
      ids(col("metadata", "contains", { source: null }), customers),
    ).toEqual(["c1"]);
    expect(ids(col("metadata", "contains", {}), customers)).toEqual([
      "c1",
      "c2",
      "c3",
    ]);
  });

  it("compares timestamps by instant across offsets", () => {
    // 2026-03-08 in America/New_York, the day clocks move forward (23 hours).
    const day = [
      col("created_at", "gte", "2026-03-08T05:00:00Z"),
      col("created_at", "lt", "2026-03-09T04:00:00Z"),
    ];
    expect(ids({ kind: "and", items: day }, customers)).toEqual([
      "c1",
      "c2",
      "c3",
    ]);
    expect(
      ids(col("created_at", "lte", "2026-03-08T07:30:00+00:00"), customers),
    ).toEqual(["c1", "c2"]);
    expect(
      ids(col("created_at", "eq", "2026-03-08T07:30:00.000Z"), customers),
    ).toEqual(["c2"]);
  });

  it("sorts enum types by their declared order", () => {
    const plan = selectPlan(
      compileSqlite(
        select({
          table: notes,
          orderBy: [
            { column: "kind", direction: "asc" },
            { column: "id", direction: "asc" },
          ],
        }),
      ),
    );
    expect(plan.rows?.params).toEqual(["call", "meeting", "email"]);
    expect(
      sqlite
        .prepare(plan.rows!.text)
        .all(...(plan.rows!.params as never[]))
        .map((row) => row["id"]),
    ).toEqual([1, 2, 3, 4]);
  });

  it("filters through relations with exists", () => {
    const relation = customers.relations["notes"]!;
    sqlite.exec(
      "insert into notes (id, organization_id, customer_id, kind, body) values (5, 'o', 'c1', 'call', 'hi')",
    );
    const relationCondition = (
      quantifier: "some" | "none" | "every",
    ): Condition => ({
      kind: "relation",
      name: "notes",
      relation,
      target: notes,
      quantifier,
      where: col("kind", "eq", "call"),
    });
    expect(ids(relationCondition("some"), customers)).toEqual(["c1"]);
    expect(ids(relationCondition("none"), customers)).toEqual(["c2", "c3"]);
    expect(ids(relationCondition("every"), customers)).toEqual([
      "c1",
      "c2",
      "c3",
    ]);
  });
});

describe("helpers", () => {
  it("converts values and patterns", () => {
    expect(sqliteValue(true)).toBe(1);
    expect(sqliteValue(false)).toBe(0);
    expect(sqliteValue(undefined)).toBeNull();
    expect(sqliteValue(5n)).toBe(5);
    expect(sqliteValue(2n ** 60n)).toBe(2n ** 60n);
    expect(sqliteValue({ a: 1 })).toBe('{"a":1}');
    expect(likeToGlob("a%b_c\\%[")).toBe("a*b?c%[[]");
    expect(quoteSqliteIdent('a"b')).toBe('"a""b"');
  });

  it("pages keys", () => {
    const keys = Array.from({ length: 1001 }, (_, index) => [index]);
    expect(keyPages(keys).map((page) => page.length)).toEqual([500, 500, 1]);
  });
});
