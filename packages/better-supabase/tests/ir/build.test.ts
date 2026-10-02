import { describe, expect, it } from "vitest";

import type { DbError } from "../../src/core/errors.ts";
import type { Condition } from "../../src/ir/types.ts";
import type { SchemaMeta, TableMeta } from "../../src/schema/types.ts";

import { DbException } from "../../src/core/errors.ts";
import { IrBuilder, escapeLike, invalidRequest } from "../../src/ir/build.ts";
import { schema } from "../fixtures/generated-camel.ts";

const ledger: TableMeta = {
  key: "ledger",
  name: "ledger",
  schema: "public",
  kind: "table",
  columns: {
    id: {
      db: "id",
      type: "int8",
      nullable: false,
      hasDefault: true,
      identity: "always",
      codec: "bigint",
    },
    amount: {
      db: "amount",
      type: "numeric",
      nullable: false,
      hasDefault: false,
      codec: "string",
    },
    bookedAt: {
      db: "booked_at",
      type: "timestamptz",
      nullable: false,
      hasDefault: true,
      codec: "date",
    },
    total: {
      db: "total",
      type: "numeric",
      nullable: false,
      hasDefault: false,
      generated: true,
    },
    tags: {
      db: "tags",
      type: "text",
      nullable: false,
      hasDefault: true,
      array: true,
    },
    locked: {
      db: "locked",
      type: "text",
      nullable: true,
      hasDefault: false,
      updatable: false,
    },
    label: { db: "label", type: "text", nullable: true, hasDefault: false },
  },
  primaryKey: ["id"],
  uniqueKeys: {},
  relations: {},
  flags: {},
};

const ledgerView: TableMeta = {
  ...ledger,
  key: "ledgerView",
  name: "ledger_view",
  kind: "view",
  columns: {
    label: {
      db: "label",
      type: "text",
      nullable: true,
      hasDefault: false,
      insertable: false,
    },
  },
  primaryKey: [],
};

const meta: SchemaMeta = {
  ...schema.meta,
  tables: { ...schema.meta.tables, ledger, ledgerView },
};

const ir = new IrBuilder(meta);
const customers = ir.table("customers");
const notes = ir.table("notes");
const organizations = ir.table("organizations");
const relation = (from: TableMeta, name: string) => {
  const found = from.relations[name];
  if (!found) throw new Error(`No relation ${name}`);
  return found;
};

function rejection(fn: () => unknown): DbError {
  try {
    fn();
  } catch (error) {
    if (error instanceof DbException) return error.error;
    throw error;
  }
  throw new Error("Expected a DbException");
}

const col = (
  column: string,
  op: Extract<Condition, { kind: "column" }>["op"],
  value: unknown,
): Condition => ({ kind: "column", column, op, value });

const notesRelation = (
  quantifier: "some" | "none" | "every",
  where: Condition | undefined,
): Condition => ({
  kind: "relation",
  name: "notes",
  relation: relation(customers, "notes"),
  target: notes,
  quantifier,
  where,
});

const organizationRelation = (
  quantifier: "some" | "none",
  where: Condition | undefined,
): Condition => ({
  kind: "relation",
  name: "organization",
  relation: relation(customers, "organization"),
  target: organizations,
  quantifier,
  where,
});

describe("invalidRequest and escapeLike", () => {
  it("throws an invalid_request DbException with the table", () => {
    expect(rejection(() => invalidRequest("Bad", "customers"))).toEqual({
      kind: "invalid_request",
      message: "Bad",
      status: 400,
      table: "customers",
    });
    expect(rejection(() => invalidRequest("Bad"))).toEqual({
      kind: "invalid_request",
      message: "Bad",
      status: 400,
    });
  });

  it("escapes LIKE wildcards and backslashes", () => {
    expect(escapeLike("50%_off\\")).toBe("50\\%\\_off\\\\");
  });
});

describe("IrBuilder lookups", () => {
  it("rejects an unknown table", () => {
    expect(rejection(() => ir.table("nope"))).toMatchObject({
      message: 'Unknown table "nope"',
    });
  });

  it("rejects an unknown column with its table", () => {
    expect(rejection(() => ir.column(customers, "nope"))).toEqual({
      kind: "invalid_request",
      status: 400,
      message: 'Unknown column "nope" on "customers"',
      table: "customers",
    });
  });
});

