import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { tableSchema } from "../../src/core/table-schema-object.ts";
import {
  resultSchema,
  specResultSchema,
} from "../../src/result-schema/index.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { registerRpcReturn } from "../../src/schema/rpc-returns.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = createSupabase(schema);

function issues(schema: StandardSchemaV1, value: unknown): string[] {
  const result = schema["~standard"].validate(value);

  if (result instanceof Promise) {
    throw new TypeError("expected a sync result");
  }

  return result.issues?.map((issue) => issue.message) ?? [];
}

function value(schema: StandardSchemaV1, input: unknown): unknown {
  const result = schema["~standard"].validate(input);

  if (result instanceof Promise) {
    throw new TypeError("expected a sync result");
  }

  if (result.issues) {
    throw new Error(result.issues.map((issue) => issue.message).join("; "));
  }

  return result.value;
}

const id = "00000000-0000-4000-8000-000000000001";

describe("resultSchema", () => {
  const page = defineReadSet(betterSupabase, "result_page", {}, (s) => ({
    names: s.customers.list({ select: ["id", "name", "status"] }),
    one: s.customers.get(
      { where: { id } },
      { select: ["id", "name", "status"] },
    ),
    total: s.customers.count(),
    notes: s.customers.list({
      select: ["id"],
      include: { notes: { select: ["id"] }, _count: { notes: true } },
    }),
  }));

  const checked = resultSchema(page);

  it("checks columns, nested includes and counts", () => {
    const row = {
      names: [{ id, name: "Acme", status: "active" }],
      one: { id, name: "Acme", status: "lead" },
      total: 2,
      notes: [{ id, notes: [{ id: 1 }], _count: { notes: 1 } }],
    };

    expect(
      value(checked, { ...row, one: { ...row.one, leaked: true }, extra: 1 }),
    ).toEqual(row);
    expect(
      issues(checked, {
        ...row,
        names: [{ id, name: "Acme", status: "nope" }],
      }),
    ).toEqual(['Expected one of "lead", "active", "archived"']);
    expect(issues(checked, { ...row, total: 1.5 })).toEqual([
      "Expected an integer",
    ]);
    expect(
      issues(checked, {
        ...row,
        notes: [{ id, notes: {}, _count: { notes: 1 } }],
      }),
    ).toEqual(["Expected an array"]);
  });

  it("rejects unknown keys when asked", () => {
    const strict = resultSchema(page, { unknownKeys: "reject" });

    expect(
      issues(strict, { names: [], one: null, total: 0, notes: [], leaked: 1 }),
    ).toEqual(["Unexpected key"]);
  });
});

describe("specResultSchema", () => {
  it("validates a page and an aggregate", () => {
    const paged = specResultSchema(
      schema.meta,
      betterSupabase.spec.customers.page({ select: ["id"], page: 1, size: 10 }),
    );

    expect(
      value(paged, {
        items: [{ id }],
        page: { number: 1, size: 10, total: null, pages: null, hasMore: false },
      }),
    ).toMatchObject({ items: [{ id }] });

    const grouped = specResultSchema(
      schema.meta,
      betterSupabase.spec.notes.aggregate({
        groupBy: ["kind"],
        _count: true,
        _sum: { id: true },
      }),
    );

    expect(
      value(grouped, [{ kind: "call", _count: 2, _sum: { id: null } }]),
    ).toEqual([{ kind: "call", _count: 2, _sum: { id: null } }]);
  });

  it("decodes codecs and keeps snake names", () => {
    const coded = defineSchema({
      ...schema.meta,
      tables: {
        ...schema.meta.tables,
        notes: {
          ...schema.meta.tables["notes"]!,
          columns: {
            ...schema.meta.tables["notes"]!.columns,
            createdAt: {
              ...schema.meta.tables["notes"]!.columns["createdAt"]!,
              codec: "instant",
            },
          },
        },
      },
    });

    const at = Temporal.Instant.from("2026-01-01T00:00:00Z");

    const spec = specResultSchema(
      coded.meta,
      betterSupabase.spec.notes.list({ select: ["createdAt"] }),
    );

    expect(value(spec, [{ createdAt: at }])).toEqual([{ createdAt: at }]);
    expect(issues(spec, [{ createdAt: "2026-01-01T00:00:00Z" }])).toEqual([
      "Expected a Temporal.Instant",
    ]);

    const snake = defineSchema({
      version: 1,
      casing: "snake",
      enums: {},
      functions: {},
      tables: {
        notes: {
          key: "notes",
          name: "notes",
          schema: "public",
          kind: "table",
          columns: { created_at: { db: "created_at", type: "timestamptz" } },
          primaryKey: ["created_at"],
          uniqueKeys: {},
          relations: {},
          flags: {},
        },
      },
    });

    const snakeDb = createSupabase(snake);
    const snakeNotes = snakeDb.spec["notes"];

    if (snakeNotes === undefined) {
      throw new Error("notes");
    }

    expect(
      value(
        specResultSchema(
          snake.meta,
          snakeNotes.list({ select: ["created_at"] } as unknown as Parameters<
            typeof snakeNotes.list
          >[0]),
        ),
        [{ created_at: "2026-01-01T00:00:00Z" }],
      ),
    ).toEqual([{ created_at: "2026-01-01T00:00:00Z" }]);
  });
});

