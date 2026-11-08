import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";
import type { SchemaMeta } from "../../src/schema/types.ts";

import { bindClient, memoryEngine } from "../../src/client/index.ts";
import { createSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { defineListQuery } from "../../src/list/list-query.ts";
import { defineSchema, defineTable } from "../../src/schema/define.ts";
import meta from "../fixtures/generated-camel.meta.js";

const customers = defineTable(meta.tables["customers"] as never);
const contacts = defineTable(meta.tables["contacts"] as never);

const lazy: SchemaMeta = {
  version: 1,
  casing: "camel",
  lazyTables: true,
  tables: {},
  enums: {},
  functions: {},
};

describe("defineTable", () => {
  it("returns the metadata it was given", () => {
    expect(customers.key).toBe("customers");
    expect(customers.name).toBe("customers");
  });
});

describe("a schema with lazyTables", () => {
  it("copies its tables, so registering never changes a module's constant", () => {
    const shared = { ...lazy, tables: {} };
    const one = defineSchema(shared);
    const two = defineSchema(shared);
    createSupabase(one).registerTable(customers);

    expect(Object.keys(one.meta.tables)).toEqual(["customers"]);
    expect(Object.keys(two.meta.tables)).toEqual([]);
    expect(Object.keys(shared.tables)).toEqual([]);
  });

  it("registers a table once and leaves the others out", () => {
    const app = createSupabase(defineSchema(lazy));
    app.registerTable(customers);
    app.registerTable(customers);

    expect(Object.keys(app.meta.tables)).toEqual(["customers"]);
  });

  it("refuses a table on a schema that lists its tables", () => {
    const app = createSupabase(defineSchema(meta));

    expect(() => {
      app.registerTable(customers);
    }).toThrow(/lists its tables/);
  });
});

describe("client.table", () => {
  const supabase = {} as unknown as SupabaseClient;

  const engine = {
    ...memoryEngine(),
    connect: (): Executor => ({
      name: "local",
      execute: () => Promise.resolve(ok({ rows: [], count: 5 })),
    }),
  };

  it("exposes the query options of a table registered after the client was built", () => {
    const app = createSupabase(defineSchema(lazy));

    const client = bindClient(app, supabase);

    expect(client.queries).not.toHaveProperty("customers");
    client.table(customers);

    const queries: Record<string, { list?: unknown } | undefined> =
      client.queries;

    expect(typeof queries["customers"]?.list).toBe("function");
  });

  it("registers the table, also on a `db` made before it", async () => {
    const bound = bindClient(createSupabase(defineSchema(lazy)), supabase, {
      engine,
    });

    const before = bound.db;

    expect(Object.keys(bound.betterSupabase.meta.tables)).toEqual([]);

    const repository = bound.table(customers);

    expect(Object.keys(bound.betterSupabase.meta.tables)).toEqual([
      "customers",
    ]);
    expect(await repository.count().orThrow()).toBe(5);
    expect(bound.table(customers as never)).toBe(repository);
    expect("customers" in before).toBe(true);
    expect("contacts" in before).toBe(false);
    bound.dispose();
  });

  it("reads db.<table> when the schema lists its tables", () => {
    const bound = bindClient(createSupabase(defineSchema(meta)), supabase, {
      engine,
    });

    expect(bound.table(customers as never)).toBe(bound.db["customers"]);
    bound.dispose();
  });

  it("registers a table on its own, without the others", () => {
    const bound = bindClient(createSupabase(defineSchema(lazy)), supabase);
    bound.table(contacts);

    expect(Object.keys(bound.betterSupabase.meta.tables)).toEqual(["contacts"]);
    bound.dispose();
  });
});

describe("defineListQuery over a table module", () => {
  it("registers the module with a lazy definition", () => {
    const app = createSupabase(defineSchema(lazy));

    const list = defineListQuery(
      app,
      customers as never,
      {
        search: ["name"],
        sorts: { name: [{ name: "asc" }, { id: "asc" }] },
        defaultSort: "name",
      } as never,
    );

    expect(list).toBeDefined();
    expect(Object.keys(app.meta.tables)).toEqual(["customers"]);
  });
});