describe("IrBuilder.where", () => {
  it.each<[string, unknown, Condition | undefined]>([
    ["nothing", undefined, undefined],
    ["an empty object", {}, undefined],
    ["a value", { name: "Acme" }, col("name", "eq", "Acme")],
    [
      "skipped undefined values",
      { name: undefined, kvk: "k" },
      col("kvk", "eq", "k"),
    ],
    ["null", { kvk: null }, col("kvk", "is", null)],
    [
      "a Date value",
      { createdAt: new Date("2026-01-01T00:00:00.000Z") },
      col("created_at", "eq", "2026-01-01T00:00:00.000Z"),
    ],
    [
      "a json value",
      { metadata: { plan: "pro" } },
      col("metadata", "eq", { plan: "pro" }),
    ],
    [
      "two fields",
      { name: "A", kvk: "k" },
      { kind: "and", items: [col("name", "eq", "A"), col("kvk", "eq", "k")] },
    ],
    ["AND with one object", { AND: { name: "A" } }, col("name", "eq", "A")],
    [
      "AND with a list",
      { AND: [{ name: "A" }, { kvk: "k" }] },
      { kind: "and", items: [col("name", "eq", "A"), col("kvk", "eq", "k")] },
    ],
    [
      "an empty OR",
      { OR: [] },
      { kind: "not", item: { kind: "and", items: [] } },
    ],
    [
      "an OR with one real branch",
      { OR: [{ name: "A" }, {}] },
      col("name", "eq", "A"),
    ],
    [
      "an OR",
      { OR: [{ name: "A" }, { name: "B" }] },
      { kind: "or", items: [col("name", "eq", "A"), col("name", "eq", "B")] },
    ],
    [
      "NOT",
      { NOT: { name: "A" } },
      { kind: "not", item: col("name", "eq", "A") },
    ],
    ["an empty NOT", { NOT: {} }, undefined],
  ])("builds %s", (_name, input, expected) => {
    expect(ir.where(customers, input)).toEqual(expected);
  });

  it.each<[string, unknown, string]>([
    ["a non-object where", "x", '"where" on "customers" must be an object'],
    [
      "a class instance",
      new Date(),
      '"where" on "customers" must be an object',
    ],
    [
      "an OR object",
      { OR: { name: "A" } },
      '"OR" on "customers" must be an array',
    ],
    ["an unknown field", { nope: 1 }, 'Unknown column "nope" on "customers"'],
  ])("rejects %s", (_name, input, message) => {
    expect(rejection(() => ir.where(customers, input))).toMatchObject({
      message,
      table: "customers",
    });
  });
});

describe("IrBuilder.where field operators", () => {
  it.each<[string, unknown, Condition]>([
    ["eq", { eq: "A" }, col("name", "eq", "A")],
    ["eq null", { eq: null }, col("name", "is", null)],
    ["neq", { neq: "A" }, col("name", "neq", "A")],
    ["neq null", { neq: null }, { kind: "not", item: col("name", "is", null) }],
    ["in", { in: ["A", "B"] }, col("name", "in", ["A", "B"])],
    [
      "notIn",
      { notIn: ["A"] },
      { kind: "not", item: col("name", "in", ["A"]) },
    ],
    ["isNull true", { isNull: true }, col("name", "is", null)],
    [
      "isNull false",
      { isNull: false },
      { kind: "not", item: col("name", "is", null) },
    ],
    [
      "not a value",
      { not: "A" },
      { kind: "not", item: col("name", "eq", "A") },
    ],
    [
      "not an operator",
      { not: { in: ["A"] } },
      { kind: "not", item: col("name", "in", ["A"]) },
    ],
    ["gt", { gt: "A" }, col("name", "gt", "A")],
    ["gte", { gte: "A" }, col("name", "gte", "A")],
    ["lt", { lt: "A" }, col("name", "lt", "A")],
    ["lte", { lte: "A" }, col("name", "lte", "A")],
    ["like", { like: "A%" }, col("name", "like", "A%")],
    ["ilike", { ilike: "a%" }, col("name", "ilike", "a%")],
    ["contains on text", { contains: "50%" }, col("name", "ilike", "%50\\%%")],
    ["startsWith", { startsWith: "a_" }, col("name", "like", "a\\_%")],
    ["endsWith", { endsWith: "b" }, col("name", "like", "%b")],
    ["search with a string", { search: "acme" }, col("name", "fts", "acme")],
    [
      "search with a query object",
      { search: { query: "acme" } },
      col("name", "fts", "acme"),
    ],
    [
      "search with a config",
      { search: { query: "acme", config: "dutch" } },
      {
        kind: "column",
        column: "name",
        op: "fts",
        value: "acme",
        config: "dutch",
      },
    ],
    ["only undefined operands", { gt: undefined }, { kind: "and", items: [] }],
    [
      "several operators",
      { gt: "A", lt: "C", eq: undefined },
      { kind: "and", items: [col("name", "gt", "A"), col("name", "lt", "C")] },
    ],
  ])("%s", (_name, operand, expected) => {
    expect(ir.where(customers, { name: operand })).toEqual(expected);
  });

  it("matches json with contains", () => {
    expect(
      ir.where(customers, { metadata: { contains: { plan: "pro" } } }),
    ).toEqual(col("metadata", "contains", { plan: "pro" }));
  });

  it.each<[string, unknown, Condition]>([
    [
      "contains on an array",
      { contains: ["a"] },
      col("tags", "contains", ["a"]),
    ],
    ["hasEvery", { hasEvery: ["a", "b"] }, col("tags", "contains", ["a", "b"])],
    ["has", { has: "a" }, col("tags", "contains", ["a"])],
    ["hasSome", { hasSome: ["a"] }, col("tags", "overlaps", ["a"])],
    ["containedBy", { containedBy: ["a"] }, col("tags", "containedBy", ["a"])],
  ])("array %s", (_name, operand, expected) => {
    expect(ir.where(ledger, { tags: operand })).toEqual(expected);
  });

  it.each(["in", "notIn"])("rejects %s without an array", (op) => {
    expect(
      rejection(() => ir.where(customers, { name: { [op]: "A" } })),
    ).toMatchObject({
      message: `"${op}" on "name" needs an array`,
      table: "customers",
    });
  });
});

