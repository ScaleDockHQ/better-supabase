import { describe, expect, it } from "vitest";

import type {
  Condition,
  Include,
  SelectOp,
  Selection,
} from "../../src/ir/types.ts";
import type { RelationMeta, TableMeta } from "../../src/schema/types.ts";

import { compileSql, quoteIdent } from "../../src/compile/sql.ts";
import { DbException } from "../../src/core/errors.ts";
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
    relation: relation(customers, "notes"),
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

function rows(op: SelectOp): { text: string; params: readonly unknown[] } {
  const plan = compileSql(op);
  if (!plan.rows) throw new Error("Expected a rows query");
  return plan.rows;
}

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

const BASE = `select json_build_object('id', t0."id") as row from "public"."customers" as t0`;

describe("quoteIdent", () => {
  it("doubles embedded quotes", () => {
    expect(quoteIdent('we"ird')).toBe('"we""ird"');
  });
});

describe("compileSql column conditions", () => {
  it.each<[string, Condition, string, unknown[]]>([
    ["eq", col("name", "eq", "Acme"), `t0."name" = $1`, ["Acme"]],
    ["neq", col("name", "neq", "Acme"), `t0."name" <> $1`, ["Acme"]],
    ["gt", col("name", "gt", 1), `t0."name" > $1`, [1]],
    ["gte", col("name", "gte", 1), `t0."name" >= $1`, [1]],
    ["lt", col("name", "lt", 1), `t0."name" < $1`, [1]],
    ["lte", col("name", "lte", 1), `t0."name" <= $1`, [1]],
    ["like", col("name", "like", "A%"), `t0."name" like $1`, ["A%"]],
    ["ilike", col("name", "ilike", "%a%"), `t0."name" ilike $1`, ["%a%"]],
    [
      "in",
      col("status", "in", ["lead", "active"]),
      `t0."status" = any($1)`,
      [["lead", "active"]],
    ],
    ["is null", col("kvk", "is", null), `t0."kvk" is null`, []],
    ["is true", col("kvk", "is", true), `t0."kvk" is true`, []],
    ["is false", col("kvk", "is", false), `t0."kvk" is false`, []],
    [
      "contains array",
      col("tags", "contains", ["a"]),
      `t0."tags" @> $1`,
      [["a"]],
    ],
    [
      "contains json",
      col("metadata", "contains", { plan: "pro" }),
      `t0."metadata" @> $1::jsonb`,
      ['{"plan":"pro"}'],
    ],
    [
      "contains a json array",
      jsonCol("metadata", "contains", [{ type: "x" }]),
      `t0."metadata" @> $1::jsonb`,
      ['[{"type":"x"}]'],
    ],
    [
      "a json path",
      pathCol("metadata", "eq", "u1", ["owner", "id"]),
      `(t0."metadata" #>> $1::text[]) = $2`,
      [["owner", "id"], "u1"],
    ],
    [
      "a json path null check",
      pathCol("metadata", "is", null, ["owner"]),
      `(t0."metadata" #>> $1::text[]) is null`,
      [["owner"]],
    ],
    [
      "containedBy array",
      col("tags", "containedBy", ["a", "b"]),
      `t0."tags" <@ $1`,
      [["a", "b"]],
    ],
    [
      "containedBy json",
      col("metadata", "containedBy", { a: 1 }),
      `t0."metadata" <@ $1::jsonb`,
      ['{"a":1}'],
    ],
    ["overlaps", col("tags", "overlaps", ["a"]), `t0."tags" && $1`, [["a"]]],
    [
      "fts on text",
      col("name", "fts", "acme"),
      `to_tsvector(t0."name") @@ websearch_to_tsquery($1)`,
      ["acme"],
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
      `to_tsvector($1::regconfig, t0."name") @@ websearch_to_tsquery($1::regconfig, $2)`,
      ["dutch", "acme"],
    ],
  ])("%s", (_name, where, expected, params) => {
    expect(rows(select({ where }))).toEqual({
      text: `${BASE} where ${expected}`,
      params,
    });
  });

  it("matches a tsvector column directly", () => {
    const searchable: TableMeta = {
      ...customers,
      columns: {
        ...customers.columns,
        search: {
          db: "search",
          type: "tsvector",
          nullable: false,
          hasDefault: false,
        },
      },
    };
    expect(
      rows(select({ table: searchable, where: col("search", "fts", "acme") })),
    ).toEqual({
      text: `${BASE} where t0."search" @@ websearch_to_tsquery($1)`,
      params: ["acme"],
    });
  });

  it.each<[string, Condition, string]>([
    ["in without an array", col("status", "in", "lead"), '"in" needs an array'],
    [
      "is with a string",
      col("kvk", "is", "x"),
      '"is" needs null, true or false',
    ],
  ])("rejects %s", (_name, where, message) => {
    expect(invalid(() => compileSql(select({ where })))).toBe(message);
  });
});