const withBindings = createSupabase(
  defineSchema({
    ...schema.meta,
    functions: {
      ...schema.meta.functions,
      record_summary: {
        name: "record_summary",
        schema: "public",
        args: [
          { name: "subject_type", type: "text" },
          { name: "subject_id", type: "text" },
        ],
        returns: "jsonb",
        returnsSet: false,
        volatility: "stable",
      },
      labelled_summary: {
        name: "labelled_summary",
        schema: "public",
        args: [],
        returns: "jsonb",
        returnsSet: false,
        volatility: "stable",
      },
    },
  }),
);

describe("gates, functions and lazy tables", () => {
  it("allows null for a gated entry", () => {
    const gated = defineReadSet(
      betterSupabase,
      "result_gated",
      {},
      (s, _p, auth) => ({
        total: s.when(auth.can("customer.read"), s.customers.count()),
      }),
    );

    const checked = resultSchema(gated);

    expect(value(checked, { total: null })).toEqual({ total: null });
    expect(value(checked, { total: 3 })).toEqual({ total: 3 });
  });

  it("checks a returns table by its columns, and a registered return by its schema", () => {
    const reads = defineReadSet(withBindings, "result_fns", {}, (s) => ({
      orgs: s.$fn["my_organizations"]!({}),
      summary: s.record("customer", id),
      labelled: s.$fn["labelled_summary"]!({}),
    }));

    const checked = resultSchema(reads);

    const row = {
      id,
      lastUsedAt: null,
      name: null,
      plan: null,
      role: null,
      slug: null,
    };

    expect(
      value(checked, {
        orgs: [row],
        summary: { anything: true },
        labelled: { anything: true },
      }),
    ).toEqual({
      orgs: [row],
      summary: { anything: true },
      labelled: { anything: true },
    });
    expect(issues(checked, { orgs: [1], summary: 1, labelled: 1 })).toEqual([
      "Expected an object",
    ]);
    expect(
      issues(checked, { orgs: [{ id }], summary: 1, labelled: 1 }).length,
    ).toBeGreaterThan(0);

    registerRpcReturn(
      "labelled_summary",
      tableSchema({ fields: { title: { kind: "string" } } }),
    );

    const registered = resultSchema(reads);

    expect(
      value(registered, {
        orgs: [],
        summary: { anything: true },
        labelled: { title: "Acme", extra: 1 },
      }),
    ).toEqual({
      orgs: [],
      summary: { anything: true },
      labelled: { title: "Acme" },
    });
    expect(
      issues(registered, {
        orgs: [],
        summary: { anything: true },
        labelled: { title: 1 },
      }),
    ).toEqual(["Expected a string"]);
  });

  it("fails when the table is not loaded", () => {
    const lazy = createSupabase(
      defineSchema({
        ...schema.meta,
        tables: {},
        lazyTables: true,
        tableGetters: {
          customers: () => Promise.resolve(schema.meta.tables["customers"]!),
        },
      }),
    );

    const set = defineReadSet(lazy, "result_lazy", {}, (s) => ({
      names: s["customers"]!.list({ select: ["id"] } as unknown as Parameters<
        NonNullable<(typeof s)["customers"]>["list"]
      >[0]),
    }));

    expect(() => resultSchema(set)).toThrow(/customers is not loaded/);
  });
});
