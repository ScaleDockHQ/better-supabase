import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { defineSeed, isSeed } from "../../src/testing/seed.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const sb = defineSupabase(schema);

describe("defineSeed", () => {
  it("renders parents first, with database names and literals", () => {
    const seed = defineSeed(sb, {
      customers: {
        acme: {
          id: "c1",
          organizationId: "o1",
          name: "O'Brien",
          metadata: { tier: "pro" },
        },
        bare: { organizationId: "o1", name: "Bare" },
      },
      organizations: { one: { id: "o1", name: "One", slug: "one" } },
    });
    expect(isSeed(seed)).toBe(true);
    const [organizations, customers] = seed.statements();
    expect(organizations).toBe(
      'insert into "public"."organizations" ("id", "name", "slug") values\n  (\'o1\', \'One\', \'one\')\non conflict do nothing;',
    );
    expect(customers).toContain(
      '("id", "organization_id", "name", "metadata")',
    );
    expect(customers).toContain(`('c1', 'o1', 'O''Brien', '{"tier":"pro"}')`);
    expect(customers).toContain("(default, 'o1', 'Bare', default)");
    expect(seed.rows.customers.acme.name).toBe("O'Brien");
  });

  it("renders arrays, dates, nulls and numbers", () => {
    const sql = defineSeed(sb, {
      organizations: { one: { id: "o1", name: "One", slug: "one" } },
      customers: {
        one: { organizationId: "o1", name: "x", kvk: null },
      },
    }).sql();
    expect(sql).toContain("('o1', 'x', null)");

    const bad = defineSeed(sb, {
      organizations: { bad: { id: "o1", name: "x", nope: 1 } as never },
    });
    expect(() => bad.statements()).toThrow('unknown column "nope"');
  });

  it("quotes array elements and serialises instants", () => {
    const column = (db: string, type: string, extra: object = {}) => ({
      db,
      type,
      nullable: true,
      hasDefault: false,
      ...extra,
    });
    const fake = {
      meta: {
        version: 1,
        casing: "snake",
        enums: {},
        functions: {},
        tables: {
          events: {
            key: "events",
            name: "events",
            schema: "app",
            kind: "table",
            primaryKey: [],
            uniqueKeys: {},
            relations: {},
            flags: {},
            columns: {
              tags: column("tags", "text", { array: true }),
              at: column("at", "timestamptz"),
              payload: column("payload", "jsonb", { json: true }),
            },
          },
        },
      },
    };
    const sql = defineSeed(
      fake as never,
      {
        events: {
          one: {
            tags: ['a "b"', "c\\d", null],
            at: Temporal.Instant.from("2026-01-02T03:04:05Z"),
            payload: ["kept", "as json"],
          },
        },
      } as never,
    ).sql();
    expect(sql).toContain(
      `('{"a \\"b\\"","c\\\\d",NULL}', '2026-01-02T03:04:05Z', '["kept","as json"]')`,
    );
  });

  it("rejects unknown tables at render time", () => {
    const seed = defineSeed(sb, { nope: {} } as never);
    expect(() => seed.sql()).toThrow('unknown table "nope"');
  });
});

describe("defineSeed literals and ordering", () => {
  const column = (db: string, extra: object = {}) => ({
    db,
    type: "text",
    nullable: true,
    hasDefault: false,
    ...extra,
  });
  const table = (key: string, extra: object = {}) => ({
    key,
    name: key,
    schema: "app",
    kind: "table",
    primaryKey: [],
    uniqueKeys: {},
    relations: {},
    flags: {},
    columns: { value: column("value"), id: column("id") },
    ...extra,
  });
  const forward = (target: string) => ({
    table: target,
    direction: "forward",
    kind: "one",
    columns: [],
    references: [],
  });
  const fakeSb = {
    meta: {
      version: 1,
      casing: "snake",
      enums: {},
      functions: {},
      tables: {
        values: table("values", {
          columns: {
            value: column("value"),
            total: column("total", { generated: true }),
            list: column("list", { array: true }),
          },
        }),
        report: table("report", { kind: "view" }),
        // a and b point at each other; c points at itself and at a.
        a: table("a", { relations: { b: forward("b") } }),
        b: table("b", { relations: { a: forward("a") } }),
        c: table("c", { relations: { self: forward("c"), a: forward("a") } }),
      },
    },
  };
  const render = (fixtures: object) =>
    defineSeed(fakeSb as never, fixtures as never);
  const value = (input: unknown) =>
    render({ values: { one: { value: input } } }).sql();

  it("renders booleans, bigints, numbers and nested arrays", () => {
    expect(value(true)).toContain("  (true)");
    expect(value(12n)).toContain("  (12)");
    expect(value(1.5)).toContain("  (1.5)");
    expect(
      render({
        values: {
          one: {
            list: [[1, 2], [Temporal.Instant.from("2026-01-01T00:00:00Z")]],
          },
        },
      }).sql(),
    ).toContain(`('{{"1","2"},{"2026-01-01T00:00:00Z"}}')`);
  });

  it("rejects values it can't render, naming the cell", () => {
    expect(() => value(Number.NaN)).toThrow(
      "seed values.one.value: NaN is not a finite number",
    );
    expect(() => value(Number.POSITIVE_INFINITY)).toThrow(
      /Infinity is not a finite number/,
    );
    expect(() => value({ a: 1 })).toThrow(
      "seed values.one.value: unsupported value of type object",
    );
    expect(() => value(() => 1)).toThrow(/unsupported value of type function/);
    expect(() => value(Symbol("s"))).toThrow(
      /unsupported value of type symbol/,
    );
  });

  it("rejects generated columns and views", () => {
    expect(() => render({ values: { one: { total: 3 } } }).sql()).toThrow(
      'seed values: "total" is a generated column',
    );
    expect(() => render({ report: { one: { value: "x" } } }).sql()).toThrow(
      'seed: "report" is a view',
    );
  });

  it("skips empty and undefined tables", () => {
    expect(render({ values: {}, report: undefined }).statements()).toEqual([]);
  });

  it("orders parents first, tolerating cycles and self references", () => {
    const tables = (fixtures: object) =>
      render(fixtures)
        .statements()
        .map((text) => /"app"\."(\w+)"/.exec(text)?.[1]);
    const row = { r: { value: "x" } };
    expect(tables({ c: row, a: row, b: row })).toEqual(["b", "a", "c"]);
    expect(tables({ a: row, b: row })).toEqual(["b", "a"]);
  });

  it("inserts each statement in order", async () => {
    const fake = fakeSql();
    await render({ c: { r: { value: "x" } }, a: { r: { value: "y" } } }).insert(
      fake.sql,
    );
    expect(fake.texts()).toEqual([
      'insert into "app"."a" ("value") values\n  (\'y\')\non conflict do nothing;',
      'insert into "app"."c" ("value") values\n  (\'x\')\non conflict do nothing;',
    ]);
  });
});
