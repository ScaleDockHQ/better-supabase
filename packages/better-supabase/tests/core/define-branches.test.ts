import { describe, expect, it, onTestFinished, vi } from "vitest";

import type { ExecuteResult, Executor } from "../../src/core/executor.ts";
import type { Result } from "../../src/core/result.ts";
import type { Operation } from "../../src/ir/types.ts";

import { createSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { err, ok } from "../../src/core/result.ts";
import { provideTemporal } from "../../src/core/temporal.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = createSupabase(schema);

function answer(op: Operation): Result<ExecuteResult> {
  return ok({
    rows: op.kind === "select" && op.head ? [] : [{ id: op.table.key }],
    count: 1,
  });
}

describe("definition clock", () => {
  it("reads the clock from the temporal option when no now is given", async () => {
    const fixed = Temporal.Instant.from("2026-03-04T05:06:07Z");

    const injected = {
      ...Temporal,
      Now: { ...Temporal.Now, instant: () => fixed },
      // SAFETY: the spread keeps every namespace member; only Now.instant is replaced.
    };

    onTestFinished(() => {
      provideTemporal(undefined);
    });

    const seen: Temporal.Instant[] = [];

    const clock = definePlugin({
      name: "clock",
      transformQuery: (op, args) => {
        seen.push(args.now());

        return op;
      },
    });

    await createSupabase(schema, { temporal: injected })
      .use(clock)
      .connect({ name: "fake", execute: async (op) => answer(op) })
      .tags.count();
    expect(seen).toEqual([fixed]);
  });
});

describe("use() with a schema extension", () => {
  it("replaces only the extension of the same name and keeps other plugins", () => {
    const keep = definePlugin({ name: "keep" });
    const other = definePlugin({ name: "other" });
    const first = createSupabase(schema).use(keep).use(other);

    expect(first.plugins.map((plugin) => plugin.name)).toEqual(
      expect.arrayContaining(["keep", "other"]),
    );
  });
});

describe("$many over an executor with batch", () => {
  const overview = defineReadSet(
    betterSupabase,
    "branch_overview",
    {},
    (s) => ({
      total: s.customers.count(),
      byStatus: s.$fn.customers_by_status({ p_limit: 1, p_status: "active" }),
    }),
  );

  const external = defineReadSet(
    betterSupabase,
    "branch_external",
    {},
    (s) => ({
      total: s.customers.count(),
      // SAFETY: a function outside the schema metadata names its own schema.
      outside: {
        v: 1,
        kind: "function",
        name: "outside_fn",
        args: {},
        schema: "extras",
      } as never,
    }),
  );

  it("calls function entries through $rpc and merges the results", async () => {
    const calls: { name: string; schema: string }[] = [];

    const executor: Executor = {
      name: "fake",
      execute: async (op) => answer(op),
      batch: async (ops) => ops.map(answer),
      rpc: async (name, _args, context) => {
        calls.push({ name, schema: context.schema });

        return ok([]);
      },
    };

    const result = await betterSupabase
      .connect(executor)
      .$many(overview, {}, { signal: new AbortController().signal });

    expect(result.ok && result.data.byStatus).toEqual([]);
    expect(calls.map((call) => call.name)).toEqual(["customers_by_status"]);
  });

  it("passes the function's own schema and signal", async () => {
    const calls: { name: string; schema: string; signal?: AbortSignal }[] = [];

    const executor: Executor = {
      name: "fake",
      execute: async (op) => answer(op),
      batch: async (ops) => ops.map(answer),
      rpc: async (name, _args, context) => {
        calls.push({
          name,
          schema: context.schema,
          ...(context.signal ? { signal: context.signal } : {}),
        });

        return ok([]);
      },
    };

    const controller = new AbortController();

    await betterSupabase
      .connect(executor)
      .$many(external, {}, { signal: controller.signal });
    expect(calls).toHaveLength(1);
    expect(calls[0]?.schema).toBe("extras");
    expect(calls[0]?.signal).toBeDefined();
  });

  it("returns the error of a failing function entry", async () => {
    const executor: Executor = {
      name: "fake",
      execute: async (op) => answer(op),
      batch: async (ops) => ops.map(answer),
      rpc: async () => err(dbError("forbidden", "denied")),
    };

    const result = await betterSupabase.connect(executor).$many(overview, {});

    expect(!result.ok && result.error.kind).toBe("forbidden");
  });

  it("returns the error of a failing table read", async () => {
    const executor: Executor = {
      name: "fake",
      execute: async () => err(dbError("timeout", "slow")),
      batch: async (ops) => ops.map(() => err(dbError("timeout", "slow"))),
      rpc: async () => ok([]),
    };

    const result = await betterSupabase.connect(executor).$many(overview, {});

    expect(!result.ok && result.error.kind).toBe("timeout");
  });
});

describe("$many decoding a PostgREST read set", () => {
  const single = defineReadSet(betterSupabase, "branch_single", {}, (s) => ({
    only: s.customers.get({ where: { name: "Acme" } }),
    total: s.customers.count(),
  }));

  const withFunction = defineReadSet(
    betterSupabase,
    "branch_function",
    {},
    (s) => ({
      byStatus: s.$fn.customers_by_status({ p_limit: 1, p_status: "active" }),
    }),
  );

  const ghost = defineReadSet(betterSupabase, "branch_ghost", {}, (s) => ({
    // SAFETY: a function outside the schema metadata names its own schema.
    outside: {
      v: 1,
      kind: "function",
      name: "outside_fn",
      args: {},
      schema: "extras",
    } as never,
    total: s.customers.count(),
  }));

  it("fails when a single entry matched several rows", async () => {
    const { client } = capturingClient(() => ({
      body: {
        only: { rows: [{ id: "a" }, { id: "b" }], count: null },
        total: { rows: [], count: 2 },
      },
    }));

    const result = await betterSupabase.connect(client).$many(single, {});

    expect(!result.ok && result.error.kind).toBe("multiple_rows");
  });

  it("fails when a single entry matched nothing", async () => {
    const { client } = capturingClient(() => ({
      body: { only: { rows: [], count: null }, total: { rows: [], count: 0 } },
    }));

    const result = await betterSupabase.connect(client).$many(single, {});

    expect(!result.ok && result.error.kind).toBe("not_found");
  });

  it("explains a function entry the generated function did not return", async () => {
    const { client } = capturingClient(() => ({ body: {} }));

    const result = await betterSupabase.connect(client).$many(withFunction, {});

    expect(!result.ok && result.error.message).toMatch(
      /returned no "byStatus"\. Run `better-supabase gen`/,
    );
  });

  it("decodes a function outside the schema metadata as it came", async () => {
    const { client } = capturingClient(() => ({
      body: { outside: [{ some_column: 1 }], total: { rows: [], count: 2 } },
    }));

    const result = await betterSupabase.connect(client).$many(ghost, {});

    expect(result.ok && result.data.total).toBe(2);
  });

  it("treats a missing payload as no entries", async () => {
    const { client } = capturingClient(() => ({ body: null }));

    const result = await betterSupabase.connect(client).$many(single, {});

    expect(result.ok).toBe(false);
  });
});

describe("cache adapters", () => {
  it("logs a synchronous failure and a rejected promise, never throws", async () => {
    const error = vi.fn();
    const logger = { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error };
    const definition = createSupabase(schema, { logger });

    const stopSync = definition.cache({
      name: "sync",
      invalidate: () => {
        throw new Error("boom");
      },
    });

    const stopAsync = definition.cache({
      name: "async",
      invalidate: () => Promise.reject(new Error("later")),
    });

    await definition
      .connect({ name: "fake", execute: async (op) => answer(op) })
      // SAFETY: the fake executor ignores the row, so the test omits the required columns.
      .tags.create({ name: "x" } as never);
    await Promise.resolve();
    stopSync();
    stopAsync();

    const messages = error.mock.calls.map((call) => String(call[0]));

    expect(messages).toContain('cache adapter "sync" failed');
    expect(messages).toContain('cache adapter "async" failed');
  });
});

describe("definition accessors", () => {
  const plain = {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value: unknown) => ({ value }),
    },
  } as const;

  it("exposes the claims and user metadata schemas", () => {
    expect(betterSupabase.claimsSchema).toBeUndefined();
    expect(betterSupabase.userMetadataSchema).toBeUndefined();
    expect(betterSupabase.claims(plain).claimsSchema).toBe(plain);
    expect(betterSupabase.userMetadata(plain).userMetadataSchema).toBe(plain);
  });

  it("connects with plugins that do not wrap the executor", async () => {
    const quiet = definePlugin({ name: "quiet" });

    const result = await betterSupabase
      .use(quiet)
      .connect({ name: "fake", execute: async (op) => answer(op) })
      .tags.count();

    expect(result.ok).toBe(true);
  });

  it("refuses $storage on an executor without storage", () => {
    const db = betterSupabase.connect({
      name: "fake",
      execute: async (op) => answer(op),
    });

    expect(() => db.$storage).toThrow(/db\.\$storage needs a client/);
  });
});