describe("compileSql boolean conditions", () => {
  it.each<[string, Condition, string, unknown[]]>([
    [
      "and",
      { kind: "and", items: [col("name", "eq", "A"), col("kvk", "is", null)] },
      `(t0."name" = $1 and t0."kvk" is null)`,
      ["A"],
    ],
    [
      "or",
      { kind: "or", items: [col("name", "eq", "A"), col("name", "eq", "B")] },
      `(t0."name" = $1 or t0."name" = $2)`,
      ["A", "B"],
    ],
    [
      "not",
      { kind: "not", item: col("name", "eq", "A") },
      `not t0."name" = $1`,
      ["A"],
    ],
    [
      "nested",
      {
        kind: "or",
        items: [
          {
            kind: "and",
            items: [col("name", "eq", "A"), col("status", "eq", "lead")],
          },
          { kind: "not", item: col("kvk", "is", null) },
        ],
      },
      `((t0."name" = $1 and t0."status" = $2) or not t0."kvk" is null)`,
      ["A", "lead"],
    ],
    [
      "a keyset step as a row comparison",
      {
        kind: "or",
        items: [
          col("created_at", "lt", "2026-02-01"),
          {
            kind: "and",
            items: [
              col("created_at", "eq", "2026-02-01"),
              col("id", "lt", "c2"),
            ],
          },
        ],
      },
      `(t0."created_at", t0."id") < ($1, $2)`,
      ["2026-02-01", "c2"],
    ],
    [
      "json path steps as an OR of ANDs",
      {
        kind: "or",
        items: [
          pathCol("metadata", "gt", "b", ["a"]),
          {
            kind: "and",
            items: [
              pathCol("metadata", "eq", "b", ["a"]),
              col("id", "gt", "c2"),
            ],
          },
        ],
      },
      `((t0."metadata" #>> $1::text[]) > $2 or ((t0."metadata" #>> $3::text[]) = $4 and t0."id" > $5))`,
      [["a"], "b", ["a"], "b", "c2"],
    ],
    [
      "mixed directions as an OR of ANDs",
      {
        kind: "or",
        items: [
          col("created_at", "lt", "2026-02-01"),
          {
            kind: "and",
            items: [
              col("created_at", "eq", "2026-02-01"),
              col("id", "gt", "c2"),
            ],
          },
        ],
      },
      `(t0."created_at" < $1 or (t0."created_at" = $2 and t0."id" > $3))`,
      ["2026-02-01", "2026-02-01", "c2"],
    ],
    [
      "a step whose equality doesn't match the previous column",
      {
        kind: "or",
        items: [
          col("name", "gt", "A"),
          {
            kind: "and",
            items: [col("kvk", "eq", "A"), col("id", "gt", "c2")],
          },
        ],
      },
      `(t0."name" > $1 or (t0."kvk" = $2 and t0."id" > $3))`,
      ["A", "A", "c2"],
    ],
  ])("%s", (_name, where, expected, params) => {
    expect(rows(select({ where }))).toEqual({
      text: `${BASE} where ${expected}`,
      params,
    });
  });

  it("drops a condition that folds to true", () => {
    expect(rows(select({ where: { kind: "and", items: [] } }))).toEqual({
      text: BASE,
      params: [],
    });
  });

  it("runs nothing when the condition can never match", () => {
    expect(compileSql(select({ where: col("id", "in", []) }))).toEqual({
      rows: undefined,
      count: undefined,
      never: true,
    });
  });
});