describe("IrBuilder.where relation filters", () => {
  it.each<[string, unknown, Condition]>([
    ["an empty to-many filter", {}, notesRelation("some", undefined)],
    [
      "undefined quantifiers",
      { some: undefined },
      notesRelation("some", undefined),
    ],
    [
      "some",
      { some: { body: "x" } },
      notesRelation("some", col("body", "eq", "x")),
    ],
    [
      "every",
      { every: { body: "x" } },
      notesRelation("every", col("body", "eq", "x")),
    ],
    [
      "several quantifiers",
      { some: { body: "x" }, none: null },
      {
        kind: "and",
        items: [
          notesRelation("some", col("body", "eq", "x")),
          notesRelation("none", undefined),
        ],
      },
    ],
  ])("to-many: %s", (_name, value, expected) => {
    expect(ir.where(customers, { notes: value })).toEqual(expected);
  });

  it.each<[string, unknown]>([
    ["a non-object", "x"],
    ["null", null],
  ])("rejects a to-many filter with %s", (_name, value) => {
    expect(
      rejection(() => ir.where(customers, { notes: value })),
    ).toMatchObject({
      message: 'Filter on to-many relation "notes" needs some, none or every',
      table: "customers",
    });
  });

  it("rejects an unknown quantifier", () => {
    expect(
      rejection(() => ir.where(customers, { notes: { any: {} } })),
    ).toMatchObject({
      message: 'Unknown quantifier "any" on relation "notes"',
    });
  });

  it.each<[string, unknown, Condition]>([
    ["null", null, organizationRelation("none", undefined)],
    ["is null", { is: null }, organizationRelation("none", undefined)],
    [
      "is",
      { is: { slug: "acme" } },
      organizationRelation("some", col("slug", "eq", "acme")),
    ],
    ["isNot null", { isNot: null }, organizationRelation("some", undefined)],
    [
      "isNot",
      { isNot: { slug: "acme" } },
      {
        kind: "not",
        item: organizationRelation("some", col("slug", "eq", "acme")),
      },
    ],
    [
      "is and isNot",
      { is: { slug: "a" }, isNot: { name: "b" } },
      {
        kind: "and",
        items: [
          organizationRelation("some", col("slug", "eq", "a")),
          {
            kind: "not",
            item: organizationRelation("some", col("name", "eq", "b")),
          },
        ],
      },
    ],
    [
      "undefined is and isNot",
      { is: undefined, isNot: undefined },
      organizationRelation("some", undefined),
    ],
    [
      "a direct filter",
      { slug: "acme" },
      organizationRelation("some", col("slug", "eq", "acme")),
    ],
    ["an empty filter", {}, organizationRelation("some", undefined)],
  ])("to-one: %s", (_name, value, expected) => {
    expect(ir.where(customers, { organization: value })).toEqual(expected);
  });
});

