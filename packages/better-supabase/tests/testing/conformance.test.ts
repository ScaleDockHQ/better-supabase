import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";

import type { AuthResolver } from "../../src/auth/resolve.ts";
import type { CacheAdapter } from "../../src/core/cache.ts";
import type { Executor } from "../../src/core/executor.ts";
import type { CloudEvent, EventSink } from "../../src/events/index.ts";
import type { Condition, Selection } from "../../src/ir/types.ts";

import {
  jsonSchema,
  resolveConfig,
  type Generator,
} from "../../src/config/index.ts";
import { memoryCache } from "../../src/core/cache.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import { err, ok } from "../../src/core/result.ts";
import { valibot } from "../../src/generators/valibot.ts";
import { zod } from "../../src/generators/zod.ts";
import { nextCache } from "../../src/next/index.ts";
import { actor } from "../../src/plugins/actor/index.ts";
import { softDelete } from "../../src/plugins/soft-delete/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { timestamps } from "../../src/plugins/timestamps/index.ts";
import { validation } from "../../src/plugins/validation/index.ts";
import { queryCache } from "../../src/query/index.ts";
import {
  ConformanceError,
  conform,
  expect as conformExpect,
  testAuthResolver,
  testCacheAdapter,
  testEventSink,
  testExecutor,
  testGenerator,
  testPlugin,
} from "../../src/testing/conformance.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { validators } from "../fixtures/generated-camel.zod.ts";

const ACME = "00000000-0000-4000-8000-000000000001";
const betterSupabase = defineSupabase(schema);

