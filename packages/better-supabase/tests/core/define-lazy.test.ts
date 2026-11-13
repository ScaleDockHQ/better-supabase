import { describe, expect, it, vi } from "vitest";

import type { Executor } from "../../src/core/executor.ts";
import type { Operation } from "../../src/ir/types.ts";
import type { SchemaMeta } from "../../src/schema/types.ts";

import { ensureFunctions, lazyRepository } from "../../src/core/define-lazy.ts";
import { createSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

function freshMeta(): SchemaMeta {
  return { ...createSupabase(schema).meta };
}

function loadedTable(
  meta: SchemaMeta,
): SchemaMeta["tables"][string] & { readonly key: string } {
  const [first] = Object.values(meta.tables);

  if (!first) {
    throw new Error("the fixture has no table");
  }

  return { ...first, key: "lazyItems" };
}

type Method = (...args: unknown[]) => Promise<unknown>;

// SAFETY: lazyRepository answers every string key with a method.
const call = (
  repo: Record<string, unknown>,
  name: string,
  ...args: unknown[]
) => (repo[name] as Method)(...args);

describe("lazyRepository", () => {
  it("loads the table once and runs the method on the built repository", async () => {
    const meta = freshMeta();
    const table = loadedTable(meta);
    const load = vi.fn(() => Promise.resolve(table));
    const register = vi.fn();
    const list = vi.fn((...args: unknown[]) => Promise.resolve(ok(args)));
    const build = vi.fn(() => ({ list }));
    const repo = lazyRepository(meta, {}, "lazyItems", load, build, register);

    const first = await call(repo, "list", 1);
    const second = await call(repo, "list", 2);

    expect(first).toEqual(ok([1]));
    expect(second).toEqual(ok([2]));
    expect(load).toHaveBeenCalledOnce();
    expect(register).toHaveBeenCalledExactlyOnceWith(table);
  });

  it("is not thenable and ignores symbol keys", () => {
    const meta = freshMeta();

    const repo = lazyRepository(
      meta,
      {},
      "lazyItems",
      () => Promise.resolve(loadedTable(meta)),
      () => ({}),
      vi.fn(),
    );

    expect(repo["then"]).toBeUndefined();
    expect(repo[Symbol.iterator as never]).toBeUndefined();
  });

  it("reports a name that is not a repository method", async () => {
    const meta = freshMeta();

    const repo = lazyRepository(
      meta,
      {},
      "lazyItems",
      () => Promise.resolve(loadedTable(meta)),
      () => ({ size: 3 }),
      vi.fn(),
    );

    const result = await call(repo, "size");

    expect(result).toMatchObject({
      ok: false,
      error: { message: "better-supabase: lazyItems.size is not a method" },
    });
  });

  it("retries a load that failed", async () => {
    const meta = freshMeta();
    const table = loadedTable(meta);

    const load = vi
      .fn<() => Promise<typeof table>>()
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValue(table);

    const repo = lazyRepository(
      meta,
      {},
      "lazyItems",
      load,
      () => ({ list: () => Promise.resolve(ok("rows")) }),
      vi.fn(),
    );

    expect(await call(repo, "list")).toMatchObject({
      ok: false,
      error: { message: "offline" },
    });
    expect(await call(repo, "list")).toEqual(ok("rows"));
    expect(load).toHaveBeenCalledTimes(2);
  });
});

describe("ensureFunctions", () => {
  const fn = {
    name: "lazy_fn",
    schema: "public",
    args: [],
    returns: "int4",
    returnsSet: false,
    volatility: "stable",
  } as const;

  it("loads the functions once and installs them", async () => {
    const loadFunctions = vi.fn(() => Promise.resolve({ lazyFn: fn }));
    const meta: SchemaMeta = { ...freshMeta(), functions: {}, loadFunctions };

    await Promise.all([ensureFunctions(meta), ensureFunctions(meta)]);
    await ensureFunctions(meta);

    expect(loadFunctions).toHaveBeenCalledOnce();
    expect(meta.functions["lazyFn"]).toEqual(fn);
  });

  it("does nothing without a loader", async () => {
    const meta: SchemaMeta = { ...freshMeta(), functions: {} };

    await ensureFunctions(meta);

    expect(meta.functions).toEqual({});
  });
});

describe("a lazy schema", () => {
  type Call = (db: Record<string, Record<string, Method>>) => Promise<unknown>;

  function run(meta: SchemaMeta, call: Call): Promise<Operation[]> {
    const ops: Operation[] = [];

    const executor: Executor = {
      name: "stub",
      execute: (op) => {
        ops.push(op);

        return Promise.resolve(ok({ rows: [], count: 0 }));
      },
    };

    // SAFETY: the test reads the tables of a generic db by name.
    const db = createSupabase(defineSchema(meta)).connect(
      executor,
    ) as unknown as Record<string, Record<string, Method>>;

    return call(db).then((result) => {
      expect(result).toMatchObject({ ok: true });

      return ops;
    });
  }

  function lazyMeta(): { meta: SchemaMeta; loaded: string[] } {
    const loaded: string[] = [];

    const tableLoaders = Object.fromEntries(
      Object.entries(schema.meta.tables).map(([key, table]) => [
        key,
        () => {
          loaded.push(key);

          return Promise.resolve(table);
        },
      ]),
    );

    return {
      meta: { ...schema.meta, tables: {}, lazyTables: true, tableLoaders },
      loaded,
    };
  }

  const cases: [string, Call, string[]][] = [
    [
      "an include",
      (db) => db["customers"]!["list"]!({ include: { primaryContact: true } }),
      ["customers", "contacts"],
    ],
    [
      "a nested include",
      (db) =>
        db["customers"]!["list"]!({
          include: { locations: { include: { organization: true } } },
        }),
      ["customers", "locations", "organizations"],
    ],
    [
      "a relation filter",
      (db) =>
        db["customers"]!["list"]!({
          where: { notes: { some: { kind: "call" } } },
        }),
      ["customers", "notes"],
    ],
    [
      "a count across a relation",
      (db) =>
        db["customers"]!["count"]!({
          where: { organization: { is: { slug: "acme" } } },
        }),
      ["customers", "organizations"],
    ],
    [
      "an orderBy across a relation",
      (db) =>
        db["locations"]!["list"]!({ orderBy: { customer: { name: "desc" } } }),
      ["locations", "customers"],
    ],
  ];

  it.each(cases)(
    "loads the tables %s reaches in a fresh process, and builds the eager query",
    async (_name, call, tables) => {
      const { meta, loaded } = lazyMeta();

      const lazyOps = await run(meta, call);
      const eagerOps = await run(schema.meta, call);

      expect(loaded.toSorted()).toEqual(tables.toSorted());
      expect(lazyOps).toEqual(eagerOps);
    },
  );

  it("loads a relation target on a later call to an already loaded table", async () => {
    const { meta, loaded } = lazyMeta();
    const app = createSupabase(defineSchema(meta));

    const db = app.connect({
      name: "stub",
      execute: () => Promise.resolve(ok({ rows: [], count: 0 })),
    }) as unknown as Record<string, Record<string, Method>>;

    expect(await db["customers"]!["list"]!()).toMatchObject({ ok: true });
    expect(loaded).toEqual(["customers"]);

    expect(
      await db["customers"]!["list"]!({ include: { primaryContact: true } }),
    ).toMatchObject({ ok: true });
    expect(loaded).toEqual(["customers", "contacts"]);
  });

  it("loads the result table of $rpc in a fresh process and returns app keys", async () => {
    const { meta, loaded } = lazyMeta();

    const fn = {
      name: "ensure_customer",
      schema: "public",
      args: [],
      returns: "customers",
      returnsSet: false,
      volatility: "volatile",
      result: { table: "customers" },
    } as const;

    const app = createSupabase(
      defineSchema({ ...meta, functions: { ensure_customer: fn } }),
    );

    const db = app.connect({
      name: "stub",
      execute: () => Promise.resolve(ok({ rows: [], count: 0 })),
      rpc: () => Promise.resolve(ok({ id: "c1", primary_contact_id: "p1" })),
    }) as unknown as { $rpc: (name: string) => Promise<unknown> };

    const first = await db.$rpc("ensure_customer");
    const second = await db.$rpc("ensure_customer");

    expect(first).toEqual(ok({ id: "c1", primaryContactId: "p1" }));
    expect(second).toEqual(first);
    expect(loaded).toEqual(["customers"]);
  });
});