describe("IrBuilder.selection", () => {
  it("selects every column by default", () => {
    const selection = ir.selection(organizations, undefined, undefined);
    expect(selection).toEqual({
      columns: [
        { alias: "id", column: "id" },
        { alias: "name", column: "name" },
        { alias: "slug", column: "slug" },
        { alias: "createdAt", column: "created_at" },
        { alias: "updatedAt", column: "updated_at" },
      ],
      includes: [],
    });
  });

  it("casts and decodes codec columns", () => {
    expect(
      ir.selection(ledger, ["id", "amount", "bookedAt", "label"], undefined)
        .columns,
    ).toEqual([
      { alias: "id", column: "id", cast: "text", codec: "bigint" },
      { alias: "amount", column: "amount", cast: "text", codec: "string" },
      { alias: "bookedAt", column: "booked_at", codec: "date" },
      { alias: "label", column: "label" },
    ]);
  });

  it("builds includes with their options", () => {
    const selection = ir.selection(customers, ["id"], {
      organization: true,
      locations: false,
      contacts: undefined,
      notes: {
        select: ["id"],
        where: { body: "x" },
        orderBy: { createdAt: "desc" },
        limit: 3,
        required: true,
        include: { customer: { select: ["name"] } },
      },
      primaryContact: "yes",
    });
    expect(selection.includes).toEqual([
      {
        alias: "organization",
        relation: relation(customers, "organization"),
        target: organizations,
        selection: ir.selection(organizations, undefined, undefined),
        where: undefined,
        orderBy: [],
        limit: undefined,
        required: false,
      },
      {
        alias: "notes",
        relation: relation(customers, "notes"),
        target: notes,
        selection: {
          columns: [{ alias: "id", column: "id" }],
          includes: [
            {
              alias: "customer",
              relation: relation(notes, "customer"),
              target: customers,
              selection: {
                columns: [{ alias: "name", column: "name" }],
                includes: [],
              },
              where: undefined,
              orderBy: [],
              limit: undefined,
              required: false,
            },
          ],
        },
        where: col("body", "eq", "x"),
        orderBy: [{ column: "created_at", direction: "desc" }],
        limit: 3,
        required: true,
      },
      {
        alias: "primaryContact",
        relation: relation(customers, "primaryContact"),
        target: ir.table("contacts"),
        selection: ir.selection(ir.table("contacts"), undefined, undefined),
        where: undefined,
        orderBy: [],
        limit: undefined,
        required: false,
      },
    ]);
  });

  it("builds _count includes", () => {
    expect(
      ir.selection(customers, [], {
        _count: {
          notes: true,
          locations: { where: { city: "Delft" } },
          customerTags: false,
        },
      }).includes,
    ).toEqual([
      {
        alias: "_count_notes",
        relation: relation(customers, "notes"),
        target: notes,
        selection: { columns: [], includes: [] },
        where: undefined,
        orderBy: [],
        limit: undefined,
        required: false,
        count: "notes",
      },
      {
        alias: "_count_locations",
        relation: relation(customers, "locations"),
        target: ir.table("locations"),
        selection: { columns: [], includes: [] },
        where: col("city", "eq", "Delft"),
        orderBy: [],
        limit: undefined,
        required: false,
        count: "locations",
      },
    ]);
  });

  it("builds relation aggregate includes and skips empty ones", () => {
    expect(
      ir.selection(customers, [], {
        _max: {
          notes: { id: true, body: false },
          locations: { id: false },
          customerTags: false,
        },
      }).includes,
    ).toEqual([
      {
        alias: "_max_notes",
        relation: relation(customers, "notes"),
        target: notes,
        selection: {
          columns: [],
          includes: [],
          aggregate: {
            count: false,
            measures: [{ fn: "max", key: "id", alias: "id", column: "id" }],
          },
        },
        where: undefined,
        orderBy: [],
        limit: undefined,
        required: false,
        aggregate: { fn: "max", name: "notes" },
      },
    ]);
  });

  it.each<[string, unknown, string]>([
    [
      "a non-object include",
      ["notes"],
      '"include" on "customers" must be an object',
    ],
    [
      "a non-object _count",
      { _count: true },
      '"_count" on "customers" must map relations to true or { where }',
    ],
    [
      "_count of a to-one relation",
      { _count: { organization: true } },
      '"_count.organization" on "customers" needs a to-many relation',
    ],
    [
      "a non-object _sum",
      { _sum: true },
      '"_sum" on "customers" must map relations to columns',
    ],
    [
      "_sum of a to-one relation",
      { _sum: { organization: { id: true } } },
      '"_sum.organization" on "customers" needs a to-many relation',
    ],
    [
      "a non-object measure list",
      { _sum: { notes: true } },
      '"_sum.notes" on "notes" must map columns to true',
    ],
    [
      "_avg of a text column",
      { _avg: { notes: { body: true } } },
      '_avg needs a numeric column; "body" on "notes" is text',
    ],
  ])("rejects %s", (_name, include, message) => {
    expect(rejection(() => ir.selection(customers, [], include))).toMatchObject(
      { message },
    );
  });
});