describe("compileSql relation conditions", () => {
  const notesOf = relation(customers, "notes");
  const on = (
    quantifier: "some" | "none" | "every",
    where: Condition | undefined,
  ): Extract<Condition, { kind: "relation" }> => ({
    kind: "relation",
    name: "notes",
    relation: notesOf,
    target: notes,
    quantifier,
    where,
  });
  const from = `select 1 from "public"."notes" as t1 where t1."customer_id" = t0."id" and t1."organization_id" = t0."organization_id"`;

  it.each<[string, Condition, string, unknown[]]>([
    [
      "some",
      on("some", col("body", "eq", "x")),
      `exists (${from} and t1."body" = $1)`,
      ["x"],
    ],
    ["some without where", on("some", undefined), `exists (${from})`, []],
    [
      "none",
      on("none", col("body", "eq", "x")),
      `not exists (${from} and t1."body" = $1)`,
      ["x"],
    ],
    [
      "every",
      on("every", col("body", "eq", "x")),
      `not exists (${from} and not t1."body" = $1)`,
      ["x"],
    ],
    [
      "every of a false filter",
      on("every", col("id", "in", [])),
      `not exists (${from})`,
      [],
    ],
  ])("%s", (_name, where, expected, params) => {
    expect(rows(select({ where }))).toEqual({
      text: `${BASE} where ${expected}`,
      params,
    });
  });

  it("joins every column of a composite relation", () => {
    expect(notesOf.references).toEqual(["customerId", "organizationId"]);
    expect(rows(select({ where: on("some", undefined) })).text).toBe(
      `${BASE} where exists (select 1 from "public"."notes" as t1 where t1."customer_id" = t0."id" and t1."organization_id" = t0."organization_id")`,
    );
  });

  it("rejects a relation with mismatched columns", () => {
    const broken: RelationMeta = { ...notesOf, columns: ["id"] };
    expect(
      invalid(() =>
        compileSql(
          select({ where: { ...on("some", undefined), relation: broken } }),
        ),
      ),
    ).toBe('Relation to "notes" has mismatched columns');
  });

  it("rejects a relation to an unknown column", () => {
    const broken: RelationMeta = {
      ...notesOf,
      references: ["nope", "organizationId"],
    };
    expect(
      invalid(() =>
        compileSql(
          select({ where: { ...on("some", undefined), relation: broken } }),
        ),
      ),
    ).toBe('Unknown column "nope" on "notes"');
  });
});

describe("compileSql selections", () => {
  it("casts columns and escapes aliases", () => {
    const selection: Selection = {
      columns: [
        { alias: "it's", column: "id", cast: "text" },
        { alias: "name", column: "name" },
      ],
      includes: [],
    };
    expect(rows(select({ selection })).text).toBe(
      `select json_build_object('it''s', t0."id"::text, 'name', t0."name") as row from "public"."customers" as t0`,
    );
  });

  it("groups aggregates by the selected columns", () => {
    const selection: Selection = {
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
          { fn: "max", key: "_max_name", alias: "name", column: "name" },
        ],
      },
    };
    expect(rows(select({ selection })).text).toBe(
      `select json_build_object('status', t0."status", '_count', count(*), '_sum_id', sum(t0."id")::text, '_max_name', max(t0."name")) as row from "public"."customers" as t0 group by t0."status"`,
    );
  });

  it("returns one aggregate row without grouping columns", () => {
    const selection: Selection = {
      columns: [],
      includes: [],
      aggregate: {
        count: false,
        measures: [{ fn: "avg", key: "_avg_id", alias: "id", column: "id" }],
      },
    };
    expect(rows(select({ selection })).text).toBe(
      `select json_build_object('_avg_id', avg(t0."id")) as row from "public"."customers" as t0`,
    );
  });

  it("splits more than 50 pairs into jsonb chunks", () => {
    const columns = Array.from({ length: 51 }, (_, index) => ({
      alias: `c${index}`,
      column: "id",
    }));
    const text = rows(select({ selection: { columns, includes: [] } })).text;
    const pair = (index: number) => `'c${index}', t0."id"`;
    const first = Array.from({ length: 50 }, (_, index) => pair(index)).join(
      ", ",
    );
    expect(text).toBe(
      `select (jsonb_build_object(${first}) || jsonb_build_object(${pair(50)}))::json as row from "public"."customers" as t0`,
    );
  });
});