async function failures(pending: Promise<unknown>): Promise<string[]> {
  const error = await pending.then(
    () => undefined,
    (cause: unknown) => cause,
  );
  expect(error).toBeInstanceOf(ConformanceError);
  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

function memoryExecutor(rows: Record<string, unknown>[]): Executor {
  return {
    name: "memory",
    execute: (op, context) => {
      if (context.signal?.aborted)
        return Promise.resolve(err(dbError("aborted", "aborted")));
      if (op.table.name !== "tags")
        return Promise.resolve(
          err(dbError("not_found", `no table ${op.table.name}`)),
        );
      if (op.kind !== "select")
        return Promise.resolve(err(dbError("invalid_request", "read only")));
      const selected = rows
        .slice(0, op.limit)
        .map((row) =>
          Object.fromEntries(
            op.selection.columns.map((column) => [
              column.alias,
              row[column.column],
            ]),
          ),
        );
      return Promise.resolve(
        ok({ rows: op.head ? [] : selected, count: rows.length }),
      );
    },
  };
}

const tagRows = [
  { id: "1", organization_id: ACME, name: "a", color: "red" },
  { id: "2", organization_id: ACME, name: "b", color: "blue" },
  { id: "3", organization_id: ACME, name: "c", color: "gray" },
];

describe("testExecutor", () => {
  it("passes a conforming executor", async () => {
    const report = await testExecutor(memoryExecutor(tagRows), {
      betterSupabase,
      table: "tags",
    });
    expect(report.subject).toBe('Executor "memory"');
    expect(report.checks.map((check) => check.name)).toContain(
      "returns an aborted error for an aborted signal",
    );
  });

  it("reports every broken contract", async () => {
    const broken: Executor = {
      name: "broken",
      execute: (op) => {
        if (op.table.name !== "tags") throw new Error("boom");
        return Promise.resolve(
          ok({ rows: [{ id: "1", extra: true }, {}, {}], count: null }),
        );
      },
    };
    expect(
      await failures(testExecutor(broken, { betterSupabase, table: "tags" })),
    ).toEqual([
      "reads rows keyed by the selection aliases",
      "counts rows",
      "returns an aborted error for an aborted signal",
      "returns failures as results instead of throwing",
    ]);
  });
});

describe("testCacheAdapter", () => {
  it("passes the first-party adapters", async () => {
    await testCacheAdapter(memoryCache());
    await testCacheAdapter(nextCache());
    await testCacheAdapter(queryCache(new QueryClient()));
  });

  it("fails adapters that mutate targets or throw", async () => {
    const mutating: CacheAdapter = {
      name: "mutating",
      invalidate: (target) => {
        (target.ids as string[]).push("x");
      },
    };
    expect(await failures(testCacheAdapter(mutating))).toContain(
      "invalidates rows of a tenant",
    );
    const picky: CacheAdapter = {
      name: "picky",
      invalidate: (target) => {
        if (target.table.startsWith("__")) throw new Error("unknown table");
      },
    };
    expect(await failures(testCacheAdapter(picky))).toEqual([
      "accepts tables it has never seen",
    ]);
  });
});

describe("testEventSink", () => {
  it("passes a sink that delivers", async () => {
    const delivered: CloudEvent[] = [];
    const sink: EventSink = {
      send: (events) => void delivered.push(...events),
    };
    const report = await testEventSink(sink, { received: () => delivered });
    expect(report.checks).toHaveLength(3);
  });

  it("fails a sink that drops or mutates events", async () => {
    const dropping: EventSink = { send: () => {} };
    expect(
      await failures(testEventSink(dropping, { received: () => [] })),
    ).toEqual(["delivers every event"]);
    const mutating: EventSink = {
      send: (events) => {
        for (const event of events) (event as { id: string }).id = "x";
      },
    };
    expect(await failures(testEventSink(mutating))).toEqual([
      "accepts a batch without mutating it",
    ]);
  });
});

const request = (key?: string): Request =>
  new Request(
    "https://api.example.com/",
    key === undefined ? {} : { headers: { "x-api-key": key } },
  );

describe("testAuthResolver", () => {
  it("passes a resolver that fails closed", async () => {
    const apiKeys: AuthResolver = {
      name: "api-key",
      resolve: (incoming) => {
        const key = incoming.headers.get("x-api-key");
        if (key === null) return;
        return key === "good"
          ? { kind: "service", keyName: "ci" }
          : {
              kind: "invalid",
              error: dbError("unauthorized", "Invalid API key"),
            };
      },
    };
    await testAuthResolver(apiKeys, {
      invalid: [request("bad"), request("")],
      valid: [{ request: request("good") }],
    });
  });

  it("fails a resolver that downgrades bad keys to anon or throws", async () => {
    const lenient: AuthResolver = {
      name: "lenient",
      resolve: (incoming) => {
        const key = incoming.headers.get("x-api-key");
        if (key === "throw") throw new Error("database down");
        return key === null
          ? { kind: "anon", reason: "none" }
          : { kind: "anon", reason: "none" };
      },
    };
    expect(
      await failures(
        testAuthResolver(lenient, {
          invalid: [request("bad"), request("throw")],
        }),
      ),
    ).toEqual([
      "passes on requests without its credentials",
      "fails closed on invalid credentials",
    ]);
  });
});

describe("testGenerator", () => {
  const config = resolveConfig({ casing: "camel" }, "/project");

  it("passes the first-party generators", async () => {
    for (const generator of [zod(), valibot(), jsonSchema()]) {
      await testGenerator(generator, { meta: schema.meta, config });
    }
  });

  it("fails generators that escape the project or are not deterministic", async () => {
    let run = 0;
    const sloppy: Generator = {
      name: "sloppy",
      generate: () => {
        run += 1;
        return [
          { path: "../outside.ts", contents: `// run ${run}\n` },
          { path: "a.ts", contents: "" },
          { path: "a.ts", contents: "" },
        ];
      },
    };
    expect(
      await failures(testGenerator(sloppy, { meta: schema.meta, config })),
    ).toEqual([
      "writes files inside the project",
      "is deterministic and does not mutate its input",
    ]);
  });
});

describe("testPlugin", () => {
  const create = { organizationId: ACME, name: "conformance" };

  it("passes the first-party plugins", async () => {
    const context = {
      tenant: ACME,
      actor: { id: "user-1", kind: "user" as const },
    };
    for (const plugin of [
      timestamps(),
      softDelete(),
      tenant(),
      actor(),
      validation({ schemas: validators }),
    ]) {
      await testPlugin(plugin, {
        betterSupabase,
        table: "customers",
        context,
        create: { ...create, status: "lead" },
      });
    }
  });

  it("fails plugins that mutate operations or change results", async () => {
    const sneaky = definePlugin({
      name: "sneaky",
      transformQuery: (op) => {
        (op as { limit: number | undefined }).limit = 1;
        return op;
      },
      wrapExecutor: (inner) => ({
        name: "sneaky",
        execute: async (op, context) => {
          const result = await inner.execute(op, context);
          return result.ok ? ok({ ...result.data, rows: [] }) : result;
        },
      }),
    });
    expect(
      await failures(testPlugin(sneaky, { betterSupabase, table: "tags" })),
    ).toEqual([
      "transformQuery is pure and deterministic",
      "wrapExecutor keeps results intact",
    ]);
  });

  it("checks mapError and beforeMutation when the plugin has them", async () => {
    const mappers = definePlugin({
      name: "mappers",
      mapError: (raw, fallback) =>
        (raw as { code?: string }).code === "XX000" ? fallback : undefined,
      beforeMutation: (op) => op,
    });
    const report = await testPlugin(mappers, {
      betterSupabase,
      table: "tags",
      create: { organizationId: ACME, name: "x" },
    });
    expect(report.checks.map((check) => check.name)).toEqual([
      "has a name",
      "targets plugin API v1",
      "installs and builds repositories",
      "beforeMutation is pure and deterministic",
      "mapError returns a DbError or undefined",
    ]);

    let calls = 0;
    const broken = definePlugin({
      name: "broken",
      mapError: () => "nope" as never,
      beforeMutation: (op) => {
        calls += 1;
        return { ...op, rows: [{ call: calls }] } as never;
      },
    });
    expect(
      await failures(
        testPlugin(broken, {
          betterSupabase,
          table: "tags",
          create: { name: "x" },
        }),
      ),
    ).toEqual([
      "beforeMutation is pure and deterministic",
      "mapError returns a DbError or undefined",
    ]);
  });

  it("checks that afterMutation cannot change the result", async () => {
    const tamper = definePlugin({
      name: "tamper",
      afterMutation: (event) => {
        (event.rows[0] as Record<string, unknown>)["marker"] = "changed";
      },
    });
    const report = await testPlugin(tamper, {
      betterSupabase,
      table: "tags",
      create: { organizationId: ACME, name: "x" },
    });
    expect(report.checks.map((check) => check.name)).toContain(
      "afterMutation cannot change the result",
    );
  });

  it("rejects an unknown table and a wrong apiVersion", async () => {
    expect(() =>
      testPlugin(definePlugin({ name: "p" }), {
        betterSupabase,
        table: "nope",
      }),
    ).toThrow('better-supabase: unknown table "nope"');
    const old = { ...definePlugin({ name: "old" }), apiVersion: 0 as 1 };
    // betterSupabase.use() refuses the plugin too, so installing fails as well.
    expect(await failures(testPlugin(old, { betterSupabase }))).toEqual([
      "targets plugin API v1",
      "installs and builds repositories",
    ]);
  });
});

describe("conform", () => {
  it("reports non-Error throws and skips disabled checks", async () => {
    const error = await conform("Thing", [
      ["passes", () => undefined],
      false,
      undefined,
      [
        "throws a string",
        () => {
          // oxlint-disable-next-line typescript/only-throw-error -- the kit must report non-Error throws.
          throw "boom";
        },
      ],
      [
        "throws an Error",
        () => {
          throw new RangeError("bad");
        },
      ],
      [
        "violates",
        () => {
          conformExpect(false, "must hold");
        },
      ],
    ]).catch((cause: unknown) => cause);
    expect(error).toBeInstanceOf(ConformanceError);
    expect((error as Error).message).toBe(
      [
        "Thing failed 3 of 4 conformance checks:",
        "  - throws a string: threw boom",
        "  - throws an Error: threw RangeError: bad",
        "  - violates: must hold",
      ].join("\n"),
    );
    expect(await conform("Fine", [["ok", () => undefined]])).toEqual({
      subject: "Fine",
      checks: [{ name: "ok", ok: true }],
    });
  });
});

type Row = Record<string, unknown>;

function matches(row: Row, where: Condition | undefined): boolean {
  if (!where) return true;
  switch (where.kind) {
    case "and":
      return where.items.every((item) => matches(row, item));
    case "or":
      return where.items.some((item) => matches(row, item));
    case "not":
      return !matches(row, where.item);
    case "column":
      return where.op !== "eq" || row[where.column] === where.value;
    case "relation":
      return true;
    default: {
      const unknown: never = where;
      return unknown;
    }
  }
}

const project = (rows: readonly Row[], selection: Selection | undefined) =>
  rows.map((row) =>
    Object.fromEntries(
      (selection?.columns ?? []).map((column) => [
        column.alias,
        row[column.column],
      ]),
    ),
  );

/** An in-memory executor over `tags` that honours eq filters, writes and sources. */
function storeExecutor(
  seed: readonly Row[],
  quirks: {
    readonly rpcSucceeds?: boolean;
    readonly ignoresSource?: boolean;
    readonly batchDrops?: boolean;
    readonly keepsDeleted?: boolean;
    readonly renames?: boolean;
  } = {},
): Executor {
  const rows = seed.map((row) => ({ ...row }));
  let next = 100;
  const execute: Executor["execute"] = (op, context) => {
    if (context.signal?.aborted)
      return Promise.resolve(err(dbError("aborted", "aborted")));
    if (op.table.name !== "tags")
      return Promise.resolve(
        err(dbError("not_found", `no table ${op.table.name}`)),
      );
    switch (op.kind) {
      case "select": {
        if (op.source && !quirks.ignoresSource)
          return Promise.resolve(err(dbError("not_found", "no function")));
        const found = rows.filter((row) => matches(row, op.where));
        const limited = found.slice(0, op.limit);
        return Promise.resolve(
          ok({
            rows: op.head ? [] : project(limited, op.selection),
            count: found.length,
          }),
        );
      }
      case "insert": {
        const created = op.rows.map((row) => ({
          ...row,
          id: String((next += 1)),
          ...(quirks.renames ? { name: "renamed" } : {}),
        }));
        rows.push(...created);
        return Promise.resolve(
          ok({ rows: project(created, op.returning), count: created.length }),
        );
      }
      case "delete": {
        const removed = rows.filter((row) => matches(row, op.where));
        if (!quirks.keepsDeleted)
          for (const row of removed) rows.splice(rows.indexOf(row), 1);
        return Promise.resolve(
          ok({ rows: project(removed, op.returning), count: removed.length }),
        );
      }
      case "update":
        return Promise.resolve(err(dbError("invalid_request", "read only")));
      default: {
        const unknown: never = op;
        return unknown;
      }
    }
  };
  return {
    name: "store",
    functionSources: true,
    execute,
    rpc: () =>
      Promise.resolve(
        quirks.rpcSucceeds
          ? ok(null)
          : err(dbError("not_found", "no such function")),
      ),
    batch: async (ops, context) => {
      const results = await Promise.all(ops.map((op) => execute(op, context)));
      return quirks.batchDrops ? results.slice(0, 2) : results;
    },
  };
}

describe("testExecutor optional contracts", () => {
  it("passes rpc, source, batch and write round-trip checks", async () => {
    const report = await testExecutor(storeExecutor(tagRows), {
      betterSupabase,
      table: "tags",
      create: { organizationId: ACME, name: "fresh", color: "red" },
    });
    expect(report.checks.map((check) => check.name)).toEqual([
      "has a name",
      "reads rows keyed by the selection aliases",
      "counts rows",
      "returns an aborted error for an aborted signal",
      "returns failures as results instead of throwing",
      "returns rpc failures as results",
      "reads from SelectOp.source instead of the table",
      "batch returns one result per operation, in order",
      "round-trips a write",
    ]);
  });

  it("fails executors that break the optional contracts", async () => {
    const create = { organizationId: ACME, name: "fresh" };
    expect(
      await failures(
        testExecutor(
          storeExecutor(tagRows, {
            rpcSucceeds: true,
            ignoresSource: true,
            batchDrops: true,
            renames: true,
          }),
          { betterSupabase, table: "tags", create },
        ),
      ),
    ).toEqual([
      "returns rpc failures as results",
      "reads from SelectOp.source instead of the table",
      "batch returns one result per operation, in order",
      "round-trips a write",
    ]);
    const error = await testExecutor(
      storeExecutor(tagRows, { keepsDeleted: true }),
      { betterSupabase, table: "tags", create },
    ).catch((cause: unknown) => cause);
    expect((error as ConformanceError).report.checks.at(-1)).toEqual({
      name: "round-trips a write",
      ok: false,
      message: "the deleted row is still readable",
    });
  });

  it("defaults to the first table and rejects unknown ones", async () => {
    expect(() =>
      testExecutor(storeExecutor(tagRows), { betterSupabase, table: "nope" }),
    ).toThrow('better-supabase: unknown table "nope"');
    // The first table is not `tags`, so the memory executor fails its reads.
    expect(
      await failures(testExecutor(storeExecutor(tagRows), { betterSupabase })),
    ).toContain("reads rows keyed by the selection aliases");
  });
});

describe("testAuthResolver edge cases", () => {
  it("reports thrown non-Errors and the wrong user", async () => {
    const resolver: AuthResolver = {
      name: "odd",
      resolve: (incoming) => {
        const key = incoming.headers.get("x-api-key");
        if (key === null) return;
        // oxlint-disable-next-line typescript/only-throw-error -- the kit must report non-Error throws.
        if (key === "throw") throw "offline";
        return key === "user"
          ? {
              kind: "user",
              token: "t",
              claims: { sub: "u2" },
              user: { id: "u2" },
              source: "bearer",
              expiresAt: null,
            }
          : { kind: "invalid", error: dbError("unauthorized", "bad") };
      },
    };
    const error = await testAuthResolver(resolver, {
      invalid: [request("bad")],
      valid: [
        { request: request("user"), userId: "u1" },
        { request: request("throw") },
      ],
    }).catch((cause: unknown) => cause);
    expect((error as ConformanceError).report.checks.at(-1)).toEqual({
      name: "resolves valid credentials",
      ok: false,
      message: "expected user u1",
    });
    const thrown = await testAuthResolver(resolver, {
      invalid: [request("throw")],
      unrelated: new Request("https://example.com/other"),
    }).catch((cause: unknown) => cause);
    expect(
      (thrown as ConformanceError).report.checks.find((check) => !check.ok),
    ).toEqual({
      name: "fails closed on invalid credentials",
      ok: false,
      message: "resolve() threw: offline",
    });
    expect(await failures(testAuthResolver(resolver, { invalid: [] }))).toEqual(
      ["fails closed on invalid credentials"],
    );
  });
});

describe("testGenerator imports", () => {
  it("hands generators relative import paths and default inputs", async () => {
    const seen: string[] = [];
    const generator: Generator = {
      name: "imports",
      generate: (input) => {
        seen.push(
          input.importPath("src/lib/db.ts", "src/lib/schema.ts"),
          input.importPath("src/lib/db.ts", "src/gen/types.ts"),
          input.importPath("a/b.ts", "c.ts"),
        );
        return [{ path: "out.ts", contents: input.output }];
      },
    };
    await testGenerator(generator, { meta: schema.meta });
    expect(seen.slice(0, 3)).toEqual([
      "./schema.ts",
      "../gen/types.ts",
      "../c.ts",
    ]);
  });

  it("fails generators that return no array or bad file shapes", async () => {
    const bad: Generator = {
      name: "bad",
      generate: () => [{ path: "/abs.ts", contents: "" }],
    };
    expect(await failures(testGenerator(bad, { meta: schema.meta }))).toEqual([
      "writes files inside the project",
    ]);
    const windows: Generator = {
      name: "windows",
      generate: () => [{ path: "C:\\x.ts", contents: "" }],
    };
    expect(
      await failures(testGenerator(windows, { meta: schema.meta })),
    ).toEqual(["writes files inside the project"]);
    const malformed: Generator = {
      name: "malformed",
      generate: () => [{ path: 1, contents: "" }] as never,
    };
    expect(
      await failures(testGenerator(malformed, { meta: schema.meta })),
    ).toContain("writes files inside the project");
  });
});
