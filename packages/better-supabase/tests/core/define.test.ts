import { describe, expect, it } from "vitest";

import type {
  ExecuteContext,
  ExecuteResult,
  Executor,
  RpcContext,
} from "../../src/core/executor.ts";
import type { AnyPlugin } from "../../src/core/plugin.ts";
import type { StandardSchemaV1 } from "../../src/core/standard.ts";
import type { Operation } from "../../src/ir/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { err, ok, type Result } from "../../src/core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";

const sb = defineSupabase(schema);
const timeout = dbError("timeout", "slow");

interface Fake extends Executor {
  readonly ops: Operation[];
  readonly contexts: ExecuteContext[];
  readonly calls: { name: string; args: unknown; context: RpcContext }[];
}

function fake(
  options: {
    answer?: (op: Operation) => Result<ExecuteResult>;
    rpc?: (name: string, args: unknown) => Result<unknown>;
    functionSources?: boolean;
  } = {},
): Fake {
  const ops: Operation[] = [];
  const contexts: ExecuteContext[] = [];
  const calls: Fake["calls"] = [];
  return {
    name: "fake",
    ops,
    contexts,
    calls,
    ...(options.functionSources ? { functionSources: true } : {}),
    async execute(op, context) {
      ops.push(op);
      contexts.push(context);
      return options.answer ? options.answer(op) : ok({ rows: [], count: 0 });
    },
    ...(options.rpc
      ? {
          rpc: async (
            name: string,
            args: Readonly<Record<string, unknown>>,
            context: RpcContext,
          ) => {
            calls.push({ name, args, context });
            return options.rpc?.(name, args) ?? ok(null);
          },
        }
      : {}),
  };
}

const numberSchema: StandardSchemaV1<unknown, number> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "number"
        ? { value }
        : { issues: [{ message: "Expected a number" }] },
  },
};

describe("use", () => {
  it("rejects a plugin for another API version", () => {
    const plugin = { apiVersion: 2, name: "future" } as unknown as AnyPlugin;
    expect(() => sb.use(plugin)).toThrow(
      'better-supabase: plugin "future" targets plugin API v2; this version supports v1',
    );
  });

  it("rejects a plugin installed twice", () => {
    const plugin: AnyPlugin = { apiVersion: 1, name: "twice" };
    expect(() => sb.use(plugin).use(plugin)).toThrow(
      'better-supabase: plugin "twice" is already installed',
    );
  });

  it("rejects a plugin method that redefines a repository method", () => {
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "clash",
      repository: () => ({ findMany: () => 1 }),
    };
    const db = sb.use(plugin).connect(fake());
    expect(() => db.customers).toThrow(
      'better-supabase: plugin "clash" redefines "customers.findMany"',
    );
  });
});

describe("connect", () => {
  it("hands the configured clock and plugin error mappers to the runtime", async () => {
    const now = new Date("2026-05-01T00:00:00.000Z");
    const seen: Date[] = [];
    const mapError = () => undefined;
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "clock",
      mapError,
      transformQuery: (op, args) => {
        seen.push(args.now());
        return op;
      },
    };
    const executor = fake();
    await defineSupabase(schema, { now: () => now })
      .use(plugin)
      .connect(executor)
      .tags.count();
    expect(seen).toEqual([now]);
    expect(executor.contexts[0]?.errorMappers).toEqual([mapError]);
  });

  it("defaults the clock to the current time", async () => {
    const seen: Date[] = [];
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "clock",
      transformQuery: (op, args) => {
        seen.push(args.now());
        return op;
      },
    };
    const before = Date.now();
    await sb.use(plugin).connect(fake()).tags.count();
    expect(seen).toHaveLength(1);
    expect(seen[0]?.getTime()).toBeGreaterThanOrEqual(before);
  });

  it("rejects an unknown table in $table", () => {
    const db = sb.connect(fake());
    expect(db.$table("tags")).toBe(db.tags);
    expect(() => db.$table("nope" as never)).toThrow(
      /^better-supabase: unknown table "nope"\. Known: contacts, customerTags, customers/,
    );
  });

  it("extends a repository with methods built on it", async () => {
    const db = sb.connect(fake({ answer: () => ok({ rows: [], count: 9 }) }));
    const extended = db.tags.extend((base) => ({
      total: () => base.count(),
    }));
    expect(await extended.total()).toEqual(ok(9));
    expect(typeof extended.findMany).toBe("function");
  });

  it("leaves plugin methods that return plain values alone under mapError", () => {
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "plain",
      repository: () => ({ label: () => "tags" }),
    };
    const db = sb
      .use(plugin)
      .mapError(() => new Error("mapped"))
      .connect(fake()) as unknown as { tags: { label: () => string } };
    expect(db.tags.label()).toBe("tags");
  });
});