describe("connection runtime slot", () => {
  it("names the entries to import when no runtime is installed", () => {
    const slot = Symbol.for("better-supabase.connection-runtime");
    const host = globalThis as Record<symbol, unknown>;
    const installed = host[slot];

    host[slot] = undefined;

    try {
      // SAFETY: the call throws before it reads the executor.
      expect(() => createSupabase(schema).connect({} as never)).toThrow(
        /needs the connection runtime/,
      );
    } finally {
      host[slot] = installed;
    }
  });

  it("registers a lazy table before any db is connected", () => {
    const slot = Symbol.for("better-supabase.connection-runtime");
    const host = globalThis as Record<symbol, unknown>;
    const installed = host[slot];
    const { tags, ...rest } = schema.meta.tables;

    if (!tags) {
      throw new Error("the fixture has no tags table");
    }

    const lazy = createSupabase(
      defineSchema({ ...schema.meta, tables: rest, lazyTables: true }),
    );

    host[slot] = undefined;

    try {
      lazy.registerTable({ ...tags, key: "lazyTags" });
    } finally {
      host[slot] = installed;
    }

    expect(Object.keys(lazy.meta.tables)).toContain("lazyTags");
  });
});

describe("tables the server loads on first use", () => {
  const { tags, ...rest } = schema.meta.tables;

  if (!tags) {
    throw new Error("the fixture has no tags table");
  }

  const load = vi.fn(() => Promise.resolve({ ...tags, key: "lazyTags" }));

  const lazy = createSupabase(
    defineSchema({
      ...schema.meta,
      tables: rest,
      lazyTables: true,
      tableLoaders: { lazyTags: load },
    }),
  );

  const executor: Executor = {
    name: "stub",
    execute: (op) => Promise.resolve(answer(op)),
  };

  it("lists the loader keys beside the loaded tables when a name is unknown", () => {
    expect(() => lazy.connect(executor).$table("nope")).toThrow(
      /unknown table "nope"\. Known: .*lazyTags/u,
    );
  });

  it("runs a method once its table module has loaded", async () => {
    const result = await lazy.connect(executor).$table("lazyTags").count();

    expect(result.error).toBeNull();
    expect(load).toHaveBeenCalledOnce();
  });
});

describe("$decodeReadSet", () => {
  const set = defineReadSet(
    betterSupabase,
    "chrome",
    { params: { organizationId: "uuid" } },
    (s, p) => ({ tag: s.tags.get(p.organizationId, { select: ["id"] }) }),
  );

  const executor: Executor = {
    name: "stub",
    execute: (op) => Promise.resolve(answer(op)),
  };

  const db = betterSupabase.connect(executor);
  const values = { organizationId: "o1" };

  it("refuses values that miss a parameter", async () => {
    const result = await db.$decodeReadSet(set, {} as never, {});

    expect(result.error?.kind).toBe("invalid_request");
    expect(result.error?.message).toContain("db.$decodeReadSet(chrome)");
  });

  it("reports a single-row spec without a row", async () => {
    const result = await db.$decodeReadSet(set, values, { tag: { rows: [] } });

    expect(result.error).toMatchObject({ kind: "not_found" });
  });

  it("decodes the one row", async () => {
    const result = await db.$decodeReadSet(set, values, {
      tag: { rows: [{ id: "a" }] },
    });

    expect(result).toEqual(ok({ tag: { id: "a" } }));
  });
});