describe("IrBuilder.aggregation", () => {
  it("groups and measures with codecs", () => {
    expect(
      ir.aggregation(ledger, {
        groupBy: ["label"],
        _count: true,
        _sum: { amount: true, total: false },
        _avg: { amount: true },
        _min: { bookedAt: true },
        _max: { id: true },
      }),
    ).toEqual({
      columns: [{ alias: "label", column: "label" }],
      includes: [],
      aggregate: {
        count: true,
        measures: [
          {
            fn: "sum",
            key: "_sum_amount",
            alias: "amount",
            column: "amount",
            cast: "text",
            codec: "string",
          },
          { fn: "avg", key: "_avg_amount", alias: "amount", column: "amount" },
          {
            fn: "min",
            key: "_min_bookedAt",
            alias: "bookedAt",
            column: "booked_at",
            codec: "date",
          },
          {
            fn: "max",
            key: "_max_id",
            alias: "id",
            column: "id",
            cast: "text",
            codec: "bigint",
          },
        ],
      },
    });
  });

  it("counts without grouping", () => {
    expect(ir.aggregation(customers, { _count: true })).toEqual({
      columns: [],
      includes: [],
      aggregate: { count: true, measures: [] },
    });
  });

  it.each<[string, Record<string, unknown>, string]>([
    [
      "a non-array groupBy",
      { groupBy: "status", _count: true },
      '"groupBy" on "customers" must be an array',
    ],
    [
      "no aggregate",
      { groupBy: ["status"], _count: false },
      'aggregate on "customers" needs _count, _sum, _avg, _min or _max',
    ],
    [
      "a non-object measure",
      { _min: "name" },
      '"_min" on "customers" must map columns to true',
    ],
    [
      "_sum of a text column",
      { _sum: { name: true } },
      '_sum needs a numeric column; "name" on "customers" is text',
    ],
  ])("rejects %s", (_name, args, message) => {
    expect(rejection(() => ir.aggregation(customers, args))).toMatchObject({
      message,
    });
  });
});

describe("IrBuilder.orderBy", () => {
  it.each<[string, unknown, unknown[]]>([
    ["nothing", undefined, []],
    ["a direction", { name: "asc" }, [{ column: "name", direction: "asc" }]],
    [
      "a list with options",
      [
        { name: { direction: "desc", nulls: "last" } },
        { createdAt: {} },
        { kvk: { nulls: "first" } },
      ],
      [
        { column: "name", direction: "desc", nulls: "last" },
        { column: "created_at", direction: "asc" },
        { column: "kvk", direction: "asc", nulls: "first" },
      ],
    ],
    [
      "unknown nulls",
      { name: { nulls: "middle" } },
      [{ column: "name", direction: "asc" }],
    ],
    [
      "skipped undefined specs",
      { name: undefined, kvk: "desc" },
      [{ column: "kvk", direction: "desc" }],
    ],
  ])("orders by %s", (_name, input, expected) => {
    expect(ir.orderBy(customers, input)).toEqual(expected);
  });

  it.each<[string, unknown, string]>([
    ["a string", "name", '"orderBy" on "customers" must be an object'],
    ["an invalid sort", { name: 1 }, 'Invalid sort for "name" on "customers"'],
  ])("rejects %s", (_name, input, message) => {
    expect(rejection(() => ir.orderBy(customers, input))).toMatchObject({
      message,
      table: "customers",
    });
  });
});