describe("$run", () => {
  it("rejects a value that is not a spec", async () => {
    expect(await sb.connect(fake()).$run({ v: 1 } as never)).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$run() expects a QuerySpec from sb.spec",
        ),
      ),
    );
  });

  it("rejects a spec for an unknown table", async () => {
    const spec = { v: 1, table: "nope", method: "findMany", args: [] };
    expect(await sb.connect(fake()).$run(spec as never)).toEqual(
      err(dbError("invalid_request", 'Unknown table "nope" in QuerySpec')),
    );
  });

  it("rejects a read-set spec that still holds placeholders", async () => {
    const set = defineReadSet(
      sb,
      "by_org",
      { params: { orgId: "uuid" } },
      (s, p) => ({
        tags: s.tags.count({ where: { organizationId: p.orgId } }),
      }),
    );
    const result = await sb.connect(fake()).$run(set.specs.tags);
    expect(result.error?.message).toBe(
      "This spec comes from a read set and still holds placeholders; run it with db.$many(readSet, params)",
    );
  });

  it.each([
    ["findById", sb.spec.tags.findById("t1")],
    ["findMany", sb.spec.tags.findMany({ select: ["id"] })],
  ] as const)(
    "passes the signal into the options of %s",
    async (_name, spec) => {
      const executor = fake({
        answer: () => ok({ rows: [{ id: "t1" }], count: null }),
      });
      const controller = new AbortController();
      await sb.connect(executor).$run(spec, { signal: controller.signal });
      expect(executor.contexts[0]?.signal).toBe(controller.signal);
    },
  );
});

describe("$many", () => {
  it("rejects a value that is neither a list nor a read set", async () => {
    expect(await sb.connect(fake()).$many("tags" as never)).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$many() expects an array of specs or a read set",
        ),
      ),
    );
  });

  it("names the first entry that is not a spec", async () => {
    expect(
      await sb.connect(fake()).$many([sb.spec.tags.count(), {} as never]),
    ).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$many() entry 1 is not a QuerySpec from sb.spec",
        ),
      ),
    );
  });

  it("returns the first failing entry", async () => {
    const executor = fake({
      answer: (op) =>
        op.table.key === "notes" ? err(timeout) : ok({ rows: [], count: 1 }),
    });
    const result = await sb
      .connect(executor)
      .$many([sb.spec.tags.count(), sb.spec.notes.count()]);
    expect(result.error).toEqual({ ...timeout, table: "notes" });
  });

  it("runs a single spec through the connected plugins", async () => {
    const seen: string[] = [];
    const plugin: AnyPlugin = {
      apiVersion: 1,
      name: "spy",
      transformQuery: (op) => {
        seen.push(op.table.key);
        return op;
      },
    };
    const result = await sb
      .use(plugin)
      .connect(fake())
      .$many([sb.spec.tags.count()]);
    expect(result).toEqual(ok([0]));
    expect(seen).toEqual(["tags"]);
  });
});

describe("$many with a read set", () => {
  const set = defineReadSet(
    sb,
    "chrome",
    { params: { orgId: "uuid" } },
    (s, p) => ({
      tags: s.tags.findMany({
        select: ["id"],
        where: { organizationId: p.orgId },
      }),
      tag: s.tags.findById(p.orgId, { select: ["id"] }),
    }),
  );
  const params = { orgId: "o1" };

  it("calls the read-set function with the parameters", async () => {
    const executor = fake({
      rpc: () =>
        ok({
          tags: { rows: [{ id: "t1" }] },
          tag: { rows: [{ id: "t1" }], count: null },
        }),
    });
    const controller = new AbortController();
    expect(
      await sb
        .connect(executor)
        .$many(set, params, { signal: controller.signal }),
    ).toEqual(ok({ tags: [{ id: "t1" }], tag: { id: "t1" } }));
    expect(executor.calls).toEqual([
      {
        name: "rs_chrome",
        args: { p: params },
        context: {
          schema: "public",
          get: true,
          errorMappers: [],
          signal: controller.signal,
        },
      },
    ]);
  });

  it("passes a failed call through", async () => {
    const executor = fake({ rpc: () => err(timeout) });
    expect(await sb.connect(executor).$many(set, params)).toEqual(err(timeout));
  });

  it.each<[string, unknown, string]>([
    [
      "a missing entry",
      { tags: { rows: [] } },
      'rs_chrome() returned no "tag". Run `better-supabase gen` and migrate.',
    ],
    [
      "nothing at all",
      null,
      'rs_chrome() returned no "tags". Run `better-supabase gen` and migrate.',
    ],
  ])("reports %s as unexpected", async (_name, payload, message) => {
    const executor = fake({ rpc: () => ok(payload) });
    expect(await sb.connect(executor).$many(set, params)).toEqual(
      err(dbError("unexpected", message)),
    );
  });

  it("returns an entry's own error, like findById without a row", async () => {
    const executor = fake({
      rpc: () => ok({ tags: { rows: null }, tag: { rows: [] } }),
    });
    const result = await sb.connect(executor).$many(set, params);
    expect(result.error).toMatchObject({ kind: "not_found", table: "tags" });
  });

  it("runs the bound specs when the executor has no rpc", async () => {
    const executor = fake({ answer: () => err(timeout) });
    const result = await sb.connect(executor).$many(set, params);
    expect(result.error).toEqual({ ...timeout, table: "tags" });
    expect(executor.ops.map((op) => op.table.key)).toEqual(["tags", "tags"]);
  });
});