describe("compileSql includes", () => {
  const withInclude = (...includes: Include[]): SelectOp =>
    select({
      selection: { columns: [{ alias: "id", column: "id" }], includes },
    });
  const prefix = `select json_build_object('id', t0."id", `;
  const suffix = `) as row from "public"."customers" as t0`;
  const join = `t1."customer_id" = t0."id" and t1."organization_id" = t0."organization_id"`;

  it.each<[string, Include, string, unknown[]]>([
    [
      "a to-one relation",
      include({
        alias: "organization",
        relation: relation(customers, "organization"),
        target: organizations,
      }),
      `'organization', (select json_build_object('id', t1."id") from "public"."organizations" as t1 where t1."id" = t0."organization_id" limit 1)`,
      [],
    ],
    [
      "a to-many relation",
      include(),
      `'notes', (select coalesce(json_agg(s.r order by s.o), '[]'::json) from (select json_build_object('id', t1."id") as r, row_number() over () as o from "public"."notes" as t1 where ${join}) as s)`,
      [],
    ],
    [
      "a filtered, ordered and limited to-many relation",
      include({
        where: col("body", "eq", "x"),
        orderBy: [
          { column: "created_at", direction: "desc", nulls: "last" },
          { column: "id", direction: "asc" },
        ],
        limit: 5,
      }),
      `'notes', (select coalesce(json_agg(s.r order by s.o), '[]'::json) from (select json_build_object('id', t1."id") as r, row_number() over (order by t1."created_at" desc nulls last, t1."id" asc) as o from "public"."notes" as t1 where ${join} and t1."body" = $1 order by t1."created_at" desc nulls last, t1."id" asc limit 5) as s)`,
      ["x"],
    ],
    [
      "a filter that never matches",
      include({ where: col("id", "in", []) }),
      `'notes', (select coalesce(json_agg(s.r order by s.o), '[]'::json) from (select json_build_object('id', t1."id") as r, row_number() over () as o from "public"."notes" as t1 where ${join} and false) as s)`,
      [],
    ],
    [
      "a count",
      include({
        alias: "_count_notes",
        count: "notes",
        selection: { columns: [], includes: [] },
      }),
      `'_count_notes', (select count(*) from "public"."notes" as t1 where ${join})`,
      [],
    ],
    [
      "an aggregate",
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
      `'_sum_notes', (select json_build_object('id', sum(t1."id")) from "public"."notes" as t1 where ${join})`,
      [],
    ],
  ])("renders %s", (_name, entry, expected, params) => {
    expect(rows(withInclude(entry))).toEqual({
      text: `${prefix}${expected}${suffix}`,
      params,
    });
  });

  it("filters parents on a required include before rendering it", () => {
    const op = withInclude(
      include({ required: true, where: col("body", "eq", "x") }),
    );
    expect(rows({ ...op, where: col("name", "eq", "Acme") })).toEqual({
      text: `${prefix}'notes', (select coalesce(json_agg(s.r order by s.o), '[]'::json) from (select json_build_object('id', t2."id") as r, row_number() over () as o from "public"."notes" as t2 where t2."customer_id" = t0."id" and t2."organization_id" = t0."organization_id" and t2."body" = $3) as s)${suffix} where t0."name" = $1 and exists (select 1 from "public"."notes" as t1 where ${join} and t1."body" = $2)`,
      params: ["Acme", "x", "x"],
    });
  });

  it("nests required includes inside an include", () => {
    const nested = include({
      alias: "organization",
      relation: relation(notes, "organization"),
      target: organizations,
      required: true,
    });
    const op = withInclude(
      include({
        selection: {
          columns: [{ alias: "id", column: "id" }],
          includes: [nested],
        },
      }),
    );
    expect(rows(op).text).toBe(
      `${prefix}'notes', (select coalesce(json_agg(s.r order by s.o), '[]'::json) from (select json_build_object('id', t1."id", 'organization', (select json_build_object('id', t3."id") from "public"."organizations" as t3 where t3."id" = t1."organization_id" limit 1)) as r, row_number() over () as o from "public"."notes" as t1 where ${join} and exists (select 1 from "public"."organizations" as t2 where t2."id" = t1."organization_id")) as s)${suffix}`,
    );
  });

  it("rejects a negative include limit", () => {
    expect(invalid(() => compileSql(withInclude(include({ limit: -1 }))))).toBe(
      "Expected a non-negative integer, got -1",
    );
  });
});

