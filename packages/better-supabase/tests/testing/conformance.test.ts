import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";

import type { AuthResolver } from "../../src/auth/resolve.ts";
import type { CacheAdapter } from "../../src/core/cache.ts";
import type { Executor } from "../../src/core/executor.ts";
import type { CloudEvent, EventSink } from "../../src/events/index.ts";

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
const sb = defineSupabase(schema);

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
      sb,
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
    expect(await failures(testExecutor(broken, { sb, table: "tags" }))).toEqual(
      [
        "reads rows keyed by the selection aliases",
        "counts rows",
        "returns an aborted error for an aborted signal",
        "returns failures as results instead of throwing",
      ],
    );
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
        if (key === null) return undefined;
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
        sb,
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
    expect(await failures(testPlugin(sneaky, { sb, table: "tags" }))).toEqual([
      "transformQuery is pure and deterministic",
      "wrapExecutor keeps results intact",
    ]);
  });
});