describe("IrBuilder.row", () => {
  it("maps app names to database names and encodes values", () => {
    expect(
      ir.row(customers, {
        name: "A",
        kvk: undefined,
        createdAt: new Date("2026-01-01T00:00:00.000Z"),
        primaryContactId: null,
      }),
    ).toEqual({
      name: "A",
      created_at: "2026-01-01T00:00:00.000Z",
      primary_contact_id: null,
    });
  });

  it("allows a column updates can't set in an insert, and the reverse", () => {
    expect(ir.row(ledger, { locked: "x" }, "insert")).toEqual({ locked: "x" });
    expect(ir.row(ledgerView, { label: "x" }, "update")).toEqual({
      label: "x",
    });
  });

  it.each<[string, TableMeta, unknown, "insert" | "update", string]>([
    [
      "a non-object",
      customers,
      [],
      "insert",
      'Row for "customers" must be an object',
    ],
    [
      "an unknown column",
      customers,
      { nope: 1 },
      "insert",
      'Unknown column "nope" on "customers"',
    ],
    [
      "a generated column",
      ledger,
      { total: 1 },
      "insert",
      '"total" on "ledger" is read-only (generated) and can\'t be set in an insert',
    ],
    [
      "an identity always column",
      ledger,
      { id: 1 },
      "update",
      '"id" on "ledger" is read-only (identity always) and can\'t be set in an update',
    ],
    [
      "a non-updatable column",
      ledger,
      { locked: "x" },
      "update",
      '"locked" on "ledger" is read-only and can\'t be set in an update',
    ],
    [
      "a non-insertable view column",
      ledgerView,
      { label: "x" },
      "insert",
      '"label" on "ledgerView" is read-only and can\'t be set in an insert',
    ],
  ])("rejects %s", (_name, target, input, mode, message) => {
    expect(rejection(() => ir.row(target, input, mode))).toMatchObject({
      message,
      table: target.key,
    });
  });
});

describe("IrBuilder.uniqueKey", () => {
  it.each<[string, unknown, Condition]>([
    [
      "the primary key",
      { id: "c1" },
      { kind: "and", items: [col("id", "eq", "c1")] },
    ],
    [
      "a unique key with a null",
      { id: undefined, organizationId: "o1", kvk: null },
      {
        kind: "and",
        items: [col("organization_id", "eq", "o1"), col("kvk", "is", null)],
      },
    ],
  ])("matches %s", (_name, input, expected) => {
    expect(ir.uniqueKey(customers, input)).toEqual(expected);
  });

  it.each<[string, TableMeta, unknown, string]>([
    [
      "a non-object",
      customers,
      "c1",
      '"where" on "customers" must be an object',
    ],
    [
      "an incomplete key",
      customers,
      { organizationId: "o1" },
      'findUnique on "customers" needs one complete unique key: { id }, { organizationId, kvk }',
    ],
    [
      "a table without keys",
      ledgerView,
      { label: "x" },
      'findUnique on "ledgerView" needs one complete unique key: ',
    ],
  ])("rejects %s", (_name, target, input, message) => {
    expect(rejection(() => ir.uniqueKey(target, input))).toMatchObject({
      message,
      table: target.key,
    });
  });
});

describe("IrBuilder.primaryKey", () => {
  const customerTags = ir.table("customerTags");

  it.each<[string, unknown, Condition]>([
    ["a value", "c1", col("id", "eq", "c1")],
    ["an object with the key", { id: "c1" }, col("id", "eq", "c1")],
    ["an object without the key", { other: 1 }, col("id", "eq", { other: 1 })],
  ])("matches %s", (_name, id, expected) => {
    expect(ir.primaryKey(customers, id)).toEqual(expected);
  });

  it("encodes a bigint key", () => {
    expect(ir.primaryKey(ledger, 12n)).toEqual(col("id", "eq", "12"));
  });

  it("matches a composite key", () => {
    expect(
      ir.primaryKey(customerTags, { customerId: "c1", tagId: "t1" }),
    ).toEqual({
      kind: "and",
      items: [col("customer_id", "eq", "c1"), col("tag_id", "eq", "t1")],
    });
  });

  it.each<[string, TableMeta, unknown, string]>([
    [
      "a table without a primary key",
      ledgerView,
      "x",
      'Table "ledgerView" has no primary key',
    ],
    [
      "a scalar for a composite key",
      customerTags,
      "c1",
      'Table "customerTags" has a composite key; pass { customerId, tagId }',
    ],
  ])("rejects %s", (_name, target, id, message) => {
    expect(rejection(() => ir.primaryKey(target, id))).toMatchObject({
      message,
      table: target.key,
    });
  });
});