describe("compileSql reads", () => {
  it("orders, limits and offsets", () => {
    expect(
      rows(
        select({
          orderBy: [{ column: "name", direction: "asc", nulls: "first" }],
          limit: 10,
          offset: 20,
        }),
      ).text,
    ).toBe(`${BASE} order by t0."name" asc nulls first limit 10 offset 20`);
  });

  it.each([1.5, -1])("rejects the limit %s", (limit) => {
    expect(invalid(() => compileSql(select({ limit })))).toBe(
      `Expected a non-negative integer, got ${limit}`,
    );
  });

  it("rejects a fractional offset", () => {
    expect(invalid(() => compileSql(select({ offset: 0.5 })))).toBe(
      "Expected a non-negative integer, got 0.5",
    );
  });

  it("adds a count query next to the rows", () => {
    expect(
      compileSql(
        select({ count: "exact", where: col("name", "eq", "Acme"), limit: 1 }),
      ),
    ).toEqual({
      rows: { text: `${BASE} where t0."name" = $1 limit 1`, params: ["Acme"] },
      count: {
        text: `select count(*)::int as count from "public"."customers" as t0 where t0."name" = $1`,
        params: ["Acme"],
      },
      never: false,
    });
  });

  it.each([["exact" as const], [undefined]])(
    "only counts for a head read (count %s)",
    (count) => {
      expect(
        compileSql(
          select({ head: true, count, where: col("name", "eq", "Acme") }),
        ),
      ).toEqual({
        rows: undefined,
        count: {
          text: `select count(*)::int as count from "public"."customers" as t0 where t0."name" = $1`,
          params: ["Acme"],
        },
        never: false,
      });
    },
  );

  it("reads from a set-returning function with named arguments", () => {
    expect(
      rows(
        select({
          table: notes,
          source: {
            schema: "public",
            name: "search_notes",
            args: { query: "hi", match_count: 5 },
          },
          where: col("kind", "eq", "call"),
        }),
      ),
    ).toEqual({
      text: `select json_build_object('id', t0."id") as row from "public"."search_notes"("query" => $1, "match_count" => $2) as t0 where t0."kind" = $3`,
      params: ["hi", 5, "call"],
    });
  });
});

describe("compileSql inserts", () => {
  const insert = (
    overrides: Partial<
      Extract<Parameters<typeof compileSql>[0], { kind: "insert" }>
    > = {},
  ) =>
    compileSql({
      kind: "insert",
      table: customers,
      rows: [{ name: "Acme", organization_id: "o1" }],
      returning: undefined,
      onConflict: undefined,
      defaultToNull: false,
      ...overrides,
    });
  const into = `insert into "public"."customers" as t0`;
  const counted = (statement: string) =>
    `with m as (${statement}) select count(*)::int as count from m`;

  it("counts affected rows without a returning selection", () => {
    expect(insert()).toEqual({
      rows: undefined,
      count: {
        text: counted(
          `${into} ("name", "organization_id") values ($1, $2) returning 1`,
        ),
        params: ["Acme", "o1"],
      },
      never: false,
    });
  });

  it("splits an insert to stay under 65,535 bind parameters", () => {
    const rows = Array.from({ length: 32_768 }, (_, index) => ({
      name: `c${index}`,
      organization_id: "o1",
    }));
    const plan = insert({ rows, returning: idOnly });
    const statements = [plan, ...(plan.chunks ?? [])];
    expect(statements.map((entry) => entry.rows?.params.length)).toEqual([
      65_534, 2,
    ]);
    expect(plan.chunks?.[0]?.rows?.text).toBe(
      `${into} ("name", "organization_id") values ($1, $2) returning json_build_object('id', t0."id") as row`,
    );
    expect(insert({ rows: rows.slice(0, 32_767) }).chunks).toBeUndefined();
  });

  it("returns rows with a returning selection", () => {
    expect(insert({ returning: idOnly })).toEqual({
      rows: {
        text: `${into} ("name", "organization_id") values ($1, $2) returning json_build_object('id', t0."id") as row`,
        params: ["Acme", "o1"],
      },
      count: undefined,
      never: false,
    });
  });

  it.each([
    [false, "default"],
    [true, "null"],
  ])(
    "fills missing bulk columns (defaultToNull %s)",
    (defaultToNull, filler) => {
      expect(
        insert({
          rows: [{ name: "A" }, { name: "B", kvk: "k" }],
          defaultToNull,
        }).count,
      ).toEqual({
        text: counted(
          `${into} ("name", "kvk") values ($1, ${filler}), ($2, $3) returning 1`,
        ),
        params: ["A", "B", "k"],
      });
    },
  );

  it("inserts default values for an empty row", () => {
    expect(insert({ rows: [{}] }).count?.text).toBe(
      counted(`${into} default values returning 1`),
    );
  });

  it("rejects several rows without columns", () => {
    expect(invalid(() => insert({ rows: [{}, {}] }))).toBe(
      "Cannot insert several rows without columns",
    );
  });

  it("runs nothing for no rows", () => {
    expect(insert({ rows: [] })).toEqual({
      rows: undefined,
      count: undefined,
      never: true,
    });
  });

  it.each<[string, Parameters<typeof insert>[0], string]>([
    [
      "updates on conflict",
      { onConflict: { columns: ["id"], action: "update" } },
      `${into} ("name", "organization_id") values ($1, $2) on conflict ("id") do update set "name" = excluded."name", "organization_id" = excluded."organization_id" where t0."organization_id" = excluded."organization_id" returning 1`,
    ],
    [
      "ignores on conflict",
      { onConflict: { columns: ["organization_id", "kvk"], action: "ignore" } },
      `${into} ("name", "organization_id") values ($1, $2) on conflict ("organization_id", "kvk") do nothing returning 1`,
    ],
    [
      "does nothing on conflict when no column is set",
      { rows: [{}], onConflict: { columns: ["id"], action: "update" } },
      `${into} default values on conflict ("id") do nothing returning 1`,
    ],
  ])("%s", (_name, overrides, statement) => {
    expect(insert(overrides).count?.text).toBe(counted(statement));
  });
});