describe("$search", () => {
  const vector = [0.1, 0.2];

  it("rejects an unknown table", async () => {
    expect(
      await sb
        .connect(fake({ functionSources: true }))
        .$search("nope" as never, { vector }),
    ).toEqual(
      err(dbError("invalid_request", 'db.$search(): unknown table "nope"')),
    );
  });

  it("rejects an executor without function sources", async () => {
    expect(await sb.connect(fake()).$search("notes", { vector })).toEqual(
      err(
        dbError(
          "invalid_request",
          "db.$search() reads from a function; the fake executor doesn't support that",
          { table: "notes" },
        ),
      ),
    );
  });

  it.each<[string, { vector: number[] | string; k?: number }]>([
    ["an empty vector", { vector: [] }],
    ["a non-finite vector", { vector: [Number.NaN] }],
    ["a malformed vector string", { vector: "0.1,0.2" }],
    ["a zero k", { vector, k: 0 }],
  ])("rejects %s", async (_name, args) => {
    expect(
      (await sb.connect(fake({ functionSources: true })).$search("notes", args))
        .error,
    ).toEqual(
      dbError(
        "invalid_input",
        "db.$search() needs a vector of finite numbers and a positive integer k",
        {
          table: "notes",
        },
      ),
    );
  });

  it("reads from the search function", async () => {
    const executor = fake({
      functionSources: true,
      answer: () => ok({ rows: [{ id: "1" }], count: null }),
    });
    expect(
      await sb.connect(executor).$search("notes", {
        vector: "[1,2]",
        k: 3,
        select: ["id"],
        where: { kind: "call" },
      }),
    ).toEqual(ok([{ id: "1" }]));
    expect(executor.ops[0]).toMatchObject({
      limit: 3,
      where: { kind: "column", column: "kind", op: "eq", value: "call" },
      source: {
        schema: "public",
        name: "search_notes",
        args: { query: "[1,2]", k: 3 },
      },
    });
  });

  it.each(["PGRST202", "42883"])(
    "hints at vectorSearch when the function is missing (%s)",
    async (code) => {
      const executor = fake({
        functionSources: true,
        answer: () => err(dbError("unexpected", "missing", { code })),
      });
      expect(
        (await sb.connect(executor).$search("notes", { vector })).error?.hint,
      ).toBe(
        'Add "public.notes" to vectorSearch in better-supabase.config.ts and run `better-supabase sql sync`.',
      );
    },
  );

  it("passes other errors through", async () => {
    const executor = fake({
      functionSources: true,
      answer: () => err(timeout),
    });
    expect(await sb.connect(executor).$search("notes", { vector })).toEqual(
      err({ ...timeout, table: "notes" }),
    );
  });
});

describe("$rpc", () => {
  it("fails on an executor without rpc", async () => {
    expect(
      await sb.connect(fake()).$rpc("search_notes" as never, {} as never),
    ).toEqual(
      err(dbError("invalid_request", 'Executor "fake" does not support rpc()')),
    );
  });

  it("calls the function with the schema and signal", async () => {
    const executor = fake({ rpc: () => ok(3) });
    const controller = new AbortController();
    const result = await sb
      .connect(executor)
      .$rpc("search_notes" as never, { q: 1 } as never, {
        schema: "api",
        signal: controller.signal,
      });
    expect(result).toEqual(ok(3));
    expect(executor.calls).toEqual([
      {
        name: "search_notes",
        args: { q: 1 },
        context: { schema: "api", errorMappers: [], signal: controller.signal },
      },
    ]);
  });

  it("defaults to the public schema and empty arguments", async () => {
    const executor = fake({ rpc: () => ok(null) });
    await sb
      .connect(executor)
      .$rpc("search_notes" as never, undefined as never);
    expect(executor.calls[0]).toMatchObject({
      args: {},
      context: { schema: "public" },
    });
  });

  it.each<[string, unknown, Result<unknown>]>([
    ["a valid result", 7, ok(7)],
    [
      "an invalid result",
      "seven",
      err(
        dbError("validation", "Invalid search_notes() result", {
          issues: [{ message: "Expected a number" }],
        }),
      ),
    ],
  ])("validates %s with returns", async (_name, value, expected) => {
    const executor = fake({ rpc: () => ok(value) });
    expect(
      await sb
        .connect(executor)
        .$rpc(
          "search_notes" as never,
          {} as never,
          { returns: numberSchema } as never,
        ),
    ).toEqual(expected);
  });

  it("skips validation when the call fails", async () => {
    const executor = fake({ rpc: () => err(timeout) });
    expect(
      await sb
        .connect(executor)
        .$rpc(
          "search_notes" as never,
          {} as never,
          { returns: numberSchema } as never,
        ),
    ).toEqual(err(timeout));
  });
});