describe("compileSql updates and deletes", () => {
  const counted = (statement: string) =>
    `with m as (${statement}) select count(*)::int as count from m`;

  it("updates the matching rows", () => {
    expect(
      compileSql({
        kind: "update",
        table: customers,
        set: { name: "B", kvk: null },
        where: col("id", "eq", "c1"),
        returning: undefined,
      }),
    ).toEqual({
      rows: undefined,
      count: {
        text: counted(
          `update "public"."customers" as t0 set "name" = $1, "kvk" = $2 where t0."id" = $3 returning 1`,
        ),
        params: ["B", null, "c1"],
      },
      never: false,
    });
  });

  it("updates every row and returns them", () => {
    expect(
      compileSql({
        kind: "update",
        table: customers,
        set: { name: "B" },
        where: undefined,
        returning: idOnly,
      }).rows,
    ).toEqual({
      text: `update "public"."customers" as t0 set "name" = $1 returning json_build_object('id', t0."id") as row`,
      params: ["B"],
    });
  });

  it("rejects an update that sets nothing", () => {
    expect(
      invalid(() =>
        compileSql({
          kind: "update",
          table: customers,
          set: {},
          where: undefined,
          returning: undefined,
        }),
      ),
    ).toBe('Update on "customers" sets no columns');
  });

  it("deletes the matching rows", () => {
    expect(
      compileSql({
        kind: "delete",
        table: customers,
        where: col("id", "eq", "c1"),
        returning: undefined,
      }).count,
    ).toEqual({
      text: counted(
        `delete from "public"."customers" as t0 where t0."id" = $1 returning 1`,
      ),
      params: ["c1"],
    });
  });

  it("deletes every row and returns them", () => {
    expect(
      compileSql({
        kind: "delete",
        table: customers,
        where: undefined,
        returning: idOnly,
      }).rows,
    ).toEqual({
      text: `delete from "public"."customers" as t0 returning json_build_object('id', t0."id") as row`,
      params: [],
    });
  });

  it.each([
    [
      {
        kind: "update",
        table: customers,
        set: { name: "B" },
        where: col("id", "in", []),
        returning: undefined,
      },
    ],
    [
      {
        kind: "delete",
        table: customers,
        where: col("id", "in", []),
        returning: undefined,
      },
    ],
  ] as const)("runs nothing when the filter never matches (%#)", (op) => {
    expect(compileSql(op)).toEqual({
      rows: undefined,
      count: undefined,
      never: true,
    });
  });
});
